package com.nuvio.app.features.torrent

import com.nuvio.app.features.streams.StreamItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object TorrentStreamingRepository {
    private val _uiState = MutableStateFlow(TorrentStreamingSettings())
    val uiState: StateFlow<TorrentStreamingSettings> = _uiState.asStateFlow()

    private var loaded = false

    fun ensureLoaded() {
        if (loaded) return
        loaded = true
        loadFromDisk()
    }

    fun setEnabled(value: Boolean) {
        ensureLoaded()
        if (_uiState.value.enabled == value) return
        TorrentStreamingSettingsStorage.saveEnabled(value)
        publish(_uiState.value.copy(enabled = value))
    }

    fun setCacheSizeMb(value: Int) {
        ensureLoaded()
        val clamped = value.coerceIn(256, 16384)
        if (_uiState.value.cacheSizeMb == clamped) return
        TorrentStreamingSettingsStorage.saveCacheSizeMb(clamped)
        publish(_uiState.value.copy(cacheSizeMb = clamped))
    }

    fun setMaxConnections(value: Int) {
        ensureLoaded()
        val clamped = value.coerceIn(1, 500)
        if (_uiState.value.maxConnectionsPerTorrent == clamped) return
        TorrentStreamingSettingsStorage.saveMaxConnections(clamped)
        publish(_uiState.value.copy(maxConnectionsPerTorrent = clamped))
    }

    fun setDownloadSpeedLimit(value: Int) {
        ensureLoaded()
        val clamped = value.coerceAtLeast(0)
        if (_uiState.value.downloadSpeedLimitKbps == clamped) return
        TorrentStreamingSettingsStorage.saveDownloadSpeedLimit(clamped)
        publish(_uiState.value.copy(downloadSpeedLimitKbps = clamped))
    }

    fun setUploadSpeedLimit(value: Int) {
        ensureLoaded()
        val clamped = value.coerceAtLeast(0)
        if (_uiState.value.uploadSpeedLimitKbps == clamped) return
        TorrentStreamingSettingsStorage.saveUploadSpeedLimit(clamped)
        publish(_uiState.value.copy(uploadSpeedLimitKbps = clamped))
    }

    fun setEnableUpload(value: Boolean) {
        ensureLoaded()
        if (_uiState.value.enableUpload == value) return
        TorrentStreamingSettingsStorage.saveEnableUpload(value)
        publish(_uiState.value.copy(enableUpload = value))
    }

    fun setEnableUpnp(value: Boolean) {
        ensureLoaded()
        if (_uiState.value.enableUpnp == value) return
        TorrentStreamingSettingsStorage.saveEnableUpnp(value)
        publish(_uiState.value.copy(enableUpnp = value))
    }

    fun setForceTcp(value: Boolean) {
        ensureLoaded()
        if (_uiState.value.forceTcp == value) return
        TorrentStreamingSettingsStorage.saveForceTcp(value)
        publish(_uiState.value.copy(forceTcp = value))
    }

    fun setCustomTrackers(value: String) {
        ensureLoaded()
        if (_uiState.value.customTrackers == value) return
        TorrentStreamingSettingsStorage.saveCustomTrackers(value)
        publish(_uiState.value.copy(customTrackers = value))
    }

    fun setPreferredPort(value: Int) {
        ensureLoaded()
        val clamped = value.coerceIn(0, 65535)
        if (_uiState.value.preferredPort == clamped) return
        TorrentStreamingSettingsStorage.savePreferredPort(clamped)
        publish(_uiState.value.copy(preferredPort = clamped))
    }

    fun canHandleStream(stream: StreamItem): Boolean {
        ensureLoaded()
        val settings = _uiState.value
        return settings.enabled && settings.canStream && stream.isTorrentStream
    }

    private fun loadFromDisk() {
        publish(
            TorrentStreamingSettings(
                enabled = TorrentStreamingSettingsStorage.loadEnabled() ?: true,
                cacheSizeMb = TorrentStreamingSettingsStorage.loadCacheSizeMb() ?: 2048,
                maxConnectionsPerTorrent = TorrentStreamingSettingsStorage.loadMaxConnections() ?: 100,
                downloadSpeedLimitKbps = TorrentStreamingSettingsStorage.loadDownloadSpeedLimit() ?: 0,
                uploadSpeedLimitKbps = TorrentStreamingSettingsStorage.loadUploadSpeedLimit() ?: 0,
                enableUpload = TorrentStreamingSettingsStorage.loadEnableUpload() ?: false,
                enableUpnp = TorrentStreamingSettingsStorage.loadEnableUpnp() ?: false,
                forceTcp = TorrentStreamingSettingsStorage.loadForceTcp() ?: false,
                customTrackers = TorrentStreamingSettingsStorage.loadCustomTrackers() ?: "",
                preferredPort = TorrentStreamingSettingsStorage.loadPreferredPort() ?: 0,
            ),
        )
    }

    fun onProfileChanged() {
        loaded = false
        ensureLoaded()
    }

    fun clearLocalState() {
        loaded = false
        _uiState.value = TorrentStreamingSettings()
    }

    private fun publish(settings: TorrentStreamingSettings) {
        _uiState.value = settings
    }
}
