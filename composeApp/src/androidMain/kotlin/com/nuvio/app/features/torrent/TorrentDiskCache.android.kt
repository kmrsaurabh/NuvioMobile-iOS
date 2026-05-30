package com.nuvio.app.features.torrent

actual object TorrentDiskCache {
    actual fun currentSizeBytes(): Long = 0L
    actual fun clearAll() {}
    actual fun evictIfNeeded(maxSizeMb: Int) {}
    actual fun getCachedFilePath(infoHash: String, fileIdx: Int): String? = null
    actual fun putCachedFile(infoHash: String, fileIdx: Int, filePath: String) {}
    actual fun removeCachedFile(infoHash: String, fileIdx: Int) {}
    actual fun markAccessed(infoHash: String, fileIdx: Int) {}
}
