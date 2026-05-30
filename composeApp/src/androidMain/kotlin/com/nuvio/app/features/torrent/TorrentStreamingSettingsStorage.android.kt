package com.nuvio.app.features.torrent

actual object TorrentStreamingSettingsStorage {
    actual fun loadEnabled(): Boolean? = null
    actual fun saveEnabled(enabled: Boolean) {}
    actual fun loadUseExternalServer(): Boolean? = null
    actual fun saveUseExternalServer(useExternal: Boolean) {}
    actual fun loadExternalServerUrl(): String? = null
    actual fun saveExternalServerUrl(url: String) {}
    actual fun loadCacheSizeMb(): Int? = null
    actual fun saveCacheSizeMb(sizeMb: Int) {}
    actual fun loadMaxConnections(): Int? = null
    actual fun saveMaxConnections(max: Int) {}
    actual fun loadDownloadSpeedLimit(): Int? = null
    actual fun saveDownloadSpeedLimit(kbps: Int) {}
    actual fun loadUploadSpeedLimit(): Int? = null
    actual fun saveUploadSpeedLimit(kbps: Int) {}
    actual fun loadEnableUpload(): Boolean? = null
    actual fun saveEnableUpload(enable: Boolean) {}
    actual fun loadPreferredPort(): Int? = null
    actual fun savePreferredPort(port: Int) {}
}
