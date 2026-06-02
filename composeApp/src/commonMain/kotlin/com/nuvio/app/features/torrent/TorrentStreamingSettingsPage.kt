package com.nuvio.app.features.torrent

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
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

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun TorrentStreamingSettingsContent(
    isTablet: Boolean,
) {
    val settings by TorrentStreamingRepository.uiState.collectAsStateWithLifecycle()
    val sectionSpacing = if (isTablet) 18.dp else 12.dp
    var testResult by remember { mutableStateOf<String?>(null) }
    var showUrlDialog by remember { mutableStateOf(false) }

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
                    if (settings.useExternalServer) {
                        SettingsGroupDivider(isTablet = isTablet)
                        SettingsNavigationRow(
                            title = "External server URL",
                            description = settings.externalServerUrl.ifBlank { "Tap to configure" },
                            isTablet = isTablet,
                            onClick = { showUrlDialog = true }
                        )
                    }
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
                    androidx.compose.runtime.LaunchedEffect(Unit) {
                        while (true) {
                            if (NativeTorrentEngine.isRunning()) {
                                try {
                                    val stats = NativeTorrentEngine.getStats()
                                    testResult = "🟢 Running (Active sessions: ${stats.activeSessions})"
                                } catch (e: Exception) {
                                    testResult = "🟢 Running"
                                }
                            } else {
                                testResult = "🔴 Offline"
                            }
                            kotlinx.coroutines.delay(1000)
                        }
                    }
                    SettingsNavigationRow(
                        title = if (isRunning) "Restart P2P Engine" else "Start P2P Engine",
                        description = testResult ?: "Checking status...",
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

    if (showUrlDialog) {
        var draft by remember { mutableStateOf(settings.externalServerUrl) }
        androidx.compose.material3.BasicAlertDialog(onDismissRequest = { showUrlDialog = false }) {
            androidx.compose.material3.Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp),
                color = androidx.compose.material3.MaterialTheme.colorScheme.surface,
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    androidx.compose.material3.Text(
                        text = "External Server URL",
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                    )
                    androidx.compose.material3.OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        placeholder = { androidx.compose.material3.Text("http://...") }
                    )
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End),
                    ) {
                        androidx.compose.material3.TextButton(onClick = { showUrlDialog = false }) {
                            androidx.compose.material3.Text("Cancel")
                        }
                        androidx.compose.material3.Button(
                            onClick = {
                                TorrentStreamingRepository.setExternalServerUrl(draft)
                                showUrlDialog = false
                            },
                        ) {
                            androidx.compose.material3.Text("Save")
                        }
                    }
                }
            }
        }
    }
}
