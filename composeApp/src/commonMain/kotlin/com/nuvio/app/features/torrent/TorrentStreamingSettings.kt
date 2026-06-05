package com.nuvio.app.features.torrent

data class TorrentStreamingSettings(
    val enabled: Boolean = true,
    val maxConnectionsPerTorrent: Int = 100,
    val downloadSpeedLimitKbps: Int = 0,
    val uploadSpeedLimitKbps: Int = 0,
    val enableUpload: Boolean = false,
    val enableUpnp: Boolean = false,
    val forceTcp: Boolean = false,
    val preferredPort: Int = 0,
    val batterySaver: Boolean = false,
) {
    val isNativeModeAvailable: Boolean
        get() = com.nuvio.app.core.build.AppFeaturePolicy.p2pEnabled

    val canStream: Boolean
        get() = enabled && isNativeModeAvailable
}
