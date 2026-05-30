package com.nuvio.app.features.torrent

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

actual object ExternalTorrentServerHttp {
    actual suspend fun fetchStreamUrl(requestUrl: String): String? = withContext(Dispatchers.IO) {
        try {
            val connection = URL(requestUrl).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10_000
            connection.readTimeout = 30_000
            connection.requestMethod = "GET"
            connection.connect()
            val statusCode = connection.responseCode
            if (statusCode in 300..399) {
                connection.getHeaderField("Location")
            } else if (statusCode in 200..299) {
                val body = connection.inputStream.bufferedReader().readText().trim()
                if (body.startsWith("http://") || body.startsWith("https://")) body
                else connection.url.toString()
            } else null
        } catch (_: Exception) { null }
    }

    actual suspend fun testReachability(baseUrl: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val connection = URL(baseUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 10_000
            connection.requestMethod = "HEAD"
            connection.connect()
            connection.responseCode < 500
        } catch (_: Exception) { false }
    }
}
