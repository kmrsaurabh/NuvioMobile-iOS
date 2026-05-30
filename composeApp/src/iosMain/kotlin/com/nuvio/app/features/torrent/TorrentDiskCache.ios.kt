package com.nuvio.app.features.torrent

import co.touchlab.kermit.Logger
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import platform.Foundation.NSCachesDirectory
import platform.Foundation.NSFileManager
import platform.Foundation.NSSearchPathForDirectoriesInDomains
import platform.Foundation.NSString
import platform.Foundation.NSUserDomainMask
import platform.Foundation.stringByAppendingPathComponent
import platform.Foundation.writeToFile

@Serializable
private data class CacheEntry(
    val infoHash: String,
    val fileIdx: Int,
    val filePath: String,
    val sizeBytes: Long,
    val lastAccessedMs: Long,
)

@Serializable
private data class CacheMetadata(
    val entries: MutableList<CacheEntry> = mutableListOf(),
)

actual object TorrentDiskCache {
    private const val TAG = "TorrentDiskCache"
    private const val CACHE_DIR_NAME = "torrent_cache"
    private const val METADATA_FILE_NAME = "cache_metadata.json"

    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = false
    }

    private fun cacheDirectory(): String {
        val paths = NSSearchPathForDirectoriesInDomains(
            NSCachesDirectory,
            NSUserDomainMask,
            true,
        )
        val cachesDir = paths.firstOrNull() as? String ?: return ""
        return (cachesDir as NSString).stringByAppendingPathComponent(CACHE_DIR_NAME)
    }

    private fun metadataFilePath(): String {
        val dir = cacheDirectory()
        if (dir.isBlank()) return ""
        return (dir as NSString).stringByAppendingPathComponent(METADATA_FILE_NAME)
    }

    private fun ensureCacheDirectoryExists() {
        val dir = cacheDirectory()
        if (dir.isBlank()) return
        val fileManager = NSFileManager.defaultManager
        if (!fileManager.fileExistsAtPath(dir)) {
            fileManager.createDirectoryAtPath(dir, withIntermediateDirectories = true, attributes = null, error = null)
        }
    }

    private fun loadMetadata(): CacheMetadata {
        val path = metadataFilePath()
        if (path.isBlank()) return CacheMetadata()
        val fileManager = NSFileManager.defaultManager
        if (!fileManager.fileExistsAtPath(path)) return CacheMetadata()
        return try {
            val content = NSString.stringWithContentsOfFile(path, encoding = 4u /* NSUTF8StringEncoding */, error = null)
                ?: return CacheMetadata()
            json.decodeFromString<CacheMetadata>(content.toString())
        } catch (e: Exception) {
            Logger.w(TAG, e) { "Failed to load cache metadata" }
            CacheMetadata()
        }
    }

    private fun saveMetadata(metadata: CacheMetadata) {
        ensureCacheDirectoryExists()
        val path = metadataFilePath()
        if (path.isBlank()) return
        try {
            val jsonStr = json.encodeToString(metadata)
            (jsonStr as NSString).writeToFile(path, atomically = true, encoding = 4u /* NSUTF8StringEncoding */, error = null)
        } catch (e: Exception) {
            Logger.w(TAG, e) { "Failed to save cache metadata" }
        }
    }

    private fun entryKey(infoHash: String, fileIdx: Int): String = "${infoHash}_$fileIdx"

    actual fun currentSizeBytes(): Long {
        val metadata = loadMetadata()
        return metadata.entries.sumOf { it.sizeBytes }
    }

    actual fun clearAll() {
        val dir = cacheDirectory()
        if (dir.isBlank()) return
        val fileManager = NSFileManager.defaultManager
        if (fileManager.fileExistsAtPath(dir)) {
            fileManager.removeItemAtPath(dir, error = null)
        }
        Logger.d(TAG) { "Cleared all torrent cache" }
    }

    actual fun evictIfNeeded(maxSizeMb: Int) {
        val maxSizeBytes = maxSizeMb.toLong() * 1024L * 1024L
        val metadata = loadMetadata()
        var totalSize = metadata.entries.sumOf { it.sizeBytes }
        if (totalSize <= maxSizeBytes) return

        val sorted = metadata.entries.sortedBy { it.lastAccessedMs }.toMutableList()
        val fileManager = NSFileManager.defaultManager
        val removed = mutableListOf<CacheEntry>()

        for (entry in sorted) {
            if (totalSize <= maxSizeBytes) break
            if (fileManager.fileExistsAtPath(entry.filePath)) {
                fileManager.removeItemAtPath(entry.filePath, error = null)
            }
            totalSize -= entry.sizeBytes
            removed.add(entry)
            Logger.d(TAG) { "Evicted cache entry: ${entry.infoHash}/${entry.fileIdx}" }
        }

        metadata.entries.removeAll(removed)
        saveMetadata(metadata)
    }

    actual fun getCachedFilePath(infoHash: String, fileIdx: Int): String? {
        val metadata = loadMetadata()
        val entry = metadata.entries.firstOrNull { it.infoHash == infoHash && it.fileIdx == fileIdx }
            ?: return null
        val fileManager = NSFileManager.defaultManager
        return if (fileManager.fileExistsAtPath(entry.filePath)) {
            entry.filePath
        } else {
            metadata.entries.remove(entry)
            saveMetadata(metadata)
            null
        }
    }

    actual fun putCachedFile(infoHash: String, fileIdx: Int, filePath: String) {
        ensureCacheDirectoryExists()
        val fileManager = NSFileManager.defaultManager
        val attributes = fileManager.attributesOfItemAtPath(filePath, error = null)
        val sizeBytes = (attributes?.get("NSFileSize") as? Long) ?: 0L

        val metadata = loadMetadata()
        metadata.entries.removeAll { it.infoHash == infoHash && it.fileIdx == fileIdx }
        metadata.entries.add(
            CacheEntry(
                infoHash = infoHash,
                fileIdx = fileIdx,
                filePath = filePath,
                sizeBytes = sizeBytes,
                lastAccessedMs = currentTimeMs(),
            ),
        )
        saveMetadata(metadata)
        Logger.d(TAG) { "Cached file: $infoHash/$fileIdx ($sizeBytes bytes)" }
    }

    actual fun removeCachedFile(infoHash: String, fileIdx: Int) {
        val metadata = loadMetadata()
        val entry = metadata.entries.firstOrNull { it.infoHash == infoHash && it.fileIdx == fileIdx }
        if (entry != null) {
            val fileManager = NSFileManager.defaultManager
            if (fileManager.fileExistsAtPath(entry.filePath)) {
                fileManager.removeItemAtPath(entry.filePath, error = null)
            }
            metadata.entries.remove(entry)
            saveMetadata(metadata)
            Logger.d(TAG) { "Removed cached file: $infoHash/$fileIdx" }
        }
    }

    actual fun markAccessed(infoHash: String, fileIdx: Int) {
        val metadata = loadMetadata()
        val index = metadata.entries.indexOfFirst { it.infoHash == infoHash && it.fileIdx == fileIdx }
        if (index >= 0) {
            metadata.entries[index] = metadata.entries[index].copy(lastAccessedMs = currentTimeMs())
            saveMetadata(metadata)
        }
    }

    private fun currentTimeMs(): Long =
        platform.Foundation.NSDate.date().timeIntervalSince1970().toLong() * 1000L
}
