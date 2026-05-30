package com.nuvio.app.features.torrent

import kotlinx.coroutines.CompletableDeferred
import platform.Foundation.NSHTTPURLResponse
import platform.Foundation.NSMutableURLRequest
import platform.Foundation.NSOperationQueue
import platform.Foundation.NSURL
import platform.Foundation.NSURLRequestReloadIgnoringLocalCacheData
import platform.Foundation.NSURLSession
import platform.Foundation.NSURLSessionConfiguration
import platform.Foundation.NSURLSessionDataTask
import platform.Foundation.setHTTPMethod
import platform.Foundation.setValue

actual object ExternalTorrentServerHttp {

    actual suspend fun fetchStreamUrl(requestUrl: String): String? {
        val url = NSURL(string = requestUrl)
        val nativeRequest = NSMutableURLRequest(
            uRL = url,
            cachePolicy = NSURLRequestReloadIgnoringLocalCacheData,
            timeoutInterval = 30.0,
        )
        nativeRequest.setHTTPMethod("GET")

        val completion = CompletableDeferred<String?>()
        val configuration = NSURLSessionConfiguration.defaultSessionConfiguration().apply {
            timeoutIntervalForRequest = 30.0
            timeoutIntervalForResource = 60.0
        }
        val session = NSURLSession.sessionWithConfiguration(
            configuration = configuration,
            delegate = null,
            delegateQueue = NSOperationQueue.mainQueue,
        )
        val task: NSURLSessionDataTask = session.dataTaskWithRequest(nativeRequest) { data, response, error ->
            if (error != null || response == null) {
                completion.complete(null)
                return@dataTaskWithRequest
            }
            val httpResponse = response as? NSHTTPURLResponse
            val statusCode = httpResponse?.statusCode?.toInt() ?: 0

            // Handle redirect
            if (statusCode in 300..399) {
                val location = httpResponse?.valueForHTTPHeaderField("Location")
                completion.complete(location)
                return@dataTaskWithRequest
            }

            if (statusCode in 200..299) {
                // Try parsing body as a URL
                if (data != null && data.length.toLong() > 0L) {
                    val bodyStr = platform.Foundation.NSString.create(
                        data = data,
                        encoding = platform.Foundation.NSUTF8StringEncoding,
                    )?.toString()?.trim()
                    if (bodyStr != null && (bodyStr.startsWith("http://") || bodyStr.startsWith("https://"))) {
                        completion.complete(bodyStr)
                        return@dataTaskWithRequest
                    }
                }
                // Use the final request URL
                completion.complete(httpResponse?.URL?.absoluteString ?: requestUrl)
                return@dataTaskWithRequest
            }

            completion.complete(null)
        }

        task.resume()
        val result = completion.await()
        session.finishTasksAndInvalidate()
        return result
    }

    actual suspend fun testReachability(baseUrl: String): Boolean {
        val url = NSURL(string = baseUrl)
        val nativeRequest = NSMutableURLRequest(
            uRL = url,
            cachePolicy = NSURLRequestReloadIgnoringLocalCacheData,
            timeoutInterval = 10.0,
        )
        nativeRequest.setHTTPMethod("HEAD")

        val completion = CompletableDeferred<Boolean>()
        val configuration = NSURLSessionConfiguration.defaultSessionConfiguration().apply {
            timeoutIntervalForRequest = 10.0
            timeoutIntervalForResource = 15.0
        }
        val session = NSURLSession.sessionWithConfiguration(
            configuration = configuration,
            delegate = null,
            delegateQueue = NSOperationQueue.mainQueue,
        )
        val task: NSURLSessionDataTask = session.dataTaskWithRequest(nativeRequest) { _, response, error ->
            if (error != null) {
                completion.complete(false)
                return@dataTaskWithRequest
            }
            val httpResponse = response as? NSHTTPURLResponse
            val statusCode = httpResponse?.statusCode?.toInt() ?: 0
            completion.complete(statusCode < 500)
        }

        task.resume()
        val result = completion.await()
        session.finishTasksAndInvalidate()
        return result
    }
}
