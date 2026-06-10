package com.nuvio.app.features.player

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect

@Composable
internal actual fun PlayerScreenRuntime.PlatformNowPlayingMetadataEffect() {
    LaunchedEffect(
        playerController,
        title,
        activeSeasonNumber,
        activeEpisodeNumber,
        activeEpisodeTitle,
        activeEpisodeThumbnail,
        poster,
    ) {
        val controller = playerController ?: return@LaunchedEffect

        val contentTitle = title
            .trim()
            .takeIf { it.isNotEmpty() }
            ?: "Nuvio"

        val episodePrefix = when {
            activeSeasonNumber != null && activeEpisodeNumber != null ->
                "S${activeSeasonNumber.toString().padStart(2, '0')}E${activeEpisodeNumber.toString().padStart(2, '0')}"
            activeEpisodeNumber != null ->
                "E${activeEpisodeNumber.toString().padStart(2, '0')}"
            else -> null
        }

        val episodeName = activeEpisodeTitle
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

        val nowPlayingSubtitle = listOfNotNull(
            episodePrefix,
            episodeName,
        )
            .distinct()
            .joinToString(" • ")
            .takeIf { it.isNotEmpty() }

        val posterArtworkUrl = poster
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

        val episodeArtworkUrl = activeEpisodeThumbnail
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

        val isSeriesPlayback = activeSeasonNumber != null ||
            activeEpisodeNumber != null ||
            episodeName != null

        val artworkUrl = if (isSeriesPlayback && episodeArtworkUrl != null) {
            episodeArtworkUrl
        } else {
            posterArtworkUrl
        }

        controller.updateNowPlayingMetadata(
            PlayerNowPlayingInfo(
                title = contentTitle,
                subtitle = nowPlayingSubtitle,
                artworkUrl = artworkUrl,
            )
        )
    }

    DisposableEffect(playerController) {
        val controller = playerController
        onDispose {
            controller?.clearNowPlayingInfo()
        }
    }
}
