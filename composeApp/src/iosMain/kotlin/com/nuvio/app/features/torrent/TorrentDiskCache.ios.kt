package com.nuvio.app.features.torrent

import co.touchlab.kermit.Logger
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.convert
import kotlinx.cinterop.usePinned
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import platform.Foundation.NSCachesDirectory
import platform.Foundation.NSData
import platform.Foundation.NSFileManager
import platform.Foundation.NSHomeDirectory
import platform.Foundation.NSSearchPathForDirectoriesInDomains
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.NSUserDomainMask
import platform.Foundation.create
import platform.posix.fclose
import platform.posix.fopen
import platform.posix.fread
import platform.posix.fseek
import platform.posix.ftell
import platform.posix.fwrite
import platform.posix.SEEK_END
import platform.posix.SEEK_SET

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

@OptIn(ExperimentalForeignApi::class)
actual object TorrentDiskCache {
    private const val TAG = "TorrentDiskCache"
    private const val CACHE_DIR_NAME = "torrent_cache"
    private const val METADATA_FILE_NAME = "cache_metadata.json"

    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = false
    }

    private fun cacheDirectory(): String {
        val root = NSHomeDirectory().trimEnd('/')
        return "$root/Library/Caches/$CACHE_DIR_NAME"
    }

    private fun metadataFilePath(): String =
        "${cacheDirectory()}/$METADATA_FILE_NAME"

    private fun ensureCacheDirectoryExists() {
        val dir = cacheDirectory()
        val fileManager = NSFileManager.defaultManager
        if (!fileManager.fileExistsAtPath(dir)) {
            fileManager.createDirectoryAtPath(
                path = dir,
                withIntermediateDirectories = true,
                attributes = null,
                error = null,
            )
        }
    }

    private fun readFileAsString(path: String): String? {
        val file = fopen(path, "rb") ?: return null
        return try {
            fseek(file, 0, SEEK_END)
            val size = ftell(file)
            if (size <= 0L) return null
            fseek(file, 0, SEEK_SET)
            val bytes = ByteArray(size.toInt())
            bytes.usePinned { pinned ->
                fread(pinned.addressOf(0), 1.convert(), size.convert(), file)
            }
            bytes.decodeToString()
        } finally {
            fclose(file)
        }
    }

    private fun writeStringToFile(path: String, content: String): Boolean {
        val bytes = content.encodeToByteArray()
        val file = fopen(path, "wb") ?: return false
        return try {
            bytes.usePinned { pinned ->
                val written = fwrite(pinned.addressOf(0), 1.convert(), bytes.size.convert(), file)
                written.toLong() == bytes.size.toLong()
            }
        } finally {
            fclose(file)
        }
    }

    private fun loadMetadata(): CacheMetadata {
        val path = metadataFilePath()
        val fileManager = NSFileManager.defaultManager
        if (!fileManager.fileExistsAtPath(path)) return CacheMetadata()
        return try {
            val content = readFileAsString(path) ?: return CacheMetadata()
            json.decodeFromString<CacheMetadata>(content)
        } catch (e: Exception) {
            Logger.w(TAG, e) { "Failed to load cache metadata" }
            CacheMetadata()
        }
    }

    private fun saveMetadata(metadata: CacheMetadata) {
        ensureCacheDirectoryExists()
        val path = metadataFilePath()
        try {
            val jsonStr = json.encodeToString(metadata)
            writeStringToFile(path, jsonStr)
        } catch (e: Exception) {
            Logger.w(TAG, e) { "Failed to save cache metadata" }
        }
    }

    actual fun currentSizeBytes(): Long {
        val metadata = loadMetadata()
        return metadata.entries.sumOf { it.sizeBytes }
    }

    actual fun clearAll() {
        val dir = cacheDirectory()
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
        val sizeBytes = when (val value = attributes?.get("NSFileSize")) {
            is Long -> value
            is Number -> value.toLong()
            else -> 0L
        }

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
        platform.Foundation.NSDate().timeIntervalSince1970.toLong() * 1000L
}
