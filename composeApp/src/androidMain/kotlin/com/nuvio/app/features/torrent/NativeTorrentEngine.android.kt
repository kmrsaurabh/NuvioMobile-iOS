package com.nuvio.app.features.torrent

actual object NativeTorrentEngine {
    actual fun start(settings: TorrentStreamingSettings) {}
    actual fun stop() {}
    actual fun isRunning(): Boolean = false
    actual suspend fun addTorrent(magnetUri: String, infoHash: String?, fileIdx: Int?): TorrentSessionStatus? = null
    actual fun removeTorrent(sessionId: String) {}
    actual fun getSessionStatus(sessionId: String): TorrentSessionStatus? = null
    actual fun getStats(): TorrentEngineStats = TorrentEngineStats()
    actual fun destroy() {}
}
