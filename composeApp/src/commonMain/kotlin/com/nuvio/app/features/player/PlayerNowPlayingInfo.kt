package com.nuvio.app.features.player

/**
 * Platform media metadata published to system Now Playing / media controls.
 *
 * The common runtime owns only clean content metadata. Platform implementations
 * decide whether and how to publish it to OS media surfaces.
 */
data class PlayerNowPlayingInfo(
    val title: String,
    val subtitle: String? = null,
    val artworkUrl: String? = null,
)

internal interface NowPlayingMetadataController {
    fun updateNowPlayingMetadata(info: PlayerNowPlayingInfo)
    fun clearNowPlayingInfo()
}

internal fun PlayerEngineController.updateNowPlayingMetadata(info: PlayerNowPlayingInfo) {
    (this as? NowPlayingMetadataController)?.updateNowPlayingMetadata(info)
}

internal fun PlayerEngineController.clearNowPlayingInfo() {
    (this as? NowPlayingMetadataController)?.clearNowPlayingInfo()
}
