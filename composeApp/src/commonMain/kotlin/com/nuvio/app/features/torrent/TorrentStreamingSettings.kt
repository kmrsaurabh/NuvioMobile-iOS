package com.nuvio.app.features.torrent

data class TorrentStreamingSettings(
    val enabled: Boolean = true,
    val cacheSizeMb: Int = 2048,
    val maxConnectionsPerTorrent: Int = 100,
    val downloadSpeedLimitKbps: Int = 0,
    val uploadSpeedLimitKbps: Int = 0,
    val enableUpload: Boolean = false,
    val enableUpnp: Boolean = false,
    val forceTcp: Boolean = false,
    val customTrackers: String = "",
    val preferredPort: Int = 0,
    val batterySaver: Boolean = true,
) {
    val isNativeModeAvailable: Boolean
        get() = com.nuvio.app.core.build.AppFeaturePolicy.p2pEnabled

    val canStream: Boolean
        get() = enabled && isNativeModeAvailable

    fun parsedCustomTrackers(): List<String> {
        return customTrackers.split(Regex("[\\n,;\\r]+"))
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .filter { it.startsWith("udp://") || it.startsWith("http://") || it.startsWith("https://") || it.startsWith("wss://") }
            .distinct()
    }
}
