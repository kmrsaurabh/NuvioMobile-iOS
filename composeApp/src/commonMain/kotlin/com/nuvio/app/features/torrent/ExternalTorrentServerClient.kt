package com.nuvio.app.features.torrent

import co.touchlab.kermit.Logger
import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.get
import io.ktor.client.request.head
import io.ktor.client.request.parameter
import io.ktor.client.statement.bodyAsText
import io.ktor.client.statement.request
import io.ktor.http.isSuccess

object ExternalTorrentServerClient {
    private const val TAG = "TorrentExternal"

    private val client by lazy {
        HttpClient {
            install(HttpTimeout) {
                requestTimeoutMillis = 30_000
                connectTimeoutMillis = 10_000
                socketTimeoutMillis = 30_000
            }
            followRedirects = false
        }
    }

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
            val response = client.get(requestUrl)

            if (response.status.value in 300..399) {
                val location = response.headers["Location"]
                if (!location.isNullOrBlank()) {
                    Logger.d(TAG) { "External server redirected to: $location" }
                    TorrentResolveResult.Success(playbackUrl = location)
                } else {
                    TorrentResolveResult.Error("External server returned redirect without Location header")
                }
            } else if (response.status.isSuccess()) {
                val body = response.bodyAsText().trim()
                if (body.startsWith("http://") || body.startsWith("https://")) {
                    Logger.d(TAG) { "External server returned stream URL: $body" }
                    TorrentResolveResult.Success(playbackUrl = body)
                } else {
                    val finalUrl = response.request.url.toString()
                    Logger.d(TAG) { "Using final response URL: $finalUrl" }
                    TorrentResolveResult.Success(playbackUrl = finalUrl)
                }
            } else {
                TorrentResolveResult.Error("External server returned status ${response.status.value}")
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
            val response = client.head(baseUrl)
            Logger.d(TAG) { "Connection test to $baseUrl: status=${response.status.value}" }
            response.status.value < 500
        } catch (e: Exception) {
            try {
                val response = client.get(baseUrl)
                Logger.d(TAG) { "Connection test (GET fallback) to $baseUrl: status=${response.status.value}" }
                response.status.value < 500
            } catch (e2: Exception) {
                Logger.w(TAG, e2) { "Connection test failed for $baseUrl" }
                false
            }
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
