package com.nuvio.app.features.p2p

import com.nuvio.app.features.torrent.NativeTorrentEngine
import com.nuvio.app.features.torrent.TorrentStreamingRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

actual object P2pStreamingEngine {
    private val _state = MutableStateFlow<P2pStreamingState>(P2pStreamingState.Idle)
    actual val state: StateFlow<P2pStreamingState> = _state.asStateFlow()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var statsJob: Job? = null
    private var activeSessionId: String? = null

    actual suspend fun startStream(request: P2pStreamRequest): String {
        stopStream()
        _state.value = P2pStreamingState.Connecting

        TorrentStreamingRepository.ensureLoaded()
        val settings = TorrentStreamingRepository.uiState.value
        if (!NativeTorrentEngine.isRunning()) {
            NativeTorrentEngine.start(settings)
        }

        val trackersParam = request.trackers.joinToString("") { "&tr=$it" }
        val magnetUri = "magnet:?xt=urn:btih:${request.infoHash}$trackersParam"

        val session = NativeTorrentEngine.addTorrent(magnetUri, request.infoHash, request.fileIdx)
            ?: throw P2pStreamingException("Failed to add torrent to NativeTorrentEngine")

        activeSessionId = session.sessionId

        _state.value = P2pStreamingState.Streaming(
            localUrl = session.streamUrl,
            downloadSpeed = session.downloadSpeedBps,
            uploadSpeed = session.uploadSpeedBps,
            peers = session.peerCount,
            seeds = session.seedCount,
            bufferProgress = 0f,
            totalProgress = session.downloadProgress,
        )

        startStatsPolling(session.sessionId)

        return session.streamUrl
    }

    actual fun stopStream() {
        activeSessionId?.let { sessionId ->
            NativeTorrentEngine.removeTorrent(sessionId)
        }
        activeSessionId = null
        statsJob?.cancel()
        statsJob = null
        _state.value = P2pStreamingState.Idle
    }

    actual fun shutdown() {
        stopStream()
        NativeTorrentEngine.stop()
    }

    private fun startStatsPolling(sessionId: String) {
        statsJob?.cancel()
        statsJob = scope.launch {
            while (isActive) {
                try {
                    val status = NativeTorrentEngine.getSessionStatus(sessionId)
                    val currentState = _state.value
                    if (status != null && currentState is P2pStreamingState.Streaming) {
                        _state.value = currentState.copy(
                            downloadSpeed = status.downloadSpeedBps,
                            uploadSpeed = status.uploadSpeedBps,
                            peers = status.peerCount,
                            seeds = status.seedCount,
                            totalProgress = status.downloadProgress,
                        )
                    }
                } catch (e: Exception) {
                    // Ignore polling errors
                }
                delay(1000L)
            }
        }
    }
}
