package com.nuvio.app.features.torrent

data class TorrentSessionStatus(
    val sessionId: String,
    val streamUrl: String,
    val downloadProgress: Float = 0f,
    val downloadSpeedBps: Long = 0L,
    val uploadSpeedBps: Long = 0L,
    val preloadedBytes: Long = 0L,
    val seedCount: Int = 0,
    val peerCount: Int = 0,
    val state: TorrentSessionState = TorrentSessionState.STARTING,
    val errorMessage: String? = null,
)

enum class TorrentSessionState {
    STARTING,
    DOWNLOADING_METADATA,
    DOWNLOADING,
    STREAMING_READY,
    SEEDING,
    STOPPED,
    ERROR,
}

data class TorrentEngineStats(
    val activeSessions: Int = 0,
    val totalDownloadSpeedBps: Long = 0L,
    val totalUploadSpeedBps: Long = 0L,
)

expect object NativeTorrentEngine {
    fun start(settings: TorrentStreamingSettings)
    fun stop()
    fun isRunning(): Boolean
    suspend fun addTorrent(magnetUri: String, infoHash: String?, fileIdx: Int?): TorrentSessionStatus?
    fun removeTorrent(sessionId: String)
    fun getSessionStatus(sessionId: String): TorrentSessionStatus?
    fun getStats(): TorrentEngineStats
    fun destroy()
}
