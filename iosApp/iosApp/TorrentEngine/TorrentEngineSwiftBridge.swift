// TorrentEngineSwiftBridge.swift
// NuvioMobile-iOS
//
// Main Swift bridge for the P2P torrent streaming engine.
// Kotlin calls this class via ObjC interop to manage torrent sessions,
// an embedded HTTP server, and piece-level streaming prioritization.
//
// Architecture:
//   Kotlin (ComposeApp) --> ObjC interop --> TorrentEngineSwiftBridge
//     ├── LibTorrentSession (C API abstraction, placeholder)
//     ├── TorrentHTTPServer (NWListener-based streaming)
//     ├── TorrentPiecePrioritizer (streaming-optimized download)
//     └── TorrentDiskCacheManager (LRU disk cache)

import Foundation

// MARK: - Configuration Models

/// Engine configuration decoded from JSON passed by Kotlin.
private struct TorrentEngineConfig: Codable {
    /// Port for the HTTP streaming server (0 = random ephemeral).
    var httpPort: UInt16 = 0
    /// Maximum number of concurrent torrent sessions.
    var maxActiveTorrents: Int = 3
    /// Maximum disk cache size in bytes (default 2 GB).
    var maxCacheSizeBytes: Int64 = 2 * 1024 * 1024 * 1024
    /// Maximum download rate in bytes/sec (0 = unlimited).
    var maxDownloadRate: Int = 0
    /// Maximum upload rate in bytes/sec (0 = unlimited).
    var maxUploadRate: Int = 0
    /// Maximum number of peer connections per torrent.
    var maxPeerConnections: Int = 80
    /// Whether to enable DHT.
    var enableDHT: Bool = true
    /// Libtorrent alert mask (for debugging; 0 = defaults).
    var alertMask: Int = 0
}

// MARK: - Session State Models

/// State of a single torrent session, returned to Kotlin as JSON.
private struct TorrentSessionState: Codable {
    let sessionId: String
    let infoHash: String
    let magnetUri: String
    let fileIndex: Int
    var status: TorrentStatus
    var streamUrl: String
    var fileName: String
    var totalSizeBytes: Int64
    var downloadedBytes: Int64
    var downloadRate: Int64        // bytes/sec
    var uploadRate: Int64          // bytes/sec
    var numPeers: Int
    var numSeeds: Int
    var progress: Double           // 0.0 - 1.0
    var isMetadataResolved: Bool
    var isStreaming: Bool
    var errorMessage: String?
}

/// High-level status of a torrent session.
private enum TorrentStatus: String, Codable {
    case initializing
    case resolvingMetadata = "resolving_metadata"
    case downloading
    case streaming
    case paused
    case completed
    case error
    case stopped
}

/// Aggregated engine statistics returned to Kotlin as JSON.
private struct EngineStats: Codable {
    let activeSessions: Int
    let totalDownloadRate: Int64
    let totalUploadRate: Int64
    let httpServerPort: UInt16
    let httpServerRunning: Bool
    let cacheStats: CacheStats
}

private struct CacheStats: Codable {
    let entryCount: Int
    let totalSizeBytes: Int64
    let maxSizeBytes: Int64
}

// MARK: - LibTorrent Session Abstraction (Placeholder)

/// Clean abstraction over the libtorrent C API.
///
/// This class contains placeholder implementations that return simulated values.
/// When `LibTorrent.xcframework` is integrated, replace the placeholder bodies
/// with actual C API calls (e.g., `lt_session_create()`, `lt_add_torrent()`, etc.).
///
/// The interface is designed to map 1:1 to the libtorrent C API, making the
/// eventual integration straightforward.
private class LibTorrentSession {

    /// Opaque handle to the libtorrent session (will be `OpaquePointer?` when connected).
    private var sessionHandle: UnsafeMutableRawPointer?

    /// Whether the session has been started.
    private(set) var isActive: Bool = false

    /// Creates and configures the libtorrent session.
    /// - Parameters:
    ///   - config: Engine configuration.
    func create(config: TorrentEngineConfig) {
        // PLACEHOLDER: Replace with actual C API call
        // sessionHandle = lt_session_create()
        // lt_session_set_download_rate_limit(sessionHandle, config.maxDownloadRate)
        // lt_session_set_upload_rate_limit(sessionHandle, config.maxUploadRate)
        // if config.enableDHT { lt_session_start_dht(sessionHandle) }
        print("[LibTorrent] Session created (placeholder)")
        isActive = true
    }

    /// Adds a torrent by magnet URI.
    /// - Parameters:
    ///   - magnetUri: The magnet URI string.
    ///   - savePath: Directory to save downloaded data.
    ///   - fileIndex: Index of the file to prioritize (-1 for largest).
    /// - Returns: An opaque torrent handle, or nil on failure.
    func addTorrent(magnetUri: String, savePath: String, fileIndex: Int) -> UnsafeMutableRawPointer? {
        // PLACEHOLDER: Replace with actual C API call
        // let params = lt_parse_magnet_uri(magnetUri)
        // lt_add_torrent_params_set_save_path(params, savePath)
        // let handle = lt_session_add_torrent(sessionHandle, params)
        // return handle
        print("[LibTorrent] Added torrent: \(magnetUri.prefix(60))... (placeholder)")
        // Return a dummy non-nil handle for tracking
        return UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    }

    /// Removes a torrent from the session.
    /// - Parameters:
    ///   - handle: The torrent handle returned by `addTorrent`.
    ///   - deleteFiles: Whether to also delete downloaded files.
    func removeTorrent(handle: UnsafeMutableRawPointer, deleteFiles: Bool = false) {
        // PLACEHOLDER: Replace with actual C API call
        // lt_session_remove_torrent(sessionHandle, handle, deleteFiles ? 1 : 0)
        handle.deallocate()
        print("[LibTorrent] Removed torrent (placeholder)")
    }

    /// Sets the piece priority for a torrent.
    /// - Parameters:
    ///   - handle: The torrent handle.
    ///   - pieceIndex: The piece index.
    ///   - priority: Priority value (0-7).
    func setPiecePriority(handle: UnsafeMutableRawPointer, pieceIndex: Int, priority: Int32) {
        // PLACEHOLDER: Replace with actual C API call
        // lt_torrent_set_piece_priority(handle, pieceIndex, priority)
    }

    /// Returns whether a torrent's metadata has been resolved.
    func hasMetadata(handle: UnsafeMutableRawPointer) -> Bool {
        // PLACEHOLDER: Replace with actual C API call
        // return lt_torrent_has_metadata(handle) != 0
        return true
    }

    /// Returns the total number of pieces for a torrent.
    func totalPieces(handle: UnsafeMutableRawPointer) -> Int {
        // PLACEHOLDER
        // return Int(lt_torrent_num_pieces(handle))
        return 1000
    }

    /// Returns the piece length in bytes.
    func pieceLength(handle: UnsafeMutableRawPointer) -> Int {
        // PLACEHOLDER
        // return Int(lt_torrent_piece_length(handle))
        return 256 * 1024  // 256 KB
    }

    /// Returns the total file size in bytes.
    func totalSize(handle: UnsafeMutableRawPointer, fileIndex: Int) -> Int64 {
        // PLACEHOLDER
        // return lt_torrent_file_size(handle, fileIndex)
        return Int64(1000 * 256 * 1024) // 256 MB placeholder
    }

    /// Returns the file name.
    func fileName(handle: UnsafeMutableRawPointer, fileIndex: Int) -> String {
        // PLACEHOLDER
        // let cStr = lt_torrent_file_name(handle, fileIndex)
        // return String(cString: cStr)
        return "video.mkv"
    }

    /// Returns download rate in bytes/sec.
    func downloadRate(handle: UnsafeMutableRawPointer) -> Int64 {
        // PLACEHOLDER
        return 0
    }

    /// Returns upload rate in bytes/sec.
    func uploadRate(handle: UnsafeMutableRawPointer) -> Int64 {
        // PLACEHOLDER
        return 0
    }

    /// Returns the number of connected peers.
    func numPeers(handle: UnsafeMutableRawPointer) -> Int {
        // PLACEHOLDER
        return 0
    }

    /// Returns the number of connected seeds.
    func numSeeds(handle: UnsafeMutableRawPointer) -> Int {
        // PLACEHOLDER
        return 0
    }

    /// Returns download progress (0.0 - 1.0).
    func progress(handle: UnsafeMutableRawPointer) -> Double {
        // PLACEHOLDER
        return 0.0
    }

    /// Returns the total downloaded bytes.
    func downloadedBytes(handle: UnsafeMutableRawPointer) -> Int64 {
        // PLACEHOLDER
        return 0
    }

    /// Sets sequential download mode.
    func setSequentialDownload(handle: UnsafeMutableRawPointer, enabled: Bool) {
        // PLACEHOLDER
        // lt_torrent_set_sequential_download(handle, enabled ? 1 : 0)
        print("[LibTorrent] Sequential download \(enabled ? "enabled" : "disabled") (placeholder)")
    }

    /// Destroys the libtorrent session.
    func destroy() {
        // PLACEHOLDER
        // lt_session_destroy(sessionHandle)
        sessionHandle = nil
        isActive = false
        print("[LibTorrent] Session destroyed (placeholder)")
    }
}

// MARK: - Torrent Session Data Provider

/// Bridges a torrent session to the HTTP server by conforming to `TorrentDataProvider`.
///
/// Reads data from the downloaded file on disk and reports availability based on
/// the libtorrent download progress.
private class TorrentSessionDataProvider: NSObject, TorrentDataProvider {

    let sessionId: String
    private let savePath: URL
    private let _fileName: String
    private let _totalSize: Int64
    private var fileHandle: FileHandle?
    private let fileLock = NSLock()

    /// Condition variable signaled when new pieces complete downloading.
    private let dataCondition = NSCondition()

    /// Track the furthest contiguous byte available.
    private var _availableSize: Int64 = 0

    init(sessionId: String, savePath: URL, fileName: String, totalSize: Int64) {
        self.sessionId = sessionId
        self.savePath = savePath
        self._fileName = fileName
        self._totalSize = totalSize
        super.init()
        openFileIfNeeded()
    }

    deinit {
        fileLock.lock()
        try? fileHandle?.close()
        fileHandle = nil
        fileLock.unlock()
    }

    // MARK: - TorrentDataProvider

    var totalSize: Int64 { _totalSize }

    var availableSize: Int64 {
        dataCondition.lock()
        defer { dataCondition.unlock() }
        return _availableSize
    }

    var fileName: String { _fileName }

    func readData(offset: Int64, length: Int) -> Data? {
        fileLock.lock()
        defer { fileLock.unlock() }

        guard let handle = fileHandle else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = handle.readData(ofLength: length)
            return data.isEmpty ? nil : data
        } catch {
            print("[DataProvider:\(sessionId)] Read error at offset \(offset): \(error.localizedDescription)")
            return nil
        }
    }

    func waitForData(offset: Int64, length: Int, timeout: TimeInterval) -> Bool {
        let requiredEnd = offset + Int64(length)

        dataCondition.lock()
        defer { dataCondition.unlock() }

        if _availableSize >= requiredEnd || _availableSize >= _totalSize {
            return true
        }

        // Wait until enough data is available or timeout
        let deadline = Date(timeIntervalSinceNow: timeout)
        while _availableSize < requiredEnd && _availableSize < _totalSize {
            if !dataCondition.wait(until: deadline) {
                // Timed out
                return _availableSize >= requiredEnd
            }
        }

        return _availableSize >= requiredEnd || _availableSize >= _totalSize
    }

    // MARK: - Internal Updates

    /// Called by the engine when new data becomes available.
    func updateAvailableSize(_ newSize: Int64) {
        dataCondition.lock()
        _availableSize = newSize
        dataCondition.broadcast()
        dataCondition.unlock()
    }

    // MARK: - File Handle Management

    private func openFileIfNeeded() {
        fileLock.lock()
        defer { fileLock.unlock() }

        let filePath = savePath.appendingPathComponent(_fileName)
        if FileManager.default.fileExists(atPath: filePath.path) {
            fileHandle = try? FileHandle(forReadingFrom: filePath)
        }
    }

    /// Re-opens the file handle (e.g., after the file is first created by libtorrent).
    func reopenFile() {
        fileLock.lock()
        try? fileHandle?.close()
        let filePath = savePath.appendingPathComponent(_fileName)
        fileHandle = try? FileHandle(forReadingFrom: filePath)
        fileLock.unlock()
    }
}

// MARK: - Active Session Container

/// Internal container tracking all state for an active torrent session.
private class ActiveTorrentSession {
    let sessionId: String
    let infoHash: String
    let magnetUri: String
    let fileIndex: Int
    var state: TorrentSessionState
    var torrentHandle: UnsafeMutableRawPointer?
    var prioritizer: TorrentPiecePrioritizer?
    var dataProvider: TorrentSessionDataProvider?

    init(sessionId: String, infoHash: String, magnetUri: String, fileIndex: Int, state: TorrentSessionState) {
        self.sessionId = sessionId
        self.infoHash = infoHash
        self.magnetUri = magnetUri
        self.fileIndex = fileIndex
        self.state = state
    }
}

// MARK: - TorrentEngineSwiftBridge

/// Main Swift bridge for the P2P torrent streaming engine.
///
/// Kotlin calls this class via ObjC interop (similar to `NuvioPlayerBridgeFactory`).
/// Manages:
/// - libtorrent session lifecycle (via `LibTorrentSession` abstraction)
/// - Embedded HTTP streaming server (`TorrentHTTPServer`)
/// - Active torrent sessions with streaming-optimized prioritization
/// - Disk cache with LRU eviction
///
/// All methods are thread-safe, using a serial GCD queue for state mutations.
@objc public class TorrentEngineSwiftBridge: NSObject {

    // MARK: - Singleton

    /// Shared instance (Kotlin may hold its own reference, but this ensures a single engine).
    @objc public static let shared = TorrentEngineSwiftBridge()

    // MARK: - Properties

    /// Serial queue for all engine state mutations.
    private let engineQueue = DispatchQueue(label: "com.nuvio.torrent.engine", qos: .userInitiated)

    /// The libtorrent session abstraction.
    private let ltSession = LibTorrentSession()

    /// Embedded HTTP server for streaming.
    private let httpServer = TorrentHTTPServer()

    /// Disk cache manager.
    private var cacheManager: TorrentDiskCacheManager?

    /// Active torrent sessions keyed by session ID.
    private var activeSessions: [String: ActiveTorrentSession] = [:]

    /// Engine configuration.
    private var config = TorrentEngineConfig()

    /// Whether the engine has been started.
    @objc public private(set) var isStarted: Bool = false

    /// Counter for generating unique session IDs.
    private var sessionCounter: UInt64 = 0

    /// JSON encoder for returning status to Kotlin.
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// JSON decoder for parsing config from Kotlin.
    private let jsonDecoder = JSONDecoder()

    // MARK: - Initialization

    private override init() {
        super.init()
        print("[TorrentEngine] Bridge initialized")
    }

    // MARK: - Engine Lifecycle

    /// Starts the torrent engine with the given JSON configuration.
    ///
    /// Called by Kotlin when the user initiates torrent streaming.
    /// Initializes the libtorrent session, HTTP server, and disk cache.
    ///
    /// - Parameter configJson: JSON string matching `TorrentEngineConfig` fields.
    ///   Pass `"{}"` or `""` for defaults.
    @objc public func start(configJson: String) {
        engineQueue.async { [weak self] in
            guard let self = self, !self.isStarted else {
                print("[TorrentEngine] Already started or deallocated")
                return
            }

            // Parse configuration
            if let data = configJson.data(using: .utf8),
               let parsed = try? self.jsonDecoder.decode(TorrentEngineConfig.self, from: data) {
                self.config = parsed
            } else {
                print("[TorrentEngine] Using default configuration")
                self.config = TorrentEngineConfig()
            }

            // Initialize disk cache
            self.cacheManager = TorrentDiskCacheManager(maxCacheSizeBytes: self.config.maxCacheSizeBytes)

            // Create libtorrent session
            self.ltSession.create(config: self.config)

            // Start HTTP server
            let actualPort = self.httpServer.start(port: self.config.httpPort)
            print("[TorrentEngine] Started — HTTP server on port \(actualPort)")

            self.isStarted = true
        }
    }

    /// Stops all active torrent sessions and the HTTP server.
    ///
    /// Called when the user navigates away from streaming or the app is backgrounded.
    /// Sessions can be re-added after calling `start()` again.
    @objc public func stop() {
        engineQueue.async { [weak self] in
            guard let self = self, self.isStarted else { return }

            // Remove all active sessions
            for sessionId in self.activeSessions.keys {
                self.removeSessionInternal(sessionId: sessionId)
            }

            // Stop HTTP server
            self.httpServer.stop()

            // Destroy libtorrent session
            self.ltSession.destroy()

            self.isStarted = false
            print("[TorrentEngine] Stopped")
        }
    }

    // MARK: - Torrent Session Management

    /// Adds a torrent and returns session status JSON with the stream URL.
    ///
    /// This method:
    /// 1. Creates a unique session entry
    /// 2. Starts metadata resolution via libtorrent
    /// 3. Sets up streaming-optimized piece prioritization
    /// 4. Registers the session with the HTTP server
    /// 5. Returns JSON with the stream URL: `http://127.0.0.1:{port}/stream/{sessionId}`
    ///
    /// - Parameters:
    ///   - magnetUri: The magnet URI of the torrent.
    ///   - infoHash: The info hash (used for caching and deduplication).
    ///   - fileIdx: Index of the file to stream within the torrent (-1 for largest).
    /// - Returns: JSON string with session state including `streamUrl`, or error JSON.
    @objc public func addTorrent(magnetUri: String, infoHash: String, fileIdx: Int32) -> String {
        var resultJson = "{}"

        engineQueue.sync { [weak self] in
            guard let self = self, self.isStarted else {
                resultJson = self?.errorJson(message: "Engine not started") ?? "{}"
                return
            }

            // Check if a session already exists for this info hash
            if let existing = self.activeSessions.values.first(where: { $0.infoHash == infoHash }) {
                resultJson = self.encodeSessionState(existing.state)
                return
            }

            // Generate unique session ID
            self.sessionCounter += 1
            let sessionId = "\(infoHash.prefix(16))_\(self.sessionCounter)_\(Int(Date().timeIntervalSince1970))"

            // Resolve save path from cache manager
            let savePath: URL
            if let cache = self.cacheManager {
                savePath = cache.directoryForTorrent(infoHash: infoHash, fileName: "")
            } else {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("torrent_\(infoHash)")
                try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                savePath = tmp
            }

            // Add torrent to libtorrent session
            let handle = self.ltSession.addTorrent(
                magnetUri: magnetUri,
                savePath: savePath.path,
                fileIndex: Int(fileIdx)
            )

            // Build initial session state
            let streamUrl = self.httpServer.streamUrl(forSession: sessionId)

            var state = TorrentSessionState(
                sessionId: sessionId,
                infoHash: infoHash,
                magnetUri: magnetUri,
                fileIndex: Int(fileIdx),
                status: .resolvingMetadata,
                streamUrl: streamUrl,
                fileName: "",
                totalSizeBytes: 0,
                downloadedBytes: 0,
                downloadRate: 0,
                uploadRate: 0,
                numPeers: 0,
                numSeeds: 0,
                progress: 0.0,
                isMetadataResolved: false,
                isStreaming: false,
                errorMessage: nil
            )

            let session = ActiveTorrentSession(
                sessionId: sessionId,
                infoHash: infoHash,
                magnetUri: magnetUri,
                fileIndex: Int(fileIdx),
                state: state
            )
            session.torrentHandle = handle

            // If metadata is immediately available (placeholder always returns true),
            // set up streaming infrastructure
            if let handle = handle, self.ltSession.hasMetadata(handle: handle) {
                self.setupStreamingForSession(session, handle: handle, savePath: savePath)
            }

            self.activeSessions[sessionId] = session
            resultJson = self.encodeSessionState(session.state)
            print("[TorrentEngine] Added torrent session: \(sessionId)")
        }

        return resultJson
    }

    /// Removes a torrent session and cleans up all associated resources.
    /// - Parameter sessionId: The session ID to remove.
    @objc public func removeTorrent(sessionId: String) {
        engineQueue.async { [weak self] in
            self?.removeSessionInternal(sessionId: sessionId)
        }
    }

    /// Returns the current status of a torrent session as JSON.
    /// - Parameter sessionId: The session ID to query.
    /// - Returns: JSON string with current session state, or error JSON.
    @objc public func getSessionStatus(sessionId: String) -> String {
        var resultJson = "{}"

        engineQueue.sync { [weak self] in
            guard let self = self,
                  let session = self.activeSessions[sessionId] else {
                resultJson = self?.errorJson(message: "Session not found: \(sessionId)") ?? "{}"
                return
            }

            // Refresh state from libtorrent
            self.refreshSessionState(session)
            resultJson = self.encodeSessionState(session.state)
        }

        return resultJson
    }

    /// Returns the stream URL for a session.
    /// - Parameter sessionId: The session ID.
    /// - Returns: The HTTP stream URL, or empty string if not found.
    @objc public func getStreamUrl(sessionId: String) -> String {
        var url = ""
        engineQueue.sync { [weak self] in
            guard let self = self,
                  let session = self.activeSessions[sessionId] else { return }
            url = session.state.streamUrl
        }
        return url
    }

    /// Returns aggregated engine statistics as JSON.
    /// - Returns: JSON string with overall engine stats.
    @objc public func getStats() -> String {
        var resultJson = "{}"

        engineQueue.sync { [weak self] in
            guard let self = self else { return }

            var totalDownRate: Int64 = 0
            var totalUpRate: Int64 = 0

            for session in self.activeSessions.values {
                totalDownRate += session.state.downloadRate
                totalUpRate += session.state.uploadRate
            }

            let cacheStats = CacheStats(
                entryCount: self.cacheManager?.entryCount() ?? 0,
                totalSizeBytes: self.cacheManager?.currentCacheSize() ?? 0,
                maxSizeBytes: self.config.maxCacheSizeBytes
            )

            let stats = EngineStats(
                activeSessions: self.activeSessions.count,
                totalDownloadRate: totalDownRate,
                totalUploadRate: totalUpRate,
                httpServerPort: self.httpServer.port,
                httpServerRunning: self.httpServer.isRunning,
                cacheStats: cacheStats
            )

            if let data = try? self.jsonEncoder.encode(stats),
               let json = String(data: data, encoding: .utf8) {
                resultJson = json
            }
        }

        return resultJson
    }

    /// Completely destroys the engine and frees all resources.
    ///
    /// After calling this, the engine cannot be restarted. Create a new instance instead.
    /// Typically called when the app is terminating.
    @objc public func destroy() {
        stop()
        engineQueue.async { [weak self] in
            self?.cacheManager = nil
            self?.activeSessions.removeAll()
            print("[TorrentEngine] Destroyed")
        }
    }

    // MARK: - Internal: Session Setup

    /// Configures streaming infrastructure after torrent metadata is resolved.
    private func setupStreamingForSession(_ session: ActiveTorrentSession,
                                          handle: UnsafeMutableRawPointer,
                                          savePath: URL) {
        let pieces = ltSession.totalPieces(handle: handle)
        let pLength = ltSession.pieceLength(handle: handle)
        let fileIdx = session.fileIndex >= 0 ? session.fileIndex : 0
        let tSize = ltSession.totalSize(handle: handle, fileIndex: fileIdx)
        let fName = ltSession.fileName(handle: handle, fileIndex: fileIdx)

        // Update session state with metadata
        session.state.isMetadataResolved = true
        session.state.fileName = fName
        session.state.totalSizeBytes = tSize
        session.state.status = .downloading

        // Enable sequential downloading for streaming
        ltSession.setSequentialDownload(handle: handle, enabled: true)

        // Create piece prioritizer
        let prioritizer = TorrentPiecePrioritizer(
            totalPieces: pieces,
            pieceLength: pLength,
            totalSize: tSize
        )

        // Wire up the priority applier to libtorrent
        prioritizer.priorityApplier = { [weak self] pieceIndex, priority in
            self?.ltSession.setPiecePriority(handle: handle, pieceIndex: pieceIndex, priority: priority.rawValue)
        }

        // Start with streaming priorities from the beginning
        prioritizer.prioritizeForStreaming(currentByte: 0)

        session.prioritizer = prioritizer

        // Create data provider for HTTP server
        let provider = TorrentSessionDataProvider(
            sessionId: session.sessionId,
            savePath: savePath,
            fileName: fName,
            totalSize: tSize
        )
        session.dataProvider = provider

        // Register with HTTP server
        httpServer.registerProvider(sessionId: session.sessionId, provider: provider)

        session.state.isStreaming = true
        session.state.status = .streaming

        print("[TorrentEngine] Streaming setup complete for \(session.sessionId): \(fName) (\(tSize) bytes)")
    }

    // MARK: - Internal: Session State Refresh

    /// Refreshes a session's state from the libtorrent handle.
    private func refreshSessionState(_ session: ActiveTorrentSession) {
        guard let handle = session.torrentHandle else { return }

        session.state.downloadRate = ltSession.downloadRate(handle: handle)
        session.state.uploadRate = ltSession.uploadRate(handle: handle)
        session.state.numPeers = ltSession.numPeers(handle: handle)
        session.state.numSeeds = ltSession.numSeeds(handle: handle)
        session.state.progress = ltSession.progress(handle: handle)
        session.state.downloadedBytes = ltSession.downloadedBytes(handle: handle)

        // Update data provider with current available size
        session.dataProvider?.updateAvailableSize(session.state.downloadedBytes)
    }

    // MARK: - Internal: Session Removal

    /// Removes a session (must be called on engineQueue).
    private func removeSessionInternal(sessionId: String) {
        guard let session = activeSessions.removeValue(forKey: sessionId) else { return }

        // Unregister from HTTP server
        httpServer.unregisterProvider(sessionId: sessionId)

        // Remove from libtorrent
        if let handle = session.torrentHandle {
            ltSession.removeTorrent(handle: handle, deleteFiles: false)
        }

        session.state.status = .stopped
        session.state.isStreaming = false
        session.prioritizer = nil
        session.dataProvider = nil

        print("[TorrentEngine] Removed session: \(sessionId)")
    }

    // MARK: - Internal: JSON Helpers

    /// Encodes a session state to JSON string.
    private func encodeSessionState(_ state: TorrentSessionState) -> String {
        guard let data = try? jsonEncoder.encode(state),
              let json = String(data: data, encoding: .utf8) else {
            return errorJson(message: "Failed to encode session state")
        }
        return json
    }

    /// Returns a minimal error JSON string.
    private func errorJson(message: String) -> String {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"error\":\"\(escaped)\"}"
    }
}
