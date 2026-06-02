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

        val streamItem = com.nuvio.app.features.streams.StreamItem(
            infoHash = request.infoHash,
            fileIdx = request.fileIdx,
            torrentMagnetUri = null,
            behaviorHints = com.nuvio.app.features.streams.BehaviorHints(filename = request.filename),
            sources = request.trackers.map { "tracker:$it" }
        )

        val resolveResult = com.nuvio.app.features.torrent.TorrentStreamResolver.resolve(streamItem, request.fileIdx)
        if (resolveResult is com.nuvio.app.features.torrent.TorrentResolveResult.Error) {
            throw P2pStreamingException(resolveResult.message)
        }

        val successResult = resolveResult as com.nuvio.app.features.torrent.TorrentResolveResult.Success
        activeSessionId = successResult.sessionId

        if (activeSessionId != null) {
            // Native session started, wait for initial status to get proper stream URL if needed
            val status = NativeTorrentEngine.getSessionStatus(activeSessionId!!)
            if (status != null) {
                _state.value = P2pStreamingState.Streaming(
                    localUrl = successResult.playbackUrl,
                    downloadSpeed = status.downloadSpeedBps,
                    uploadSpeed = status.uploadSpeedBps,
                    peers = status.peerCount,
                    seeds = status.seedCount,
                    bufferProgress = 0f,
                    totalProgress = status.downloadProgress,
                )
            } else {
                _state.value = P2pStreamingState.Streaming(
                    localUrl = successResult.playbackUrl,
                    downloadSpeed = 0,
                    uploadSpeed = 0,
                    peers = 0,
                    seeds = 0,
                    bufferProgress = 0f,
                    totalProgress = 0f,
                )
            }
            startStatsPolling(activeSessionId!!)
        } else {
            // External server, just streaming URL, no stats polling
            _state.value = P2pStreamingState.Streaming(
                localUrl = successResult.playbackUrl,
                downloadSpeed = 0,
                uploadSpeed = 0,
                peers = 0,
                seeds = 0,
                bufferProgress = 0f,
                totalProgress = 0f,
            )
        }

        return successResult.playbackUrl
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
