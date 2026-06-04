import Foundation
import Network

/// A lightweight HTTP server built on Network.framework to serve torrent files locally to MPV.
/// It parses HTTP Range requests, asks LibtorrentBridge to prioritize pieces, and streams the file.
@objc public class LibtorrentHTTPServer: NSObject {
    @objc public static let shared = LibtorrentHTTPServer()
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.nuvio.torrent.httpserver", qos: .userInteractive)
    private var connections: [NWConnection] = []
    
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
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receiveRequest(on: connection)
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
        guard parts.count >= 2, parts[0] == "GET" else {
            send400(on: connection)
            return
        }
        
        let path = parts[1]
        // path format: /stream/{hash}?fileIdx={idx}
        guard path.hasPrefix("/stream/") else {
            send404(on: connection)
            return
        }
        
        // Parse hash and fileIdx (simplified parsing for now)
        let hashAndQuery = path.dropFirst(8).components(separatedBy: "?")
        let hash = String(hashAndQuery[0])
        
        // Get status from bridge to find file name and size
        let statusJson = LibtorrentBridge.shared().getStatusForHash(hash, magnetUri: "", fileIndex: Int32(-1))
        guard let statusData = statusJson.data(using: .utf8),
              let statusObj = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let fileName = statusObj["fileName"] as? String,
              let fileSize = statusObj["totalSizeBytes"] as? Int64 else {
            send404(on: connection)
            return
        }
        
        let filePath = (self.downloadPath as NSString).appendingPathComponent(fileName)
        let pieceLength = LibtorrentBridge.shared().pieceLength(forHash: hash)
        guard pieceLength > 0 else {
            send500(on: connection)
            return
        }
        
        // Parse Range header
        var rangeStart: Int64 = 0
        var rangeEnd: Int64 = fileSize - 1
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
        
        let contentLength = rangeEnd - rangeStart + 1
        
        // Send Headers
        var response = ""
        if isPartial {
            response += "HTTP/1.1 206 Partial Content\r\n"
            response += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(fileSize)\r\n"
        } else {
            response += "HTTP/1.1 200 OK\r\n"
        }
        
        response += "Content-Length: \(contentLength)\r\n"
        response += "Content-Type: video/mp4\r\n" // simplified
        response += "Accept-Ranges: bytes\r\n"
        response += "Connection: keep-alive\r\n\r\n"
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ [weak self] error in
            if error == nil {
                self?.streamData(on: connection, filePath: filePath, hash: hash, pieceLength: Int64(pieceLength), currentOffset: rangeStart, remaining: contentLength)
            } else {
                connection.cancel()
            }
        }))
    }
    
    private func streamData(on connection: NWConnection, filePath: String, hash: String, pieceLength: Int64, currentOffset: Int64, remaining: Int64) {
        if remaining <= 0 {
            connection.cancel()
            return
        }
        
        let pieceIndex = Int32(currentOffset / pieceLength)
        
        // Prioritize this piece with a 500ms deadline
        LibtorrentBridge.shared().setPieceDeadline(pieceIndex, forHash: hash, deadlineMs: Int32(500))
        
        // Also prioritize the next few pieces to keep a buffer ahead
        let maxLookahead = 3
        for i in 1...maxLookahead {
            let aheadIndex = pieceIndex + Int32(i)
            LibtorrentBridge.shared().setPieceDeadline(aheadIndex, forHash: hash, deadlineMs: Int32(500 + i * 200))
        }
        
        // Block until piece is downloaded (Poll every 100ms)
        // Warning: Polling in NWConnection callback queue is okay here since we use QoS .userInteractive and multiple threads,
        // but typically should use an async sleep.
        checkPieceReadyAndSend(on: connection, filePath: filePath, hash: hash, pieceIndex: pieceIndex, pieceLength: pieceLength, currentOffset: currentOffset, remaining: remaining, attempts: 0)
    }
    
    private func checkPieceReadyAndSend(on connection: NWConnection, filePath: String, hash: String, pieceIndex: Int32, pieceLength: Int64, currentOffset: Int64, remaining: Int64, attempts: Int) {
        
        let hasPiece = LibtorrentBridge.shared().hasPiece(pieceIndex, forHash: hash)
        
        if hasPiece {
            // Read piece from disk
            if let fileHandle = FileHandle(forReadingAtPath: filePath) {
                defer { try? fileHandle.close() }
                
                do {
                    try fileHandle.seek(toOffset: UInt64(currentOffset))
                    
                    let pieceOffset = currentOffset % pieceLength
                    let bytesToRead = min(remaining, pieceLength - pieceOffset)
                    let maxChunk = Int64(1024 * 1024) // 1MB chunks
                    let chunkToRead = min(bytesToRead, maxChunk)
                    
                    let data = fileHandle.readData(ofLength: Int(chunkToRead))
                    if data.isEmpty {
                        // EOF
                        connection.cancel()
                        return
                    }
                    
                    connection.send(content: data, completion: .contentProcessed({ [weak self] error in
                        if error == nil {
                            self?.streamData(on: connection, filePath: filePath, hash: hash, pieceLength: pieceLength, currentOffset: currentOffset + chunkToRead, remaining: remaining - chunkToRead)
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
        
        if attempts > 300 { // 30 seconds timeout
            print("[LibtorrentHTTPServer] Timeout waiting for piece \(pieceIndex)")
            connection.cancel()
            return
        }
        
        // Wait and check again
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.checkPieceReadyAndSend(on: connection, filePath: filePath, hash: hash, pieceIndex: pieceIndex, pieceLength: pieceLength, currentOffset: currentOffset, remaining: remaining, attempts: attempts + 1)
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
}
