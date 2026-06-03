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
    var showTcpInfoDialog by remember { mutableStateOf(false) }
    var showTrackersInfoDialog by remember { mutableStateOf(false) }
    var showCustomTrackersDialog by remember { mutableStateOf(false) }
    var showBatterySaverInfoDialog by remember { mutableStateOf(false) }
    
    var currentCacheSizeBytes by remember { mutableStateOf(0L) }
    androidx.compose.runtime.LaunchedEffect(Unit) {
        withContext(Dispatchers.Default) {
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
                        title = "Battery Saver Mode (Low Power)",
                        description = "Saves battery by disabling DHT & PEX and limiting peers.",
                        checked = settings.batterySaver,
                        onCheckedChange = { TorrentStreamingRepository.setBatterySaver(it) },
                        isTablet = isTablet,
                        actionIcon = {
                            IconButton(onClick = { showBatterySaverInfoDialog = true }) {
                                Icon(
                                    imageVector = Icons.Rounded.Info,
                                    contentDescription = "Battery Saver Information",
                                    tint = androidx.compose.material3.MaterialTheme.colorScheme.primary
                                )
                            }
                        }
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
                    SettingsSwitchRow(
                        title = "Force TCP Connections",
                        description = "Disable uTP and force aggressive TCP peer connections.",
                        checked = settings.forceTcp,
                        onCheckedChange = { TorrentStreamingRepository.setForceTcp(it) },
                        isTablet = isTablet,
                        actionIcon = {
                            IconButton(onClick = { showTcpInfoDialog = true }) {
                                Icon(
                                    imageVector = Icons.Rounded.Info,
                                    contentDescription = "Force TCP Information",
                                    tint = androidx.compose.material3.MaterialTheme.colorScheme.primary
                                )
                            }
                        }
                    )
                    SettingsGroupDivider(isTablet = isTablet)
                    SettingsNavigationRow(
                        title = "Custom Trackers",
                        description = "Auto-inject high-speed trackers to magnet links.",
                        isTablet = isTablet,
                        onClick = { showCustomTrackersDialog = true },
                        actionIcon = {
                            IconButton(onClick = { showTrackersInfoDialog = true }) {
                                Icon(
                                    imageVector = Icons.Rounded.Info,
                                    contentDescription = "Custom Trackers Information",
                                    tint = androidx.compose.material3.MaterialTheme.colorScheme.primary
                                )
                            }
                        }
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
    
    
    if (showBatterySaverInfoDialog) {
        androidx.compose.material3.BasicAlertDialog(onDismissRequest = { showBatterySaverInfoDialog = false }) {
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
                        text = "Battery Saver Mode (Low Power)",
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                    )
                    androidx.compose.material3.Text(
                        text = "When enabled, the Torrent Engine disables UDP chatter (DHT & PEX) and strictly limits active peer connections.\n\n" +
                               "• Extremely friendly for device battery and temperature.\n" +
                               "• No speed impact on popular torrents with many seeds.\n" +
                               "• May take a few extra seconds to find seeds on very rare/dead torrents.\n\n" +
                               "Recommended to keep ON unless you stream very obscure content.",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        androidx.compose.material3.TextButton(onClick = { showBatterySaverInfoDialog = false }) {
                            androidx.compose.material3.Text("Close")
                        }
                    }
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

    if (showTcpInfoDialog) {
        androidx.compose.material3.BasicAlertDialog(onDismissRequest = { showTcpInfoDialog = false }) {
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
                        text = "Force TCP (Disable uTP)",
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                    )
                    androidx.compose.material3.Text(
                        text = "By default, BitTorrent uses uTP (UDP) to be polite to your network. However, some ISPs throttle UDP traffic.\n\n" +
                               "• Pros: Forcing TCP can result in drastically faster speeds if your ISP throttles UDP.\n" +
                               "• Tradeoffs: TCP is aggressive and may slow down other devices on your network.\n\n" +
                               "When to enable: If your torrents are stuck on 'Downloading metadata' or buffering heavily.\n" +
                               "When to disable: If you want to keep your network smooth for other users while streaming.",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        androidx.compose.material3.TextButton(onClick = { showTcpInfoDialog = false }) {
                            androidx.compose.material3.Text("Close")
                        }
                    }
                }
            }
        }
    }

    if (showTrackersInfoDialog) {
        androidx.compose.material3.BasicAlertDialog(onDismissRequest = { showTrackersInfoDialog = false }) {
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
                        text = "Auto-Inject Custom Trackers",
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                    )
                    androidx.compose.material3.Text(
                        text = "Addons often provide magnet links with very few or dead trackers. This feature automatically injects your list of high-speed public trackers into every magnet link before starting the download.\n\n" +
                               "• Pros: Massively speeds up the initial 'Resolving Metadata' phase and finds more peers.\n" +
                               "• Tradeoffs: Slight overhead when resolving large tracker lists.\n\n" +
                               "Interference Note: If you enable DHT (Distributed Hash Table), you might not need custom trackers, but having both is the absolute best for instant streaming.",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        androidx.compose.material3.TextButton(onClick = { showTrackersInfoDialog = false }) {
                            androidx.compose.material3.Text("Close")
                        }
                    }
                }
            }
        }
    }

    if (showCustomTrackersDialog) {
        var draft by remember { mutableStateOf(settings.customTrackers) }
        androidx.compose.material3.BasicAlertDialog(onDismissRequest = { showCustomTrackersDialog = false }) {
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
                        text = "Custom Trackers",
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                    )
                    androidx.compose.material3.Text(
                        text = "Enter a list of tracker URLs (separated by commas or newlines).",
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    androidx.compose.material3.OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 4,
                        maxLines = 10,
                        placeholder = { androidx.compose.material3.Text("udp://tracker.opentrackr.org:1337/announce\nudp://tracker.coppersurfer.tk:6969/announce") }
                    )
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End),
                    ) {
                        androidx.compose.material3.TextButton(onClick = { showCustomTrackersDialog = false }) {
                            androidx.compose.material3.Text("Cancel")
                        }
                        androidx.compose.material3.Button(
                            onClick = {
                                TorrentStreamingRepository.setCustomTrackers(draft.trim())
                                showCustomTrackersDialog = false
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
