package com.nuvio.app.features.torrent

import co.touchlab.kermit.Logger
import com.nuvio.app.features.streams.StreamItem

sealed class TorrentResolveResult {
    data class Success(
        val playbackUrl: String,
        val headers: Map<String, String> = emptyMap(),
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

        Logger.d(TAG) { "Resolving torrent: infoHash=$infoHash, fileIdx=$effectiveFileIdx, external=${settings.useExternalServer}" }

        return if (settings.useExternalServer && settings.externalServerUrl.isNotBlank()) {
            resolveViaExternalServer(settings.externalServerUrl, infoHash, magnetUri, effectiveFileIdx)
        } else if (settings.isNativeModeAvailable) {
            resolveViaNativeEngine(settings, magnetUri, infoHash, effectiveFileIdx)
        } else {
            TorrentResolveResult.Error("No torrent streaming engine available")
        }
    }

    private suspend fun resolveViaExternalServer(
        serverUrl: String,
        infoHash: String?,
        magnetUri: String?,
        fileIdx: Int?,
    ): TorrentResolveResult {
        return try {
            ExternalTorrentServerClient.resolve(serverUrl, infoHash, magnetUri, fileIdx)
        } catch (e: Exception) {
            Logger.e(TAG, e) { "External server resolution failed" }
            TorrentResolveResult.Error("External server error: ${e.message}")
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
            val effectiveMagnet = magnetUri ?: "magnet:?xt=urn:btih:${infoHash!!}"
            val session = NativeTorrentEngine.addTorrent(effectiveMagnet, infoHash, fileIdx)
                ?: return TorrentResolveResult.Error("Failed to start torrent session")
            Logger.d(TAG) { "Native torrent session started: streamUrl=${session.streamUrl}" }
            TorrentResolveResult.Success(playbackUrl = session.streamUrl)
        } catch (e: Exception) {
            Logger.e(TAG, e) { "Native engine resolution failed" }
            TorrentResolveResult.Error("Torrent engine error: ${e.message}")
        }
    }

    private fun buildMagnetUri(infoHash: String, stream: StreamItem): String {
        return buildString {
            append("magnet:?xt=urn:btih:")
            append(infoHash)
            stream.behaviorHints.filename?.takeIf { it.isNotBlank() }?.let { filename ->
                append("&dn=")
                append(filename)
            }
            stream.sources.filter { !it.startsWith("dht:", ignoreCase = true) }.forEach { source ->
                val tracker = source.removePrefix("tracker:").trim()
                if (tracker.isNotBlank()) {
                    append("&tr=")
                    append(tracker)
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
