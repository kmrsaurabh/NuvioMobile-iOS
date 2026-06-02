package com.nuvio.app.features.torrent

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nuvio.app.features.settings.SettingsGroup
import com.nuvio.app.features.settings.SettingsGroupDivider
import com.nuvio.app.features.settings.SettingsNavigationRow
import com.nuvio.app.features.settings.SettingsSection
import com.nuvio.app.features.settings.SettingsSwitchRow

@Composable
internal fun TorrentStreamingSettingsContent(
    isTablet: Boolean,
) {
    val settings by TorrentStreamingRepository.uiState.collectAsStateWithLifecycle()
    val sectionSpacing = if (isTablet) 18.dp else 12.dp
    var testResult by remember { mutableStateOf<String?>(null) }

    Column(
        verticalArrangement = Arrangement.spacedBy(sectionSpacing),
    ) {
        SettingsSection(
            title = "Torrent Streaming",
            isTablet = isTablet,
        ) {
            SettingsGroup(isTablet = isTablet) {
                SettingsSwitchRow(
                    title = "Enable P2P torrent streaming",
                    description = "Play torrent streams directly without a debrid service",
                    checked = settings.enabled,
                    isTablet = isTablet,
                    onCheckedChange = TorrentStreamingRepository::setEnabled,
                )

                if (settings.enabled) {
                    SettingsGroupDivider(isTablet = isTablet)
                    SettingsSwitchRow(
                        title = "Use external torrent server",
                        description = if (settings.useExternalServer && settings.externalServerUrl.isNotBlank()) {
                            settings.externalServerUrl
                        } else {
                            "Connect to a remote torrent server instead of the built-in engine"
                        },
                        checked = settings.useExternalServer,
                        isTablet = isTablet,
                        onCheckedChange = TorrentStreamingRepository::setUseExternalServer,
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    SettingsSwitchRow(
                        title = "Enable upload (seeding)",
                        description = "Share downloaded pieces with other peers",
                        checked = settings.enableUpload,
                        isTablet = isTablet,
                        onCheckedChange = TorrentStreamingRepository::setEnableUpload,
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    val isRunning = NativeTorrentEngine.isRunning()
                    SettingsNavigationRow(
                        title = if (isRunning) "Restart P2P Engine" else "Start P2P Engine",
                        description = testResult ?: "Verify that the native torrent engine can start successfully",
                        isTablet = isTablet,
                        onClick = {
                            try {
                                if (NativeTorrentEngine.isRunning()) {
                                    NativeTorrentEngine.stop()
                                }
                                NativeTorrentEngine.start(settings)
                                val stats = NativeTorrentEngine.getStats()
                                testResult = "🟢 Running (Active sessions: ${stats.activeSessions})"
                            } catch (e: Exception) {
                                testResult = "🔴 Offline (${e.message})"
                            }
                        },
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    SettingsNavigationRow(
                        title = "Max connections per torrent",
                        description = settings.maxConnectionsPerTorrent.toString(),
                        isTablet = isTablet,
                        onClick = { /* TODO: show max connections dialog */ },
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    SettingsNavigationRow(
                        title = "Cache size",
                        description = "${settings.cacheSizeMb} MB",
                        isTablet = isTablet,
                        onClick = { /* TODO: show cache size dialog */ },
                    )
                }
            }
        }
    }
}
