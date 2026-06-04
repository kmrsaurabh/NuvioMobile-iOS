package com.nuvio.app.features.torrent

import com.nuvio.app.core.storage.ProfileScopedKey
import platform.Foundation.NSUserDefaults

actual object TorrentStreamingSettingsStorage {
    private const val enabledKey = "torrent_enabled"
    private const val cacheSizeMbKey = "torrent_cache_size_mb"
    private const val maxConnectionsKey = "torrent_max_connections"
    private const val downloadSpeedLimitKey = "torrent_download_speed_limit"
    private const val uploadSpeedLimitKey = "torrent_upload_speed_limit"
    private const val enableUploadKey = "torrent_enable_upload"
    private const val enableUpnpKey = "torrent_enable_upnp"
    private const val forceTcpKey = "torrent_force_tcp"
    private const val preferredPortKey = "torrent_preferred_port"
    private const val batterySaverKey = "torrent_battery_saver"

    actual fun loadEnabled(): Boolean? = loadBoolean(enabledKey)

    actual fun saveEnabled(enabled: Boolean) {
        saveBoolean(enabledKey, enabled)
    }

    actual fun loadCacheSizeMb(): Int? = loadInt(cacheSizeMbKey)

    actual fun saveCacheSizeMb(sizeMb: Int) {
        saveInt(cacheSizeMbKey, sizeMb)
    }

    actual fun loadMaxConnections(): Int? = loadInt(maxConnectionsKey)

    actual fun saveMaxConnections(max: Int) {
        saveInt(maxConnectionsKey, max)
    }

    actual fun loadDownloadSpeedLimit(): Int? = loadInt(downloadSpeedLimitKey)

    actual fun saveDownloadSpeedLimit(kbps: Int) {
        saveInt(downloadSpeedLimitKey, kbps)
    }

    actual fun loadUploadSpeedLimit(): Int? = loadInt(uploadSpeedLimitKey)

    actual fun saveUploadSpeedLimit(kbps: Int) {
        saveInt(uploadSpeedLimitKey, kbps)
    }

    actual fun loadEnableUpload(): Boolean? = loadBoolean(enableUploadKey)

    actual fun saveEnableUpload(enable: Boolean) {
        saveBoolean(enableUploadKey, enable)
    }

    actual fun loadEnableUpnp(): Boolean? = loadBoolean(enableUpnpKey)

    actual fun saveEnableUpnp(enable: Boolean) {
        saveBoolean(enableUpnpKey, enable)
    }

    actual fun loadForceTcp(): Boolean? = loadBoolean(forceTcpKey)

    actual fun saveForceTcp(force: Boolean) {
        saveBoolean(forceTcpKey, force)
    }

    actual fun loadPreferredPort(): Int? = loadInt(preferredPortKey)

    actual fun savePreferredPort(port: Int) {
        saveInt(preferredPortKey, port)
    }

    actual fun loadBatterySaver(): Boolean? = loadBoolean(batterySaverKey)

    actual fun saveBatterySaver(enabled: Boolean) {
        saveBoolean(batterySaverKey, enabled)
    }

    private fun loadBoolean(key: String): Boolean? {
        val defaults = NSUserDefaults.standardUserDefaults
        val scopedKey = ProfileScopedKey.of(key)
        return if (defaults.objectForKey(scopedKey) != null) {
            defaults.boolForKey(scopedKey)
        } else {
            null
        }
    }

    private fun saveBoolean(key: String, value: Boolean) {
        NSUserDefaults.standardUserDefaults.setBool(value, forKey = ProfileScopedKey.of(key))
    }

    private fun loadInt(key: String): Int? {
        val defaults = NSUserDefaults.standardUserDefaults
        val scopedKey = ProfileScopedKey.of(key)
        return if (defaults.objectForKey(scopedKey) != null) {
            defaults.integerForKey(scopedKey).toInt()
        } else {
            null
        }
    }

    private fun saveInt(key: String, value: Int) {
        NSUserDefaults.standardUserDefaults.setInteger(value.toLong(), forKey = ProfileScopedKey.of(key))
    }

    private fun loadString(key: String): String? =
        NSUserDefaults.standardUserDefaults.stringForKey(ProfileScopedKey.of(key))

    private fun saveString(key: String, value: String) {
        NSUserDefaults.standardUserDefaults.setObject(value, forKey = ProfileScopedKey.of(key))
    }
}
