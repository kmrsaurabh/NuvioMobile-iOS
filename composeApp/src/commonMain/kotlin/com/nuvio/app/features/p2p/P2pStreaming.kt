package com.nuvio.app.features.p2p

import com.nuvio.app.core.build.AppFeaturePolicy
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow



data class P2pStreamRequest(
    val infoHash: String,
    val fileIdx: Int?,
    val filename: String? = null,
    val trackers: List<String> = emptyList(),
)

sealed class P2pStreamingState {
    data object Idle : P2pStreamingState()
    data class Connecting(val peers: Int = 0, val downloadSpeed: Long = 0) : P2pStreamingState()

    data class Streaming(
        val localUrl: String,
        val downloadSpeed: Long,
        val uploadSpeed: Long,
        val peers: Int,
        val seeds: Int,
        val bufferProgress: Float,
        val totalProgress: Float,
        val preloadedBytes: Long = 0L,
    ) : P2pStreamingState()

    data class Error(val message: String) : P2pStreamingState()
}

class P2pStreamingException(message: String) : Exception(message)

expect object P2pStreamingEngine {
    val state: StateFlow<P2pStreamingState>
    suspend fun startStream(request: P2pStreamRequest): String
    fun stopStream()
    fun shutdown()
}

internal fun formatP2pSpeed(bytesPerSec: Long): String {
    return when {
        bytesPerSec >= 1_048_576 -> "${(bytesPerSec / 1_048_576.0).formatOneDecimal()} MB/s"
        else -> "${(bytesPerSec / 1_024.0).formatNoDecimal()} KB/s"
    }
}

internal fun formatP2pMegabytes(bytes: Long): String =
    "${(bytes / 1_048_576.0).formatOneDecimal()} MB"

private fun Double.formatOneDecimal(): String {
    val rounded = kotlin.math.round(this * 10.0) / 10.0
    val whole = rounded.toLong()
    val fraction = ((rounded - whole) * 10.0).toInt()
    return "$whole.$fraction"
}

private fun Double.formatNoDecimal(): String =
    kotlin.math.round(this).toInt().toString()
