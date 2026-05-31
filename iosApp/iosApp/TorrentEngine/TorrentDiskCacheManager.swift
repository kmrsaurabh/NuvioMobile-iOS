// TorrentDiskCacheManager.swift
// NuvioMobile-iOS
//
// Manages on-disk caching of downloaded torrent data with LRU eviction.
// Cached files are stored in {Caches}/torrent_cache/ and tracked via
// a JSON metadata file for persistence across app launches.

import Foundation

// MARK: - Cache Entry Metadata

/// Metadata for a single cached torrent file, persisted to disk.
public struct TorrentCacheEntry: Codable {
    /// Unique identifier for this cache entry (typically the info hash).
    let id: String

    /// The info hash of the torrent.
    let infoHash: String

    /// Display name of the cached file.
    let fileName: String

    /// Total size of the cached file in bytes.
    let fileSize: Int64

    /// Relative path within the cache directory.
    let relativePath: String

    /// Date this entry was first created (download completed).
    let createdDate: Date

    /// Date this entry was last accessed (streamed or opened).
    var lastAccessedDate: Date

    /// Number of times this cached file has been accessed.
    var accessCount: Int
}

// MARK: - Cache Metadata Container

/// Top-level container for the cache metadata JSON file.
private struct CacheMetadataStore: Codable {
    /// Version of the metadata format for future migrations.
    let version: Int

    /// All cache entries keyed by ID.
    var entries: [String: TorrentCacheEntry]

    static let currentVersion = 1

    init() {
        self.version = Self.currentVersion
        self.entries = [:]
    }
}

// MARK: - TorrentDiskCacheManager

/// Manages downloaded torrent file caching on disk with LRU eviction.
///
/// Features:
/// - Stores downloaded torrent data in `{Caches}/torrent_cache/`
/// - Persists cache metadata to `cache_metadata.json` for cross-launch tracking
/// - LRU eviction: when the cache exceeds its size limit, the least-recently-accessed
///   entries are removed first
/// - Thread-safe: all mutations go through a serial `DispatchQueue`
///
/// Usage:
/// ```swift
/// let cache = TorrentDiskCacheManager(maxCacheSizeBytes: 2 * 1024 * 1024 * 1024)  // 2 GB
/// let dir = cache.directoryForTorrent(infoHash: "abc123", fileName: "movie.mkv")
/// // ... download torrent data into `dir` ...
/// cache.registerCachedFile(id: "abc123", infoHash: "abc123", fileName: "movie.mkv", fileSize: size)
/// ```
@objc public class TorrentDiskCacheManager: NSObject {

    // MARK: - Constants

    /// Name of the cache subdirectory within the system Caches folder.
    private static let cacheDirectoryName = "torrent_cache"

    /// Name of the metadata JSON file.
    private static let metadataFileName = "cache_metadata.json"

    // MARK: - Properties

    /// Maximum allowed cache size in bytes. When exceeded, LRU eviction runs.
    public let maxCacheSizeBytes: Int64

    /// Root directory for all cached torrent files.
    public let cacheDirectory: URL

    /// Path to the metadata JSON file.
    private let metadataFilePath: URL

    /// In-memory copy of the metadata store, kept in sync with disk.
    private var metadataStore: CacheMetadataStore

    /// Serial queue for thread-safe access to cache state.
    private let queue = DispatchQueue(label: "com.nuvio.torrent.diskCache", qos: .utility)

    /// JSON encoder configured for the metadata file.
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// JSON decoder configured for the metadata file.
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialization

    /// Creates a new disk cache manager.
    /// - Parameter maxCacheSizeBytes: Maximum cache size in bytes. Defaults to 2 GB.
    @objc public init(maxCacheSizeBytes: Int64 = 2 * 1024 * 1024 * 1024) {
        self.maxCacheSizeBytes = maxCacheSizeBytes

        // Resolve cache directory
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDir.appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
        self.metadataFilePath = self.cacheDirectory.appendingPathComponent(Self.metadataFileName)
        self.metadataStore = CacheMetadataStore()

        super.init()

        // Ensure cache directory exists
        createCacheDirectoryIfNeeded()

        // Load existing metadata from disk
        loadMetadata()
    }

    // MARK: - Directory Management

    /// Returns (and creates if needed) a subdirectory for the given torrent.
    /// - Parameters:
    ///   - infoHash: The torrent's info hash, used as the directory name.
    ///   - fileName: The name of the file within the torrent (informational).
    /// - Returns: URL to the torrent's cache subdirectory.
    @objc public func directoryForTorrent(infoHash: String, fileName: String) -> URL {
        let dir = cacheDirectory.appendingPathComponent(infoHash, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[DiskCache] Failed to create torrent directory: \(error.localizedDescription)")
        }
        return dir
    }

    /// Returns the full file path for a cached torrent file.
    /// - Parameters:
    ///   - infoHash: The torrent's info hash.
    ///   - fileName: The file name within the torrent.
    /// - Returns: URL to the cached file.
    @objc public func filePathForTorrent(infoHash: String, fileName: String) -> URL {
        return directoryForTorrent(infoHash: infoHash, fileName: fileName)
            .appendingPathComponent(fileName)
    }

    // MARK: - Cache Registration

    /// Registers a file in the cache after it has been downloaded.
    ///
    /// Call this once the torrent download completes or when enough data is available
    /// for streaming. The entry is added to the metadata store and persisted to disk.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this cache entry (typically the info hash).
    ///   - infoHash: The torrent's info hash.
    ///   - fileName: Display name of the cached file.
    ///   - fileSize: Total size of the file in bytes.
    @objc public func registerCachedFile(id: String, infoHash: String, fileName: String, fileSize: Int64) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let entry = TorrentCacheEntry(
                id: id,
                infoHash: infoHash,
                fileName: fileName,
                fileSize: fileSize,
                relativePath: "\(infoHash)/\(fileName)",
                createdDate: Date(),
                lastAccessedDate: Date(),
                accessCount: 1
            )

            self.metadataStore.entries[id] = entry
            self.saveMetadata()
            self.evictIfNeeded()
        }
    }

    // MARK: - Cache Access

    /// Records an access to a cached entry, updating its LRU timestamp.
    /// - Parameter id: The cache entry ID to touch.
    @objc public func touchEntry(id: String) {
        queue.async { [weak self] in
            guard let self = self, var entry = self.metadataStore.entries[id] else { return }
            entry.lastAccessedDate = Date()
            entry.accessCount += 1
            self.metadataStore.entries[id] = entry
            self.saveMetadata()
        }
    }

    /// Checks if a cache entry exists and its file is present on disk.
    /// - Parameter id: The cache entry ID to look up.
    /// - Returns: True if the entry exists and the file is on disk.
    @objc public func hasCachedFile(id: String) -> Bool {
        var result = false
        queue.sync {
            guard let entry = metadataStore.entries[id] else { return }
            let filePath = cacheDirectory.appendingPathComponent(entry.relativePath)
            result = FileManager.default.fileExists(atPath: filePath.path)
        }
        return result
    }

    /// Returns metadata for a cached entry, or nil if not found.
    /// - Parameter id: The cache entry ID.
    /// - Returns: The cache entry metadata, or nil.
    public func getEntry(id: String) -> TorrentCacheEntry? {
        var entry: TorrentCacheEntry?
        queue.sync {
            entry = metadataStore.entries[id]
        }
        return entry
    }

    /// Returns all cache entries sorted by last accessed date (most recent first).
    public func allEntries() -> [TorrentCacheEntry] {
        var entries: [TorrentCacheEntry] = []
        queue.sync {
            entries = metadataStore.entries.values
                .sorted { $0.lastAccessedDate > $1.lastAccessedDate }
        }
        return entries
    }

    // MARK: - Cache Removal

    /// Removes a specific cache entry and its files from disk.
    /// - Parameter id: The cache entry ID to remove.
    @objc public func removeEntry(id: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.removeEntryInternal(id: id)
            self.saveMetadata()
        }
    }

    /// Clears the entire cache — removes all files and metadata.
    @objc public func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Remove all entry directories
            for entry in self.metadataStore.entries.values {
                let dir = self.cacheDirectory.appendingPathComponent(entry.infoHash)
                try? FileManager.default.removeItem(at: dir)
            }
            self.metadataStore.entries.removeAll()
            self.saveMetadata()
            print("[DiskCache] Cache cleared")
        }
    }

    // MARK: - Cache Size & Statistics

    /// Returns the current total size of all cached files in bytes.
    @objc public func currentCacheSize() -> Int64 {
        var size: Int64 = 0
        queue.sync {
            size = metadataStore.entries.values.reduce(0) { $0 + $1.fileSize }
        }
        return size
    }

    /// Returns the number of entries in the cache.
    @objc public func entryCount() -> Int {
        var count = 0
        queue.sync {
            count = metadataStore.entries.count
        }
        return count
    }

    /// Returns a JSON string with cache statistics.
    @objc public func statsJson() -> String {
        var json = "{}"
        queue.sync {
            let totalSize = metadataStore.entries.values.reduce(Int64(0)) { $0 + $1.fileSize }
            let stats: [String: Any] = [
                "entryCount": metadataStore.entries.count,
                "totalSizeBytes": totalSize,
                "maxSizeBytes": maxCacheSizeBytes,
                "usagePercent": maxCacheSizeBytes > 0
                    ? Double(totalSize) / Double(maxCacheSizeBytes) * 100.0
                    : 0.0,
                "cacheDirectory": cacheDirectory.path
            ]
            if let data = try? JSONSerialization.data(withJSONObject: stats, options: .sortedKeys) {
                json = String(data: data, encoding: .utf8) ?? "{}"
            }
        }
        return json
    }

    // MARK: - LRU Eviction

    /// Evicts least-recently-used entries until the cache is within size limits.
    private func evictIfNeeded() {
        var totalSize = metadataStore.entries.values.reduce(Int64(0)) { $0 + $1.fileSize }
        guard totalSize > maxCacheSizeBytes else { return }

        // Sort by last accessed date, oldest first (LRU candidates)
        let sortedEntries = metadataStore.entries.values
            .sorted { $0.lastAccessedDate < $1.lastAccessedDate }

        for entry in sortedEntries {
            guard totalSize > maxCacheSizeBytes else { break }

            print("[DiskCache] Evicting LRU entry: \(entry.id) (\(entry.fileName)), " +
                  "last accessed: \(entry.lastAccessedDate)")

            totalSize -= entry.fileSize
            removeEntryInternal(id: entry.id)
        }

        saveMetadata()
    }

    // MARK: - Internal Helpers

    /// Removes an entry from the store and its files from disk (not thread-safe, must be called on queue).
    private func removeEntryInternal(id: String) {
        guard let entry = metadataStore.entries.removeValue(forKey: id) else { return }
        let dir = cacheDirectory.appendingPathComponent(entry.infoHash)
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            print("[DiskCache] Failed to remove directory for \(id): \(error.localizedDescription)")
        }
    }

    /// Creates the cache root directory if it doesn't exist.
    private func createCacheDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            print("[DiskCache] Failed to create cache directory: \(error.localizedDescription)")
        }
    }

    /// Loads metadata from the JSON file on disk.
    private func loadMetadata() {
        queue.async { [weak self] in
            guard let self = self else { return }

            guard FileManager.default.fileExists(atPath: self.metadataFilePath.path) else {
                print("[DiskCache] No existing metadata file, starting fresh")
                return
            }

            do {
                let data = try Data(contentsOf: self.metadataFilePath)
                self.metadataStore = try self.jsonDecoder.decode(CacheMetadataStore.self, from: data)
                print("[DiskCache] Loaded \(self.metadataStore.entries.count) cache entries from metadata")
                self.pruneOrphanedEntries()
            } catch {
                print("[DiskCache] Failed to load metadata, starting fresh: \(error.localizedDescription)")
                self.metadataStore = CacheMetadataStore()
            }
        }
    }

    /// Saves the current metadata store to disk as JSON.
    private func saveMetadata() {
        do {
            let data = try jsonEncoder.encode(metadataStore)
            try data.write(to: metadataFilePath, options: .atomic)
        } catch {
            print("[DiskCache] Failed to save metadata: \(error.localizedDescription)")
        }
    }

    /// Removes entries whose files no longer exist on disk.
    private func pruneOrphanedEntries() {
        var pruned = false
        for (id, entry) in metadataStore.entries {
            let filePath = cacheDirectory.appendingPathComponent(entry.relativePath)
            if !FileManager.default.fileExists(atPath: filePath.path) {
                print("[DiskCache] Pruning orphaned entry: \(id) (file not found)")
                metadataStore.entries.removeValue(forKey: id)
                pruned = true
            }
        }
        if pruned {
            saveMetadata()
        }
    }
}
