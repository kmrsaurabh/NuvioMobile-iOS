package com.nuvio.app.features.torrent

expect object TorrentDiskCache {
    fun currentSizeBytes(): Long
    fun clearAll()
    fun evictIfNeeded(maxSizeMb: Int)
    fun getCachedFilePath(infoHash: String, fileIdx: Int): String?
    fun putCachedFile(infoHash: String, fileIdx: Int, filePath: String)
    fun removeCachedFile(infoHash: String, fileIdx: Int)
    fun markAccessed(infoHash: String, fileIdx: Int)
}
