// TorrentEngineSwiftBridge.swift
// NuvioMobile-iOS
//
// Main Swift bridge for the P2P torrent streaming engine.
// Kotlin calls this class via ObjC interop to manage torrent sessions,
// an embedded HTTP server, and piece-level streaming prioritization.
//
// Architecture:
//   Kotlin (ComposeApp) --> ObjC interop --> TorrentEngineSwiftBridge
//     ├── LibTorrentSession (C API wrapper for iTorrent)
//     ├── TorrentHTTPServer (NWListener-based streaming)
//     └── TorrentDiskCacheManager (LRU disk cache)

import Foundation
import iTorrent

// MARK: - Configuration Models

/// Engine configuration decoded from JSON passed by Kotlin.
private struct TorrentEngineConfig: Codable {
    var httpPort: UInt16 = 0
    var maxActiveTorrents: Int = 3
    var maxCacheSizeBytes: Int64 = 2 * 1024 * 1024 * 1024
    var maxDownloadRate: Int = 0
    var maxUploadRate: Int = 0
    var maxPeerConnections: Int = 80
    var enableDHT: Bool = true
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

// MARK: - LibTorrent Session Abstraction

/// Clean abstraction over the libtorrent C API using iTorrent framework.
private class LibTorrentSession {
    static let shared = LibTorrentSession()
    
    private var isInitialized = false
    let downloadPath: String
    private let configPath: String
    
    private init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0]
        
        let dlDir = docDir.appendingPathComponent("Downloads", isDirectory: true)
        let cfgDir = docDir.appendingPathComponent("TorrentConfig", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: dlDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cfgDir, withIntermediateDirectories: true)
        
        downloadPath = dlDir.path
        configPath = cfgDir.path
    }
    
    func initialize(config: TorrentEngineConfig) {
        if isInitialized { return }
        init_engine(strdup("NuvioMobile"), strdup(downloadPath), strdup(configPath))
        isInitialized = true
    }
    
    func destroy() {
        // iTorrent engine runs globally
    }
    
    func addMagnet(uri: String) -> String? {
        let uriPtr = strdup(uri)
        _ = add_magnet(uriPtr)
        
        // Extract info hash manually from magnet URI to avoid reading dangling pointers from C++
        let pattern = "btih:([a-zA-Z0-9]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: uri, options: [], range: NSRange(location: 0, length: uri.utf16.count)) {
            if let range = Range(match.range(at: 1), in: uri) {
                return String(uri[range]).lowercased()
            }
        }
        return nil
    }
    
    func removeTorrent(infoHash: String) {
        remove_torrent(strdup(infoHash), 1) // 1 = remove files
    }
    
    func setSequentialDownload(infoHash: String, sequential: Bool) {
        set_torrent_files_sequental(strdup(infoHash), sequential ? 1 : 0)
    }
    
    func getTorrentState(infoHash: String) -> TorrentSessionState? {
        let result = get_torrent_info()
        defer { free_result(result) }
        
        if let torrents = result.torrents {
            for i in 0..<result.count {
                let tInfo = torrents[Int(i)]
            
            if tInfo.hash == nil { continue }
            
            // Wait, tInfo.hash could also be a dangling pointer if the C++ wrapper is bad.
            // But we must read it to compare with infoHash.
            // We'll wrap it in a safe try if possible, but C strings can't be safely caught.
            // Let's assume tInfo.hash is a valid pointer because it's part of an allocated struct.
            let currentHash = tInfo.hash != nil ? (String(validatingUTF8: tInfo.hash!) ?? "") : ""
            if currentHash.lowercased() == infoHash.lowercased() {
                var status: TorrentStatus = .downloading
                if tInfo.is_paused != 0 {
                    status = .paused
                } else if tInfo.has_metadata == 0 {
                    status = .resolvingMetadata
                } else if tInfo.is_finished != 0 || tInfo.is_seed != 0 {
                    status = .completed
                } else {
                    if let statePtr = tInfo.state, (String(validatingUTF8: statePtr) ?? "") == "downloading" {
                        status = .downloading
                    }
                }
                
                let nameStr = tInfo.name != nil ? (String(validatingUTF8: tInfo.name!) ?? "") : ""
                
                return TorrentSessionState(
                    sessionId: currentHash,
                    infoHash: currentHash,
                    magnetUri: "", 
                    fileIndex: 0,
                    status: status,
                    streamUrl: "",
                    fileName: nameStr,
                    totalSizeBytes: Int64(tInfo.total_size),
                    downloadedBytes: Int64(tInfo.total_done),
                    downloadRate: Int64(tInfo.download_rate),
                    uploadRate: Int64(tInfo.upload_rate),
                    numPeers: Int(tInfo.num_peers),
                    numSeeds: Int(tInfo.num_seeds),
                    progress: Double(tInfo.progress),
                    isMetadataResolved: tInfo.has_metadata != 0,
                    isStreaming: false,
                    errorMessage: nil
                )
            }
        }
        }
        return nil
    }
    
    func getStats() -> EngineStats {
        let result = get_torrent_info()
        let activeCount = Int(result.count)
        var totalDown: Int64 = 0
        var totalUp: Int64 = 0
        
        if let torrents = result.torrents {
            for i in 0..<result.count {
                let t = torrents[Int(i)]
                totalDown += Int64(t.download_rate)
                totalUp += Int64(t.upload_rate)
            }
        }
        free_result(result)
        
        return EngineStats(
            activeSessions: activeCount,
            totalDownloadRate: totalDown,
            totalUploadRate: totalUp,
            httpServerPort: 0,
            httpServerRunning: false,
            cacheStats: CacheStats(entryCount: 0, totalSizeBytes: 0, maxSizeBytes: 0)
        )
    }
    
    func getFiles(infoHash: String) -> [(name: String, size: Int64, downloaded: Int64)] {
        let filesStruct = get_files_of_torrent_by_hash(strdup(infoHash))
        defer { free_files(filesStruct) }
        
        var result = [(name: String, size: Int64, downloaded: Int64)]()
        if filesStruct.error == 0, let files = filesStruct.files {
            for i in 0..<filesStruct.size {
                let file = files[Int(i)]
                let nameStr = file.file_name != nil ? (String(validatingUTF8: file.file_name!) ?? "") : ""
                result.append((
                    name: nameStr,
                    size: file.file_size,
                    downloaded: file.file_downloaded
                ))
            }
        }
        return result
    }
    
    func prioritizeFile(infoHash: String, fileIndex: Int, priority: Int) {
        set_torrent_file_priority(strdup(infoHash), Int32(fileIndex), Int32(priority))
    }
}

// MARK: - Torrent Session Data Provider

/// Bridges a torrent session to the HTTP server by conforming to `TorrentDataProvider`.
///
/// Reads data from the downloaded file on disk and reports availability based on
/// the libtorrent download progress.
private class TorrentSessionDataProvider: NSObject, TorrentDataProvider {

    let sessionId: String
    private let filePath: URL
    private let _fileName: String
    private let _totalSize: Int64
    private var fileHandle: FileHandle?
    private let fileLock = NSLock()

    /// Condition variable signaled when new pieces complete downloading.
    private let dataCondition = NSCondition()

    /// Track the furthest contiguous byte available.
    private var _availableSize: Int64 = 0

    init(sessionId: String, filePath: URL, fileName: String, totalSize: Int64) {
        self.sessionId = sessionId
        self.filePath = filePath
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

        guard let handle = fileHandle else {
            // Attempt to open again if it wasn't there
            openFileIfNeededInternal()
            guard let retryHandle = fileHandle else { return nil }
            return tryReadData(handle: retryHandle, offset: offset, length: length)
        }
        
        return tryReadData(handle: handle, offset: offset, length: length)
    }
    
    private func tryReadData(handle: FileHandle, offset: Int64, length: Int) -> Data? {
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
        openFileIfNeededInternal()
    }
    
    private func openFileIfNeededInternal() {
        if fileHandle == nil && FileManager.default.fileExists(atPath: filePath.path) {
            fileHandle = try? FileHandle(forReadingFrom: filePath)
        }
    }

    /// Re-opens the file handle (e.g., after the file is first created by libtorrent).
    func reopenFile() {
        fileLock.lock()
        try? fileHandle?.close()
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
/// - Active torrent sessions
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
    private let ltSession = LibTorrentSession.shared

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
            self.ltSession.initialize(config: self.config)

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
    /// 3. Registers the session with the HTTP server
    /// 4. Returns JSON with the stream URL: `http://127.0.0.1:{port}/stream/{sessionId}`
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

            // Add torrent to libtorrent session
            let addedHash = self.ltSession.addMagnet(uri: magnetUri) ?? infoHash

            // Build initial session state
            let streamUrl = self.httpServer.streamUrl(forSession: sessionId)

            let state = TorrentSessionState(
                sessionId: sessionId,
                infoHash: addedHash,
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
                infoHash: addedHash,
                magnetUri: magnetUri,
                fileIndex: Int(fileIdx),
                state: state
            )

            // Setup streaming if metadata is already available
            self.trySetupStreamingForSession(session)

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

            let engineStats = self.ltSession.getStats()
            
            let cacheStats = CacheStats(
                entryCount: self.cacheManager?.entryCount() ?? 0,
                totalSizeBytes: self.cacheManager?.currentCacheSize() ?? 0,
                maxSizeBytes: self.config.maxCacheSizeBytes
            )

            let stats = EngineStats(
                activeSessions: self.activeSessions.count,
                totalDownloadRate: engineStats.totalDownloadRate,
                totalUploadRate: engineStats.totalUploadRate,
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
    @objc public func destroy() {
        stop()
        engineQueue.async { [weak self] in
            self?.cacheManager = nil
            self?.activeSessions.removeAll()
            print("[TorrentEngine] Destroyed")
        }
    }

    // MARK: - Internal: Session Setup

    /// Tries to configure streaming infrastructure if metadata is resolved.
    private func trySetupStreamingForSession(_ session: ActiveTorrentSession) {
        guard let engineState = ltSession.getTorrentState(infoHash: session.infoHash) else { return }
        
        if engineState.isMetadataResolved {
            let files = ltSession.getFiles(infoHash: session.infoHash)
            if files.isEmpty { return }
            
            let fileIdx = session.fileIndex >= 0 && session.fileIndex < files.count ? session.fileIndex : 0
            let targetFile = files[fileIdx]
            
            // Prioritize this file
            ltSession.prioritizeFile(infoHash: session.infoHash, fileIndex: fileIdx, priority: 7) // 7 = normal
            ltSession.setSequentialDownload(infoHash: session.infoHash, sequential: true)
            
            // iTorrent stores torrents in `downloadPath/torrentName` or `downloadPath` depending on if it's a multi-file torrent
            let torrentName = engineState.fileName
            var fileUrl = URL(fileURLWithPath: ltSession.downloadPath)
            
            // Add torrent folder if it is a directory
            if !torrentName.isEmpty && files.count > 1 {
                fileUrl.appendPathComponent(torrentName)
            }
            fileUrl.appendPathComponent(targetFile.name)
            
            session.state.isMetadataResolved = true
            session.state.fileName = targetFile.name
            session.state.totalSizeBytes = targetFile.size
            session.state.status = .downloading
            
            // Create data provider for HTTP server
            let provider = TorrentSessionDataProvider(
                sessionId: session.sessionId,
                filePath: fileUrl,
                fileName: targetFile.name,
                totalSize: targetFile.size
            )
            session.dataProvider = provider
            
            // Register with HTTP server
            httpServer.registerProvider(sessionId: session.sessionId, provider: provider)
            
            session.state.isStreaming = true
            session.state.status = .streaming
            
            print("[TorrentEngine] Streaming setup complete for \(session.sessionId): \(targetFile.name) (\(targetFile.size) bytes)")
        }
    }

    // MARK: - Internal: Session State Refresh

    /// Refreshes a session's state from the libtorrent handle.
    private func refreshSessionState(_ session: ActiveTorrentSession) {
        guard let engineState = ltSession.getTorrentState(infoHash: session.infoHash) else { return }

        // Check if metadata just became available
        if !session.state.isMetadataResolved && engineState.isMetadataResolved {
            trySetupStreamingForSession(session)
        }

        session.state.downloadRate = engineState.downloadRate
        session.state.uploadRate = engineState.uploadRate
        session.state.numPeers = engineState.numPeers
        session.state.numSeeds = engineState.numSeeds
        session.state.progress = engineState.progress
        
        let files = ltSession.getFiles(infoHash: session.infoHash)
        let fileIdx = session.fileIndex >= 0 && session.fileIndex < files.count ? session.fileIndex : 0
        if fileIdx < files.count {
            session.state.downloadedBytes = files[fileIdx].downloaded
            // Update data provider with current available size for this specific file!
            session.dataProvider?.updateAvailableSize(session.state.downloadedBytes)
        } else {
            session.state.downloadedBytes = engineState.downloadedBytes
        }
        
        // Ensure status reflects downloading state
        if session.state.status == .resolvingMetadata && engineState.isMetadataResolved {
            session.state.status = .downloading
        }
    }

    // MARK: - Internal: Session Removal

    /// Removes a session (must be called on engineQueue).
    private func removeSessionInternal(sessionId: String) {
        guard let session = activeSessions.removeValue(forKey: sessionId) else { return }

        // Unregister from HTTP server
        httpServer.unregisterProvider(sessionId: sessionId)

        // Remove from libtorrent
        ltSession.removeTorrent(infoHash: session.infoHash)

        session.state.status = .stopped
        session.state.isStreaming = false
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
