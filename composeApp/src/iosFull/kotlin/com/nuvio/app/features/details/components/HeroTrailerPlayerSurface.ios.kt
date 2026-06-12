package com.nuvio.app.features.details.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.nuvio.app.features.player.PlatformPlayerSurface
import com.nuvio.app.features.player.PlayerResizeMode

@Composable
actual fun HeroTrailerPlayerSurface(
    sourceUrl: String,
    sourceAudioUrl: String?,
    playWhenReady: Boolean,
    muted: Boolean,
    modifier: Modifier,
    onReady: () -> Unit,
    onEnded: () -> Unit,
    onError: () -> Unit,
) {
    PlatformPlayerSurface(
        sourceUrl = sourceUrl,
        sourceAudioUrl = sourceAudioUrl,
        sourceHeaders = emptyMap(),
        sourceResponseHeaders = emptyMap(),
        useYoutubeChunkedPlayback = true,
        modifier = modifier,
        playWhenReady = playWhenReady,
        resizeMode = PlayerResizeMode.Crop,
        useNativeController = false,
        muted = muted,
        onReady = onReady,
        onEnded = onEnded,
        onControllerReady = {},
        onSnapshot = {},
        onError = { onError() },
    )
}
