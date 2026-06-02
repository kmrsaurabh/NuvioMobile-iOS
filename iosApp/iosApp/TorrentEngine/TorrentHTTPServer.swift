// TorrentHTTPServer.swift
// NuvioMobile-iOS
//
// Embedded HTTP server for streaming torrent data to the local video player.
// Uses Apple's Network framework (NWListener/NWConnection) — no third-party deps.
// Supports HTTP Range requests (206 Partial Content) for seeking in video files.

import Foundation
import Network

// MARK: - TorrentDataProvider Protocol

/// Protocol implemented by torrent session objects to supply data to the HTTP server.
///
/// The HTTP server reads data through this protocol, decoupling it from
/// the torrent download implementation. Conforming types must be thread-safe.
@objc public protocol TorrentDataProvider: AnyObject {
    /// Total size of the file in bytes (from torrent metadata).
    var totalSize: Int64 { get }

    /// Currently available (downloaded) size in bytes.
    var availableSize: Int64 { get }

    /// Name of the file being streamed (used for Content-Disposition).
    var fileName: String { get }

    /// Reads data from the underlying torrent file.
    /// - Parameters:
    ///   - offset: Byte offset to start reading from.
    ///   - length: Number of bytes to read.
    /// - Returns: The requested data, or nil if the data is not yet available.
    func readData(offset: Int64, length: Int) -> Data?

    /// Blocks until the requested data range is available, or timeout expires.
    /// - Parameters:
    ///   - offset: Start byte offset of the range.
    ///   - length: Number of bytes needed.
    ///   - timeout: Maximum time to wait in seconds.
    /// - Returns: True if the data became available, false on timeout.
    func waitForData(offset: Int64, length: Int, timeout: TimeInterval) -> Bool
}

// MARK: - MIME Type Helper

/// Determines MIME type from file extension for Content-Type headers.
private func mimeType(forFileName name: String) -> String {
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "mp4", "m4v":      return "video/mp4"
    case "mkv":             return "video/x-matroska"
    case "avi":             return "video/x-msvideo"
    case "webm":            return "video/webm"
    case "mov":             return "video/quicktime"
    case "ts":              return "video/mp2t"
    case "flv":             return "video/x-flv"
    case "wmv":             return "video/x-ms-wmv"
    case "mp3":             return "audio/mpeg"
    case "flac":            return "audio/flac"
    case "aac":             return "audio/aac"
    case "ogg":             return "audio/ogg"
    case "srt":             return "text/plain; charset=utf-8"
    case "vtt":             return "text/vtt; charset=utf-8"
    default:                return "application/octet-stream"
    }
}

// MARK: - HTTP Request Parsing

/// Minimal parsed HTTP request — only what we need for range-based streaming.
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]

    /// Parses a raw HTTP request string into an HTTPRequest.
    static func parse(_ raw: String) -> HTTPRequest? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return HTTPRequest(method: method, path: path, headers: headers)
    }

    /// Parses the Range header into a (start, end?) tuple.
    /// Supports: `bytes=0-`, `bytes=0-999`, `bytes=500-`
    var rangeHeader: (start: Int64, end: Int64?)? {
        guard let range = headers["range"] else { return nil }
        let trimmed = range.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes=") else { return nil }

        let rangeSpec = String(trimmed.dropFirst(6))
        let rangeParts = rangeSpec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard rangeParts.count == 2 else { return nil }

        guard let start = Int64(rangeParts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        let endStr = rangeParts[1].trimmingCharacters(in: .whitespaces)
        let end = endStr.isEmpty ? nil : Int64(endStr)
        return (start, end)
    }
}

// MARK: - TorrentHTTPServer

/// Embedded HTTP server that streams torrent data over `127.0.0.1` to the local player.
///
/// Architecture:
/// - Uses `NWListener` from Apple's Network framework (no GCDWebServer dependency).
/// - Supports HTTP Range requests (206 Partial Content) for video seeking.
/// - Each active torrent session registers a `TorrentDataProvider` keyed by session ID.
/// - Stream URLs follow the pattern: `http://127.0.0.1:{port}/stream/{sessionId}`
///
/// Thread Safety:
/// - The session registry is protected by a serial `DispatchQueue`.
/// - Each connection is handled on the Network framework's internal queue.
@objc public class TorrentHTTPServer: NSObject {

    // MARK: - Constants

    /// Maximum chunk size for each data write (512 KB).
    /// Balances memory usage and write efficiency.
    private static let chunkSize: Int = 512 * 1024

    /// Timeout for waiting on torrent data availability (seconds).
    private static let dataWaitTimeout: TimeInterval = 30.0

    // MARK: - Properties

    /// The NWListener powering the HTTP server.
    private var listener: NWListener?

    /// The port the server is currently listening on.
    private(set) var port: UInt16 = 0

    /// Registry of active data providers keyed by session ID.
    private var providers: [String: TorrentDataProvider] = [:]

    /// Serial queue protecting the providers dictionary.
    private let registryQueue = DispatchQueue(label: "com.nuvio.torrent.httpserver.registry", qos: .userInitiated)

    /// Queue for handling network I/O.
    private let networkQueue = DispatchQueue(label: "com.nuvio.torrent.httpserver.network", qos: .userInitiated)

    /// Background queue for data reads (can be slow while waiting for pieces).
    private let dataQueue = DispatchQueue(label: "com.nuvio.torrent.httpserver.data", qos: .utility, attributes: .concurrent)

    /// Whether the server is currently running.
    private(set) var isRunning: Bool = false

    // MARK: - Lifecycle

    /// Starts the HTTP server on the specified port.
    /// - Parameter port: Port to listen on. Pass 0 for a random ephemeral port.
    /// - Returns: The actual port the server is listening on, or 0 on failure.
    @objc @discardableResult
    public func start(port: UInt16 = 0) -> UInt16 {
        guard !isRunning else {
            print("[HTTPServer] Already running on port \(self.port)")
            return self.port
        }

        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!
            )
            // Allow immediate port reuse after restart
            params.allowLocalEndpointReuse = true

            let newListener = try NWListener(using: params)

            let semaphore = DispatchSemaphore(value: 0)
            
            newListener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    semaphore.signal()
                } else if case .failed(_) = state {
                    semaphore.signal()
                }
                self?.handleListenerState(state)
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            newListener.start(queue: networkQueue)
            listener = newListener

            // Wait for the listener to become ready
            _ = semaphore.wait(timeout: .now() + 2.0)
            
            let resolvedPort = newListener.port?.rawValue ?? 0
            self.port = resolvedPort
            isRunning = true
            print("[HTTPServer] Started on port \(resolvedPort)")
            return resolvedPort

        } catch {
            print("[HTTPServer] Failed to start: \(error.localizedDescription)")
            return 0
        }
    }

    /// Stops the HTTP server and cancels all connections.
    @objc public func stop() {
        guard isRunning else { return }

        listener?.cancel()
        listener = nil
        isRunning = false

        registryQueue.sync {
            providers.removeAll()
        }

        print("[HTTPServer] Stopped")
    }

    // MARK: - Session Registry

    /// Registers a data provider for a torrent session.
    /// - Parameters:
    ///   - sessionId: The unique session ID for the torrent.
    ///   - provider: The data provider that will supply file data.
    @objc public func registerProvider(sessionId: String, provider: TorrentDataProvider) {
        registryQueue.async { [weak self] in
            self?.providers[sessionId] = provider
            print("[HTTPServer] Registered provider for session: \(sessionId)")
        }
    }

    /// Unregisters a data provider for a torrent session.
    /// - Parameter sessionId: The session ID to unregister.
    @objc public func unregisterProvider(sessionId: String) {
        registryQueue.async { [weak self] in
            self?.providers.removeValue(forKey: sessionId)
            print("[HTTPServer] Unregistered provider for session: \(sessionId)")
        }
    }

    /// Returns the stream URL for a given session.
    /// - Parameter sessionId: The session ID.
    /// - Returns: The local HTTP URL for streaming, e.g. `http://127.0.0.1:8080/stream/abc123`.
    @objc public func streamUrl(forSession sessionId: String) -> String {
        return "http://127.0.0.1:\(port)/stream/\(sessionId)"
    }

    /// Returns the number of currently registered providers.
    @objc public func activeSessionCount() -> Int {
        var count = 0
        registryQueue.sync {
            count = providers.count
        }
        return count
    }

    // MARK: - Listener State Handler

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let actualPort = listener?.port?.rawValue {
                self.port = actualPort
                print("[HTTPServer] Listener ready on port \(actualPort)")
            }
        case .failed(let error):
            print("[HTTPServer] Listener failed: \(error.localizedDescription)")
            isRunning = false
        case .cancelled:
            print("[HTTPServer] Listener cancelled")
            isRunning = false
        default:
            break
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: networkQueue)
        receiveRequest(on: connection)
    }

    /// Receives the full HTTP request data from a connection.
    private func receiveRequest(on connection: NWConnection) {
        // Receive up to 8KB of headers — more than enough for any request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if let error = error {
                print("[HTTPServer] Receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty,
                  let rawRequest = String(data: data, encoding: .utf8),
                  let request = HTTPRequest.parse(rawRequest) else {
                self.sendErrorResponse(connection: connection, statusCode: 400, message: "Bad Request")
                return
            }

            self.handleRequest(request, connection: connection)

            if isComplete {
                // Connection closed by client after sending request
            }
        }
    }

    // MARK: - Request Routing

    private func handleRequest(_ request: HTTPRequest, connection: NWConnection) {
        guard request.method == "GET" || request.method == "HEAD" else {
            sendErrorResponse(connection: connection, statusCode: 405, message: "Method Not Allowed")
            return
        }

        // Route: /stream/{sessionId}
        let pathComponents = request.path.split(separator: "/").map(String.init)
        guard pathComponents.count == 2, pathComponents[0] == "stream" else {
            sendErrorResponse(connection: connection, statusCode: 404, message: "Not Found")
            return
        }

        let sessionId = pathComponents[1]

        // Look up the provider
        var provider: TorrentDataProvider?
        registryQueue.sync {
            provider = providers[sessionId]
        }

        guard let dataProvider = provider else {
            sendErrorResponse(connection: connection, statusCode: 404, message: "Session Not Found")
            return
        }

        // Dispatch data serving to the data queue to avoid blocking network queue
        dataQueue.async { [weak self] in
            self?.serveStream(request: request, provider: dataProvider, connection: connection)
        }
    }

    // MARK: - Stream Serving

    /// Serves file data from the torrent provider, supporting range requests.
    private func serveStream(request: HTTPRequest, provider: TorrentDataProvider, connection: NWConnection) {
        let totalSize = provider.totalSize
        let contentType = mimeType(forFileName: provider.fileName)

        // Determine the byte range to serve
        let rangeStart: Int64
        let rangeEnd: Int64

        if let range = request.rangeHeader {
            rangeStart = range.start
            rangeEnd = range.end ?? (totalSize - 1)
        } else {
            rangeStart = 0
            rangeEnd = totalSize - 1
        }

        // Validate range
        guard rangeStart >= 0, rangeStart < totalSize, rangeEnd >= rangeStart, rangeEnd < totalSize else {
            let headers = "Content-Range: bytes */\(totalSize)\r\n"
            sendResponse(connection: connection, statusCode: 416, statusText: "Range Not Satisfiable",
                         headers: headers, body: nil)
            return
        }

        let contentLength = rangeEnd - rangeStart + 1
        let isRangeRequest = request.rangeHeader != nil

        // Build response headers
        var headerString = ""
        headerString += "Content-Type: \(contentType)\r\n"
        headerString += "Accept-Ranges: bytes\r\n"
        headerString += "Content-Length: \(contentLength)\r\n"
        headerString += "Connection: close\r\n"
        headerString += "Cache-Control: no-cache, no-store\r\n"

        if isRangeRequest {
            headerString += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalSize)\r\n"
        }

        let statusCode = isRangeRequest ? 206 : 200
        let statusText = isRangeRequest ? "Partial Content" : "OK"

        // For HEAD requests, send headers only
        if request.method == "HEAD" {
            sendResponse(connection: connection, statusCode: statusCode, statusText: statusText,
                         headers: headerString, body: nil)
            return
        }

        // Send response line and headers
        let responseLine = "HTTP/1.1 \(statusCode) \(statusText)\r\n\(headerString)\r\n"
        guard let headerData = responseLine.data(using: .utf8) else {
            connection.cancel()
            return
        }

        let sendGroup = DispatchGroup()
        sendGroup.enter()
        connection.send(content: headerData, completion: .contentProcessed { error in
            sendGroup.leave()
            if let error = error {
                print("[HTTPServer] Header send error: \(error.localizedDescription)")
            }
        })
        sendGroup.wait()

        // Stream the body in chunks
        var offset = rangeStart
        let endOffset = rangeEnd + 1 // exclusive

        while offset < endOffset {
            let remaining = Int(endOffset - offset)
            let chunkLength = min(remaining, Self.chunkSize)

            // Wait for data to become available (torrent may still be downloading)
            let dataAvailable = provider.waitForData(offset: offset, length: chunkLength, timeout: Self.dataWaitTimeout)
            guard dataAvailable else {
                print("[HTTPServer] Timeout waiting for data at offset \(offset)")
                break
            }

            guard let chunk = provider.readData(offset: offset, length: chunkLength) else {
                print("[HTTPServer] Failed to read data at offset \(offset), length \(chunkLength)")
                break
            }

            let chunkGroup = DispatchGroup()
            var sendError: NWError?
            chunkGroup.enter()
            connection.send(content: chunk, completion: .contentProcessed { error in
                sendError = error
                chunkGroup.leave()
            })
            chunkGroup.wait()

            if sendError != nil {
                // Client disconnected (e.g., user seeked)
                break
            }

            offset += Int64(chunk.count)
        }

        // Signal completion and close
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Response Helpers

    /// Sends a simple error response with a text body.
    private func sendErrorResponse(connection: NWConnection, statusCode: Int, message: String) {
        let body = message.data(using: .utf8)
        let headers = "Content-Type: text/plain\r\nContent-Length: \(body?.count ?? 0)\r\nConnection: close\r\n"
        sendResponse(connection: connection, statusCode: statusCode, statusText: message,
                     headers: headers, body: body)
    }

    /// Sends a complete HTTP response (headers + optional body) and closes the connection.
    private func sendResponse(connection: NWConnection, statusCode: Int, statusText: String,
                              headers: String, body: Data?) {
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n\(headers)\r\n"
        var responseData = response.data(using: .utf8) ?? Data()

        if let body = body {
            responseData.append(body)
        }

        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
