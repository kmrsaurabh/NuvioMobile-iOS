package com.nuvio.app.features.torrent

import co.touchlab.kermit.Logger

/**
 * Bridge interface for the native torrent engine.
 * Swift side implements this and registers a factory at app startup.
 */
interface TorrentEngineBridge {
    fun start(settings: TorrentStreamingSettings)
    fun stop()
    fun isRunning(): Boolean
    suspend fun addTorrent(magnetUri: String, infoHash: String?, fileIdx: Int?): TorrentSessionStatus?
    fun removeTorrent(sessionId: String)
    fun getSessionStatus(sessionId: String): TorrentSessionStatus?
    fun getStats(): TorrentEngineStats
    fun destroy()
}

/**
 * Interface for creating bridge instances.
 * Swift implements this to provide the factory.
 */
interface TorrentEngineBridgeCreator {
    fun createBridge(): TorrentEngineBridge
}

/**
 * Registry for the torrent engine bridge factory.
 * Swift calls [registerFactory] during app startup before Compose is initialized.
 * On iosAppStore builds where no bridge is registered, all operations are safe no-ops.
 */
object TorrentEngineBridgeFactory {
    private var factoryRef: TorrentEngineBridgeCreator? = null

    fun registerFactory(creator: TorrentEngineBridgeCreator) {
        this.factoryRef = creator
    }

    fun create(): TorrentEngineBridge? = factoryRef?.createBridge()

    val isRegistered: Boolean get() = factoryRef != null
}

actual object NativeTorrentEngine {
    private const val TAG = "NativeTorrent"

    private var bridge: TorrentEngineBridge? = null

    private fun ensureBridge(): TorrentEngineBridge? {
        if (bridge == null) {
            bridge = TorrentEngineBridgeFactory.create()
            if (bridge == null) {
                Logger.w(TAG) { "No TorrentEngineBridge registered — native P2P unavailable" }
            }
        }
        return bridge
    }

    actual fun start(settings: TorrentStreamingSettings) {
        val b = ensureBridge() ?: return
        Logger.d(TAG) { "Starting native torrent engine" }
        b.start(settings)
    }

    actual fun stop() {
        Logger.d(TAG) { "Stopping native torrent engine" }
        bridge?.stop()
    }

    actual fun isRunning(): Boolean {
        return bridge?.isRunning() ?: false
    }

    actual suspend fun addTorrent(magnetUri: String, infoHash: String?, fileIdx: Int?): TorrentSessionStatus? {
        val b = ensureBridge() ?: return null
        Logger.d(TAG) { "Adding torrent: infoHash=$infoHash, fileIdx=$fileIdx" }
        return b.addTorrent(magnetUri, infoHash, fileIdx)
    }

    actual fun removeTorrent(sessionId: String) {
        Logger.d(TAG) { "Removing torrent session: $sessionId" }
        bridge?.removeTorrent(sessionId)
    }

    actual fun getSessionStatus(sessionId: String): TorrentSessionStatus? {
        return bridge?.getSessionStatus(sessionId)
    }

    actual fun getStats(): TorrentEngineStats {
        return bridge?.getStats() ?: TorrentEngineStats()
    }

    actual fun destroy() {
        Logger.d(TAG) { "Destroying native torrent engine" }
        bridge?.destroy()
        bridge = null
    }
}
