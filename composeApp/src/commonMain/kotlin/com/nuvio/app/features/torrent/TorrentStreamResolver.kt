package com.nuvio.app.features.torrent

import co.touchlab.kermit.Logger
import com.nuvio.app.features.streams.StreamItem
import io.ktor.http.encodeURLParameter

sealed class TorrentResolveResult {
    data class Success(
        val playbackUrl: String,
        val headers: Map<String, String> = emptyMap(),
        val sessionId: String? = null,
    ) : TorrentResolveResult()

    data class Error(val message: String) : TorrentResolveResult()
}

object TorrentStreamResolver {
    private const val TAG = "TorrentResolver"

    suspend fun resolve(stream: StreamItem, fileIdx: Int? = null): TorrentResolveResult {
        val settings = TorrentStreamingRepository.uiState.value
        if (!settings.enabled) {
            return TorrentResolveResult.Error("Torrent streaming is disabled")
        }

        val infoHash = stream.infoHash
            ?: stream.clientResolve?.infoHash
        val magnetUri = stream.torrentMagnetUri
            ?: infoHash?.let { buildMagnetUri(it, stream) }
        val effectiveFileIdx = fileIdx ?: stream.fileIdx ?: stream.clientResolve?.fileIdx

        if (magnetUri == null && infoHash == null) {
            return TorrentResolveResult.Error("No torrent info hash or magnet URI available")
        }

        Logger.d(TAG) { "Resolving torrent: infoHash=$infoHash, fileIdx=$effectiveFileIdx" }

        return if (settings.isNativeModeAvailable) {
            resolveViaNativeEngine(settings, magnetUri, infoHash, effectiveFileIdx)
        } else {
            TorrentResolveResult.Error("No torrent streaming engine available")
        }
    }

    private suspend fun resolveViaNativeEngine(
        settings: TorrentStreamingSettings,
        magnetUri: String?,
        infoHash: String?,
        fileIdx: Int?,
    ): TorrentResolveResult {
        return try {
            if (!NativeTorrentEngine.isRunning()) {
                NativeTorrentEngine.start(settings)
            }
            val effectiveMagnet = appendTrackersToMagnet(
                baseMagnet = magnetUri ?: "magnet:?xt=urn:btih:${infoHash!!}",
                trackers = settings.parsedCustomTrackers()
            )
            val session = NativeTorrentEngine.addTorrent(effectiveMagnet, infoHash, fileIdx)
                ?: return TorrentResolveResult.Error("Failed to start torrent session: Engine returned null")
            
            if (session.state == TorrentSessionState.ERROR) {
                return TorrentResolveResult.Error(session.errorMessage ?: "Failed to start torrent session: Unknown error")
            }
            
            Logger.d(TAG) { "Native torrent session started: streamUrl=${session.streamUrl}" }
            TorrentResolveResult.Success(playbackUrl = session.streamUrl, sessionId = session.sessionId)
        } catch (e: Exception) {
            Logger.e(TAG, e) { "Native engine resolution failed" }
            TorrentResolveResult.Error("Torrent engine error: ${e.message}")
        }
    }

    private fun appendTrackersToMagnet(baseMagnet: String, trackers: List<String>): String {
        val defaultTrackers = listOf(
            "udp://tracker.opentrackr.org:1337/announce",
            "udp://open.tracker.cl:1337/announce",
            "udp://9.rarbg.com:2810/announce",
            "udp://tracker.torrent.eu.org:451/announce",
            "udp://exodus.desync.com:6969/announce",
            "udp://tracker.openbittorrent.com:6969/announce",
            "http://tracker.openbittorrent.com:80/announce",
            "udp://open.demonii.com:1337/announce"
        )
        val allTrackers = (defaultTrackers + trackers).distinct()
        
        val existingTrackers = baseMagnet.split("&tr=").drop(1).map { it.substringBefore("&") }
        val newTrackers = allTrackers.filter { tracker ->
            existingTrackers.none { it == tracker || it.contains(tracker) }
        }
        
        if (newTrackers.isEmpty()) return baseMagnet
        
        return buildString {
            append(baseMagnet)
            newTrackers.forEach { tracker ->
                append("&tr=")
                append(tracker.encodeURLParameter())
            }
        }
    }

    private fun buildMagnetUri(infoHash: String, stream: StreamItem): String {
        return buildString {
            append("magnet:?xt=urn:btih:")
            append(infoHash)
            stream.behaviorHints.filename?.takeIf { it.isNotBlank() }?.let { filename ->
                append("&dn=")
                append(filename.encodeURLParameter())
            }
            stream.sources.filter { !it.startsWith("dht:", ignoreCase = true) }.forEach { source ->
                val tracker = source.removePrefix("tracker:").trim()
                if (tracker.isNotBlank()) {
                    append("&tr=")
                    append(tracker.encodeURLParameter())
                }
            }
        }
    }

    fun shutdown() {
        if (NativeTorrentEngine.isRunning()) {
            NativeTorrentEngine.stop()
        }
    }
}
