package com.plexclient.androidtv.plex.identity

import android.content.Context
import android.os.Build
import android.provider.Settings
import com.plexclient.androidtv.BuildConfig
import okhttp3.Request
import java.util.UUID

/**
 * Stable per-install identity + Plex request headers.
 * Matches multi-platform-contracts.md §1.
 */
class ClientIdentity(context: Context) {
    val clientIdentifier: String
    val product: String = BuildConfig.PLEX_PRODUCT
    val version: String = BuildConfig.VERSION_NAME
    val platform: String = "Android"
    val platformVersion: String = Build.VERSION.RELEASE ?: ""
    val device: String = Build.MODEL ?: "AndroidTV"
    val deviceName: String = Build.MODEL ?: "Android TV"
    val deviceVendor: String = Build.MANUFACTURER ?: "Google"

    init {
        val prefs = context.getSharedPreferences("plex_identity", Context.MODE_PRIVATE)
        clientIdentifier = prefs.getString("client_id", null) ?: run {
            val id = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
                ?.takeIf { it.isNotBlank() && it != "9774d56d682e549c" }
                ?: UUID.randomUUID().toString()
            prefs.edit().putString("client_id", id).apply()
            id
        }
    }

    fun applyTo(builder: Request.Builder, token: String? = null) {
        builder
            .header("X-Plex-Client-Identifier", clientIdentifier)
            .header("X-Plex-Product", product)
            .header("X-Plex-Version", version)
            .header("X-Plex-Platform", platform)
            .header("X-Plex-Platform-Version", platformVersion)
            .header("X-Plex-Device", device)
            .header("X-Plex-Device-Name", deviceName)
            .header("X-Plex-Device-Vendor", deviceVendor)
            .header("Accept", "application/json")
        if (!token.isNullOrBlank()) {
            builder.header("X-Plex-Token", token)
        }
    }
}
