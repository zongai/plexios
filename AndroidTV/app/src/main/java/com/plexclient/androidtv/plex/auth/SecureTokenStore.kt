package com.plexclient.androidtv.plex.auth

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Token store with EncryptedSharedPreferences when available.
 * Falls back to plain private SharedPreferences if crypto init fails
 * (some devices / profiles throw on MasterKey), so the app still launches.
 */
class SecureTokenStore(context: Context) {
    private val prefs: SharedPreferences = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "plex_secure_tokens",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (e: Exception) {
        Log.e(TAG, "EncryptedSharedPreferences unavailable, using private prefs", e)
        context.getSharedPreferences("plex_tokens_fallback", Context.MODE_PRIVATE)
    }

    var authToken: String?
        get() = try {
            prefs.getString(KEY_TOKEN, null)
        } catch (e: Exception) {
            Log.e(TAG, "read token failed", e)
            null
        }
        set(value) {
            try {
                prefs.edit().apply {
                    if (value.isNullOrBlank()) remove(KEY_TOKEN) else putString(KEY_TOKEN, value)
                }.apply()
            } catch (e: Exception) {
                Log.e(TAG, "write token failed", e)
            }
        }

    fun clear() {
        try {
            prefs.edit().remove(KEY_TOKEN).apply()
        } catch (e: Exception) {
            Log.e(TAG, "clear token failed", e)
        }
    }

    companion object {
        private const val KEY_TOKEN = "auth_token"
        private const val TAG = "SecureTokenStore"
    }
}
