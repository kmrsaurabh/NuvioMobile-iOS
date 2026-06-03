package com.nuvio.app.features.torrent

expect object TorrentStreamingSettingsStorage {
    fun loadEnabled(): Boolean?
    fun saveEnabled(enabled: Boolean)
    fun loadCacheSizeMb(): Int?
    fun saveCacheSizeMb(sizeMb: Int)
    fun loadMaxConnections(): Int?
    fun saveMaxConnections(max: Int)
    fun loadDownloadSpeedLimit(): Int?
    fun saveDownloadSpeedLimit(kbps: Int)
    fun loadUploadSpeedLimit(): Int?
    fun saveUploadSpeedLimit(kbps: Int)
    fun loadEnableUpload(): Boolean?
    fun saveEnableUpload(enable: Boolean)
    fun loadEnableUpnp(): Boolean?
    fun saveEnableUpnp(enable: Boolean)
    fun loadForceTcp(): Boolean?
    fun saveForceTcp(force: Boolean)
    fun loadCustomTrackers(): String?
    fun saveCustomTrackers(trackers: String)
    fun loadPreferredPort(): Int?
    fun savePreferredPort(port: Int)
}
