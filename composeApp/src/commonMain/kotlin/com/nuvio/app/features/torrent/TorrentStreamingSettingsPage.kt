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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun TorrentStreamingSettingsContent(
    isTablet: Boolean,
) {
    val settings by TorrentStreamingRepository.uiState.collectAsStateWithLifecycle()
    val sectionSpacing = if (isTablet) 18.dp else 12.dp
    var testResult by remember { mutableStateOf<String?>(null) }
    var showUploadLimitDialog by remember { mutableStateOf(false) }
    var showCacheSizeDialog by remember { mutableStateOf(false) }
    var showUpnpInfoDialog by remember { mutableStateOf(false) }
    
    var currentCacheSizeBytes by remember { mutableStateOf(0L) }
    androidx.compose.runtime.LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) {
            currentCacheSizeBytes = TorrentDiskCache.currentSizeBytes()
        }
    }

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
                        title = if (isRunning) "Stop P2P Engine" else "Start P2P Engine",
                        description = testResult ?: "Checking status...",
                        isTablet = isTablet,
                        onClick = {
                            try {
                                if (NativeTorrentEngine.isRunning()) {
                                    NativeTorrentEngine.stop()
                                } else {
                                    NativeTorrentEngine.start(settings)
                                }
                            } catch (e: Exception) {
                                testResult = "🔴 Offline (${e.message})"
                            }
                        },
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    SettingsSwitchRow(
                        title = "Enable UPnP (Port Forwarding)",
                        description = "Allows incoming connections for faster streaming (may crash older routers).",
                        checked = settings.enableUpnp,
                        onCheckedChange = { TorrentStreamingRepository.setEnableUpnp(it) },
                        isTablet = isTablet,
                        actionIcon = {
                            IconButton(onClick = { showUpnpInfoDialog = true }) {
                                Icon(
                                    imageVector = Icons.Rounded.Info,
                                    contentDescription = "UPnP Information",
                                    tint = androidx.compose.material3.MaterialTheme.colorScheme.primary
                                )
                            }
                        }
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    SettingsNavigationRow(
                        title = "Upload Speed Limit",
                        description = if (settings.uploadSpeedLimitKbps == 0) "Unlimited" else "${settings.uploadSpeedLimitKbps} KB/s",
                        isTablet = isTablet,
                        onClick = { showUploadLimitDialog = true },
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    SettingsNavigationRow(
                        title = "Disk Cache Size Limit",
                        description = if (settings.cacheSizeMb == 0) "Unlimited" else "${settings.cacheSizeMb} MB",
                        isTablet = isTablet,
                        onClick = { showCacheSizeDialog = true },
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    val cacheMb = currentCacheSizeBytes / (1024 * 1024)
                    SettingsNavigationRow(
                        title = "Clear Cached Videos",
                        description = "Free up storage space used by P2P streams. (Currently used: $cacheMb MB)",
                        isTablet = isTablet,
                        onClick = { 
                            NativeTorrentEngine.stop()
                            com.nuvio.app.features.torrent.TorrentDiskCache.clearAll()
                            currentCacheSizeBytes = 0L
                        },
                    )

                }
            }
        }
    }
    
    if (showUpnpInfoDialog) {
        androidx.compose.material3.BasicAlertDialog(onDismissRequest = { showUpnpInfoDialog = false }) {
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
                        text = "UPnP (Universal Plug and Play)",
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                    )
                    androidx.compose.material3.Text(
                        text = "UPnP automatically opens a port on your home router to accept incoming peer connections.\n\n" +
                               "• Helpful on Home Wi-Fi for faster P2P streaming.\n" +
                               "• Useless on Cellular networks (due to Carrier NAT).\n" +
                               "• May crash older/buggy routers.\n\n" +
                               "Turn ON for home Wi-Fi. Turn OFF if you experience router issues or use Cellular data.",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        androidx.compose.material3.TextButton(onClick = { showUpnpInfoDialog = false }) {
                            androidx.compose.material3.Text("Close")
                        }
                    }
                }
            }
        }
    }



    if (showUploadLimitDialog) {
        var draft by remember { mutableStateOf(if (settings.uploadSpeedLimitKbps == 0) "" else settings.uploadSpeedLimitKbps.toString()) }
        androidx.compose.material3.BasicAlertDialog(onDismissRequest = { showUploadLimitDialog = false }) {
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
                        text = "Upload Speed Limit (KB/s)",
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                    )
                    androidx.compose.material3.Text(
                        text = "Leave empty or 0 for unlimited.",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    androidx.compose.material3.OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it.filter { char -> char.isDigit() } },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        placeholder = { androidx.compose.material3.Text("e.g. 500") }
                    )
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End),
                    ) {
                        androidx.compose.material3.TextButton(onClick = { showUploadLimitDialog = false }) {
                            androidx.compose.material3.Text("Cancel")
                        }
                        androidx.compose.material3.Button(
                            onClick = {
                                TorrentStreamingRepository.setUploadSpeedLimit(draft.toIntOrNull() ?: 0)
                                showUploadLimitDialog = false
                            },
                        ) {
                            androidx.compose.material3.Text("Save")
                        }
                    }
                }
            }
        }
    }

    if (showCacheSizeDialog) {
        var draft by remember { mutableStateOf(if (settings.cacheSizeMb == 0) "" else settings.cacheSizeMb.toString()) }
        androidx.compose.material3.BasicAlertDialog(onDismissRequest = { showCacheSizeDialog = false }) {
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
                        text = "Disk Cache Size Limit (MB)",
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                    )
                    androidx.compose.material3.Text(
                        text = "Leave empty or 0 for unlimited (not recommended). Default is 2048 MB.",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    androidx.compose.material3.OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it.filter { char -> char.isDigit() } },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        placeholder = { androidx.compose.material3.Text("e.g. 2048") }
                    )
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End),
                    ) {
                        androidx.compose.material3.TextButton(onClick = { showCacheSizeDialog = false }) {
                            androidx.compose.material3.Text("Cancel")
                        }
                        androidx.compose.material3.Button(
                            onClick = {
                                TorrentStreamingRepository.setCacheSizeMb(draft.toIntOrNull() ?: 0)
                                showCacheSizeDialog = false
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
