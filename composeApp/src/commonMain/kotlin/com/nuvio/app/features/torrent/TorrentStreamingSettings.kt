package com.nuvio.app.features.torrent

data class TorrentStreamingSettings(
    val enabled: Boolean = true,
    val useExternalServer: Boolean = false,
    val externalServerUrl: String = "",
    val cacheSizeMb: Int = 2048,
    val maxConnectionsPerTorrent: Int = 100,
    val downloadSpeedLimitKbps: Int = 0,
    val uploadSpeedLimitKbps: Int = 0,
    val enableUpload: Boolean = false,
    val preferredPort: Int = 0,
) {
    val isNativeModeAvailable: Boolean
        get() = com.nuvio.app.core.build.AppFeaturePolicy.p2pEnabled

    val isExternalServerConfigured: Boolean
        get() = useExternalServer && externalServerUrl.isNotBlank()

    val canStream: Boolean
        get() = enabled && (isExternalServerConfigured || (!useExternalServer && isNativeModeAvailable))
}
