package com.plexclient.androidtv.util

import android.util.Log

/**
 * Central debug logger. Categories mirror iOS LogRouter / Windows AppDebugLog.
 * Always redacts X-Plex-Token in messages.
 */
object AppLog {
    private const val GLOBAL = "PlexATV"

    fun d(area: String, message: String) = Log.d(GLOBAL, "[$area] ${redact(message)}")
    fun i(area: String, message: String) = Log.i(GLOBAL, "[$area] ${redact(message)}")
    fun w(area: String, message: String) = Log.w(GLOBAL, "[$area] ${redact(message)}")
    fun e(area: String, message: String, t: Throwable? = null) {
        if (t != null) Log.e(GLOBAL, "[$area] ${redact(message)}", t)
        else Log.e(GLOBAL, "[$area] ${redact(message)}")
    }

    fun redact(input: String): String =
        input.replace(Regex("""([?&]X-Plex-Token=)[^&\s]+""", RegexOption.IGNORE_CASE), "$1***")
            .replace(Regex("""(X-Plex-Token["']?\s*[:=]\s*["']?)[^"'\s&]+""", RegexOption.IGNORE_CASE), "$1***")
}
