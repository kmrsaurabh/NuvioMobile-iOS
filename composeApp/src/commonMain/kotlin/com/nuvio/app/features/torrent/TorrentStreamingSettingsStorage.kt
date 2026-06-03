package com.nuvio.app.features.torrent

expect object TorrentStreamingSettingsStorage {
    fun loadEnabled(): Boolean?
    fun saveEnabled(enabled: Boolean)
    fun loadUseExternalServer(): Boolean?
    fun saveUseExternalServer(useExternal: Boolean)
    fun loadExternalServerUrl(): String?
    fun saveExternalServerUrl(url: String)
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
    fun loadPreferredPort(): Int?
    fun savePreferredPort(port: Int)
}
