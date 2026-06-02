package com.nuvio.app.features.torrent

import co.touchlab.kermit.Logger
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Adapter that bridges the Kotlin [TorrentEngineBridge] protocol to the
 * Swift [TorrentEngineSwiftBridge] singleton, which uses JSON-based ObjC interop.
 */
class TorrentEngineBridgeAdapter(
    private val swiftBridge: SwiftTorrentBridge,
) : TorrentEngineBridge {

    private val json = Json { ignoreUnknownKeys = true }

    override fun start(settings: TorrentStreamingSettings) {
        val configJson = buildString {
            append("{")
            append("\"httpPort\":${settings.preferredPort},")
            append("\"maxCacheSizeBytes\":${settings.cacheSizeMb.toLong() * 1024L * 1024L},")
            append("\"maxDownloadRate\":${settings.downloadSpeedLimitKbps * 1024},")
            append("\"maxUploadRate\":${settings.uploadSpeedLimitKbps * 1024},")
            append("\"maxPeerConnections\":${settings.maxConnectionsPerTorrent},")
            append("\"enableDHT\":true")
            append("}")
        }
        swiftBridge.startEngine(configJson)
    }

    override fun stop() {
        swiftBridge.stopEngine()
    }

    override fun isRunning(): Boolean {
        return swiftBridge.isEngineRunning()
    }

    override suspend fun addTorrent(
        magnetUri: String,
        infoHash: String?,
        fileIdx: Int?,
    ): TorrentSessionStatus? {
        val hash = infoHash ?: extractInfoHash(magnetUri) ?: return null
        val resultJson = swiftBridge.addTorrentSession(magnetUri, hash, (fileIdx ?: -1))
        return parseSessionStatus(resultJson)
    }

    override fun removeTorrent(sessionId: String) {
        swiftBridge.removeTorrentSession(sessionId)
    }

    override fun getSessionStatus(sessionId: String): TorrentSessionStatus? {
        val resultJson = swiftBridge.getSessionStatusJson(sessionId)
        return parseSessionStatus(resultJson)
    }

    override fun getStats(): TorrentEngineStats {
        val statsJson = swiftBridge.getEngineStatsJson()
        return try {
            val parsed = json.decodeFromString<SwiftEngineStats>(statsJson)
            TorrentEngineStats(
                activeSessions = parsed.activeSessions,
                totalDownloadSpeedBps = parsed.totalDownloadRate,
                totalUploadSpeedBps = parsed.totalUploadRate,
            )
        } catch (e: Exception) {
            Logger.w("TorrentBridgeAdapter", e) { "Failed to parse engine stats" }
            TorrentEngineStats()
        }
    }

    override fun destroy() {
        swiftBridge.destroyEngine()
    }

    private fun parseSessionStatus(jsonStr: String): TorrentSessionStatus? {
        if (jsonStr.isBlank() || jsonStr == "{}") return null
        return try {
            val parsed = json.decodeFromString<SwiftSessionState>(jsonStr)
            if (parsed.errorMessage != null && parsed.sessionId.isBlank()) return null
            TorrentSessionStatus(
                sessionId = parsed.sessionId,
                streamUrl = parsed.streamUrl,
                downloadProgress = parsed.progress.toFloat(),
                downloadSpeedBps = parsed.downloadRate,
                uploadSpeedBps = parsed.uploadRate,
                seedCount = parsed.numSeeds,
                peerCount = parsed.numPeers,
                state = mapStatus(parsed.status),
            )
        } catch (e: Exception) {
            Logger.w("TorrentBridgeAdapter", e) { "Failed to parse session status: $jsonStr" }
            null
        }
    }

    private fun mapStatus(status: String): TorrentSessionState {
        return when (status) {
            "initializing" -> TorrentSessionState.STARTING
            "resolvingmetadata", "resolving_metadata" -> TorrentSessionState.DOWNLOADING_METADATA
            "downloading" -> TorrentSessionState.DOWNLOADING
            "streaming" -> TorrentSessionState.STREAMING_READY
            "completed" -> TorrentSessionState.SEEDING
            "paused", "stopped" -> TorrentSessionState.STOPPED
            "error" -> TorrentSessionState.ERROR
            else -> TorrentSessionState.STARTING
        }
    }

    private fun extractInfoHash(magnetUri: String): String? {
        val btihPrefix = "urn:btih:"
        val idx = magnetUri.indexOf(btihPrefix, ignoreCase = true)
        if (idx < 0) return null
        val start = idx + btihPrefix.length
        val end = magnetUri.indexOf('&', start).let { if (it < 0) magnetUri.length else it }
        return magnetUri.substring(start, end).takeIf { it.isNotBlank() }
    }
}

/**
 * ObjC-compatible interface that the Swift side implements.
 * This is what Swift's TorrentEngineSwiftBridge exposes to Kotlin.
 */
interface SwiftTorrentBridge {
    fun startEngine(configJson: String)
    fun stopEngine()
    fun isEngineRunning(): Boolean
    fun addTorrentSession(magnetUri: String, infoHash: String, fileIdx: Int): String
    fun removeTorrentSession(sessionId: String)
    fun getSessionStatusJson(sessionId: String): String
    fun getEngineStatsJson(): String
    fun destroyEngine()
}

// JSON model for parsing Swift session state responses
@Serializable
private data class SwiftSessionState(
    val sessionId: String = "",
    val infoHash: String = "",
    val magnetUri: String = "",
    val fileIndex: Int = 0,
    val status: String = "initializing",
    val streamUrl: String = "",
    val fileName: String = "",
    val totalSizeBytes: Long = 0,
    val downloadedBytes: Long = 0,
    val downloadRate: Long = 0,
    val uploadRate: Long = 0,
    val numPeers: Int = 0,
    val numSeeds: Int = 0,
    val progress: Double = 0.0,
    val isMetadataResolved: Boolean = false,
    val isStreaming: Boolean = false,
    val errorMessage: String? = null,
)

@Serializable
private data class SwiftEngineStats(
    val activeSessions: Int = 0,
    val totalDownloadRate: Long = 0,
    val totalUploadRate: Long = 0,
    val httpServerPort: Int = 0,
    val httpServerRunning: Boolean = false,
)
