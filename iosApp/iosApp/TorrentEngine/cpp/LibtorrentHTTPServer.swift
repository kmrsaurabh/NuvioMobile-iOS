import Foundation
import Network

/// A lightweight HTTP server built on Network.framework to serve torrent files locally to MPV.
/// It parses HTTP Range requests, asks LibtorrentBridge to prioritize pieces, and streams the file.
@objc public class LibtorrentHTTPServer: NSObject {
    @objc public static let shared = LibtorrentHTTPServer()
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.nuvio.torrent.httpserver", qos: .userInteractive)
    private var connections: [NWConnection] = []
    private var fileHandles: [ObjectIdentifier: FileHandle] = [:]
    
    private var currentPort: Int = 0
    @objc public var port: Int { return currentPort }
    
    // Configurable paths
    private var downloadPath: String = ""
    
    private override init() {
        super.init()
    }
    
    @objc public func start(downloadPath: String) -> Int {
        self.downloadPath = downloadPath
        
        do {
            let parameters = NWParameters.tcp
            let listener = try NWListener(using: parameters)
            self.listener = listener
            
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.currentPort = Int(listener.port?.rawValue ?? 0)
                    print("[LibtorrentHTTPServer] Listening on port \(self?.currentPort ?? 0)")
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener.start(queue: queue)
            
            // Wait for port to be assigned
            var waitCount = 0
            while currentPort == 0 && waitCount < 10 {
                Thread.sleep(forTimeInterval: 0.1)
                waitCount += 1
            }
            
            return currentPort
        } catch {
            print("[LibtorrentHTTPServer] Failed to start: \(error)")
            return 0
        }
    }
    
    @objc public func stop() {
        listener?.cancel()
        listener = nil
        currentPort = 0
        
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        
        for (_, handle) in fileHandles {
            try? handle.close()
        }
        fileHandles.removeAll()
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .cancelled, .failed:
                self.cleanup(connection: connection)
            default: break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }
    
    private func cleanup(connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        if let fileHandle = fileHandles[id] {
            try? fileHandle.close()
            fileHandles.removeValue(forKey: id)
        }
        connections.removeAll(where: { $0 === connection })
    }
    
    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            
            if let requestString = String(data: data, encoding: .utf8) {
                self.processRequest(requestString, on: connection)
            } else {
                connection.cancel()
            }
        }
    }
    
    private func processRequest(_ request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            send400(on: connection)
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, (parts[0] == "GET" || parts[0] == "HEAD") else {
            send400(on: connection)
            return
        }
        
        let isHead = parts[0] == "HEAD"
        let path = parts[1]
        // path format: /stream/{hash}?fileIdx={idx}
        guard path.hasPrefix("/stream/") else {
            send404(on: connection)
            return
        }
        
        let hashAndQuery = path.dropFirst(8).components(separatedBy: "?")
        let hash = String(hashAndQuery[0])
        
        var fileIdx: Int32 = -1
        if hashAndQuery.count > 1 {
            let queryStr = hashAndQuery[1]
            let params = queryStr.components(separatedBy: "&")
            for param in params {
                let kv = param.components(separatedBy: "=")
                if kv.count == 2, kv[0] == "fileIdx", let idx = Int32(kv[1]) {
                    fileIdx = idx
                }
            }
        }
        
        // Parse Range header
        var rangeStart: Int64 = 0
        var rangeEnd: Int64 = -1
        var isPartial = false
        
        for line in lines {
            if line.lowercased().hasPrefix("range: bytes=") {
                let rangeStr = line.dropFirst(13)
                let rangeParts = rangeStr.components(separatedBy: "-")
                if let start = Int64(rangeParts[0]) {
                    rangeStart = start
                    isPartial = true
                }
                if rangeParts.count > 1, let end = Int64(rangeParts[1]) {
                    rangeEnd = end
                }
            }
        }
        
        waitForMetadataAndProcess(on: connection, isHead: isHead, hash: hash, fileIdx: fileIdx, rangeStart: rangeStart, rangeEnd: rangeEnd, isPartial: isPartial)
    }
    
    private func waitForMetadataAndProcess(on connection: NWConnection, isHead: Bool, hash: String, fileIdx: Int32, rangeStart: Int64, rangeEnd: Int64, isPartial: Bool) {
        
        let statusJson = LibtorrentBridge.shared().getStatusForHash(hash, magnetUri: "", fileIndex: fileIdx)
        guard let statusData = statusJson.data(using: .utf8),
              let statusObj = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let fileName = statusObj["fileName"] as? String,
              let fileSize = statusObj["totalSizeBytes"] as? Int64,
              let fileOffset = statusObj["fileOffset"] as? Int64,
              fileSize > 0 else {
            
            queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.waitForMetadataAndProcess(on: connection, isHead: isHead, hash: hash, fileIdx: fileIdx, rangeStart: rangeStart, rangeEnd: rangeEnd, isPartial: isPartial)
            }
            return
        }
        
        let filePath = (self.downloadPath as NSString).appendingPathComponent(fileName)
        let pieceLength = LibtorrentBridge.shared().pieceLength(forHash: hash)
        guard pieceLength > 0 else {
            queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.waitForMetadataAndProcess(on: connection, isHead: isHead, hash: hash, fileIdx: fileIdx, rangeStart: rangeStart, rangeEnd: rangeEnd, isPartial: isPartial)
            }
            return
        }
        
        var finalRangeEnd = rangeEnd
        if finalRangeEnd == -1 || finalRangeEnd >= fileSize {
            finalRangeEnd = fileSize - 1
        }
        
        let contentLength = finalRangeEnd - rangeStart + 1
        
        // Send Headers
        var response = ""
        if isPartial {
            response += "HTTP/1.1 206 Partial Content\r\n"
            response += "Content-Range: bytes \(rangeStart)-\(finalRangeEnd)/\(fileSize)\r\n"
        } else {
            response += "HTTP/1.1 200 OK\r\n"
        }
        
        response += "Content-Length: \(contentLength)\r\n"
        response += "Content-Type: \(inferContentType(from: fileName))\r\n"
        response += "Accept-Ranges: bytes\r\n"
        response += "Connection: keep-alive\r\n\r\n"
        
        if isHead {
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ error in
                connection.cancel()
            }))
            return
        }
        
        // Before sending headers, block until piece is downloaded (Poll every 250ms)
        // This prevents FFmpeg from timing out waiting for the body after receiving headers
        waitForPieceAndSendResponse(on: connection, responseHeader: response, filePath: filePath, hash: hash, pieceLength: Int64(pieceLength), currentOffset: rangeStart, fileOffset: fileOffset, remaining: contentLength)
    }
    
    private func waitForPieceAndSendResponse(on connection: NWConnection, responseHeader: String, filePath: String, hash: String, pieceLength: Int64, currentOffset: Int64, fileOffset: Int64, remaining: Int64) {
        let pieceIndex = Int32((fileOffset + currentOffset) / pieceLength)
        
        LibtorrentBridge.shared().setPieceDeadline(pieceIndex, forHash: hash, deadlineMs: Int32(500))
        let targetBuffer: Int64 = 15 * 1024 * 1024
        let maxLookahead = max(3, Int(targetBuffer / max(1, pieceLength)))
        
        for i in 1...maxLookahead {
            LibtorrentBridge.shared().setPieceDeadline(pieceIndex + Int32(i), forHash: hash, deadlineMs: Int32(500 + i * 200))
        }
        
        let hasPiece = LibtorrentBridge.shared().hasPiece(pieceIndex, forHash: hash)
        
        if hasPiece {
            // Piece is ready, send HTTP headers, then start streaming
            connection.send(content: responseHeader.data(using: .utf8), completion: .contentProcessed({ [weak self] error in
                if error == nil {
                    self?.streamData(on: connection, filePath: filePath, hash: hash, pieceLength: pieceLength, currentOffset: currentOffset, fileOffset: fileOffset, remaining: remaining)
                } else {
                    connection.cancel()
                }
            }))
            return
        }
        
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitForPieceAndSendResponse(on: connection, responseHeader: responseHeader, filePath: filePath, hash: hash, pieceLength: pieceLength, currentOffset: currentOffset, fileOffset: fileOffset, remaining: remaining)
        }
    }
    
    private func streamData(on connection: NWConnection, filePath: String, hash: String, pieceLength: Int64, currentOffset: Int64, fileOffset: Int64, remaining: Int64) {
        if remaining <= 0 {
            connection.cancel()
            return
        }
        
        let pieceIndex = Int32((fileOffset + currentOffset) / pieceLength)
        
        // Prioritize this piece with a 500ms deadline
        LibtorrentBridge.shared().setPieceDeadline(pieceIndex, forHash: hash, deadlineMs: Int32(500))
        
        // Also prioritize the next few pieces to keep a buffer ahead
        let targetBuffer: Int64 = 15 * 1024 * 1024
        let maxLookahead = max(3, Int(targetBuffer / max(1, pieceLength)))
        for i in 1...maxLookahead {
            let aheadIndex = pieceIndex + Int32(i)
            LibtorrentBridge.shared().setPieceDeadline(aheadIndex, forHash: hash, deadlineMs: Int32(500 + i * 200))
        }
        
        // Check if piece is ready and send
        checkPieceReadyAndSend(on: connection, filePath: filePath, hash: hash, pieceIndex: pieceIndex, pieceLength: pieceLength, currentOffset: currentOffset, fileOffset: fileOffset, remaining: remaining)
    }
    
    private func checkPieceReadyAndSend(on connection: NWConnection, filePath: String, hash: String, pieceIndex: Int32, pieceLength: Int64, currentOffset: Int64, fileOffset: Int64, remaining: Int64) {
        
        let hasPiece = LibtorrentBridge.shared().hasPiece(pieceIndex, forHash: hash)
        
        if hasPiece {
            // Get cached file handle or open a new one
            let id = ObjectIdentifier(connection)
            var fileHandle = self.fileHandles[id]
            if fileHandle == nil {
                fileHandle = FileHandle(forReadingAtPath: filePath)
                self.fileHandles[id] = fileHandle
            }
            
            if let fileHandle = fileHandle {
                do {
                    try fileHandle.seek(toOffset: UInt64(currentOffset))
                    
                    let pieceOffset = (fileOffset + currentOffset) % pieceLength
                    let bytesToRead = min(remaining, pieceLength - pieceOffset)
                    let maxChunk = Int64(1024 * 1024) // 1MB chunks
                    let chunkToRead = min(bytesToRead, maxChunk)
                    
                    var contentData: Data? = nil
                    autoreleasepool {
                        if #available(iOS 13.4, *) {
                            contentData = try? fileHandle.read(upToCount: Int(chunkToRead))
                        } else {
                            contentData = fileHandle.readData(ofLength: Int(chunkToRead))
                        }
                    }
                    
                    guard let data = contentData, !data.isEmpty else {
                        // EOF
                        connection.cancel()
                        return
                    }
                    
                    connection.send(content: data, completion: .contentProcessed({ [weak self] error in
                        if error == nil {
                            self?.streamData(on: connection, filePath: filePath, hash: hash, pieceLength: pieceLength, currentOffset: currentOffset + chunkToRead, fileOffset: fileOffset, remaining: remaining - chunkToRead)
                        } else {
                            connection.cancel()
                        }
                    }))
                    return
                } catch {
                    print("[LibtorrentHTTPServer] File seek/read error: \(error)")
                }
            } else {
                // File might not be created on disk yet by libtorrent, keep waiting
            }
        }
        
        // Wait and check again
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.checkPieceReadyAndSend(on: connection, filePath: filePath, hash: hash, pieceIndex: pieceIndex, pieceLength: pieceLength, currentOffset: currentOffset, fileOffset: fileOffset, remaining: remaining)
        }
    }
    
    private func send400(on connection: NWConnection) {
        let response = "HTTP/1.1 400 Bad Request\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
    }
    
    private func send404(on connection: NWConnection) {
        let response = "HTTP/1.1 404 Not Found\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
    }
    
    private func send500(on connection: NWConnection) {
        let response = "HTTP/1.1 500 Internal Error\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
    }

    private func inferContentType(from fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v": return "video/mp4"
        case "mkv": return "video/x-matroska"
        case "avi": return "video/x-msvideo"
        case "webm": return "video/webm"
        case "ts": return "video/mp2t"
        case "mov": return "video/quicktime"
        case "flv": return "video/x-flv"
        case "wmv": return "video/x-ms-wmv"
        default: return "application/octet-stream"
        }
    }
}
