package com.nuvio.app.features.torrent

import co.touchlab.kermit.Logger

/**
 * Client for resolving torrent streams via an external streaming server.
 * Uses platform-specific HTTP implementation (expect/actual) to avoid
 * direct ktor-client dependency in commonMain.
 */
object ExternalTorrentServerClient {
    private const val TAG = "TorrentExternal"

    suspend fun resolve(
        serverUrl: String,
        infoHash: String?,
        magnetUri: String?,
        fileIdx: Int?,
    ): TorrentResolveResult {
        if (serverUrl.isBlank()) {
            return TorrentResolveResult.Error("External server URL is empty")
        }

        val hash = infoHash ?: extractInfoHash(magnetUri)
        if (hash.isNullOrBlank()) {
            return TorrentResolveResult.Error("No info hash available for external server resolution")
        }

        val baseUrl = serverUrl.trimEnd('/')
        val idx = fileIdx ?: 0
        val requestUrl = "$baseUrl/$hash/$idx"

        Logger.d(TAG) { "Resolving via external server: $requestUrl" }

        return try {
            val playbackUrl = ExternalTorrentServerHttp.fetchStreamUrl(requestUrl)
            if (playbackUrl != null) {
                Logger.d(TAG) { "External server resolved to: $playbackUrl" }
                TorrentResolveResult.Success(playbackUrl = playbackUrl)
            } else {
                TorrentResolveResult.Error("External server returned no usable stream URL")
            }
        } catch (e: Exception) {
            Logger.e(TAG, e) { "External server request failed" }
            TorrentResolveResult.Error("External server error: ${e.message}")
        }
    }

    suspend fun testConnection(serverUrl: String): Boolean {
        if (serverUrl.isBlank()) return false
        val baseUrl = serverUrl.trimEnd('/')
        return try {
            val reachable = ExternalTorrentServerHttp.testReachability(baseUrl)
            Logger.d(TAG) { "Connection test to $baseUrl: reachable=$reachable" }
            reachable
        } catch (e: Exception) {
            Logger.w(TAG, e) { "Connection test failed for $baseUrl" }
            false
        }
    }

    private fun extractInfoHash(magnetUri: String?): String? {
        if (magnetUri.isNullOrBlank()) return null
        val btihPrefix = "urn:btih:"
        val idx = magnetUri.indexOf(btihPrefix, ignoreCase = true)
        if (idx < 0) return null
        val start = idx + btihPrefix.length
        val end = magnetUri.indexOf('&', start).let { if (it < 0) magnetUri.length else it }
        return magnetUri.substring(start, end).takeIf { it.isNotBlank() }
    }
}

/**
 * Platform-specific HTTP operations for the external torrent server client.
 */
expect object ExternalTorrentServerHttp {
    /**
     * Fetches a stream URL from the external torrent server.
     * Should follow redirects and return the final URL, or parse the response body as a URL.
     * Returns null if no usable URL was found.
     */
    suspend fun fetchStreamUrl(requestUrl: String): String?

    /**
     * Tests whether the external server is reachable.
     * Returns true if the server responds with a non-5xx status code.
     */
    suspend fun testReachability(baseUrl: String): Boolean
}
