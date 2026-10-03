package com.plexclient.androidtv.playback

import com.plexclient.androidtv.plex.identity.ClientIdentity
import com.plexclient.androidtv.plex.model.ServerContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.atomic.AtomicLong

/** Rate-limited PMS `:/timeline` reporter. Failures never stop playback. */
class TimelineReporter(
    private val http: OkHttpClient,
    private val identity: ClientIdentity
) {
    private val lastReportMs = AtomicLong(0)
    private val minIntervalMs = 10_000L
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun report(
        context: ServerContext,
        ratingKey: String,
        positionMs: Long,
        durationMs: Long,
        state: String
    ) {
        val now = System.currentTimeMillis()
        if (state == "playing" || state == "buffering") {
            if (now - lastReportMs.get() < minIntervalMs) return
        }
        lastReportMs.set(now)
        scope.launch {
            try {
                val path = buildString {
                    append(":/timeline?ratingKey=").append(ratingKey)
                    append("&key=").append(
                        java.net.URLEncoder.encode("/library/metadata/$ratingKey", Charsets.UTF_8)
                    )
                    append("&state=").append(state)
                    append("&time=").append(positionMs)
                    append("&duration=").append(durationMs)
                    append("&X-Plex-Token=").append(
                        java.net.URLEncoder.encode(context.token, Charsets.UTF_8)
                    )
                    append("&X-Plex-Client-Identifier=").append(identity.clientIdentifier)
                    append("&X-Plex-Product=").append(
                        java.net.URLEncoder.encode(identity.product, Charsets.UTF_8)
                    )
                    append("&X-Plex-Platform=").append(identity.platform)
                }
                val url = context.baseUrl.toString().trimEnd('/') + "/" + path
                val req = Request.Builder()
                    .url(url)
                    .post(ByteArray(0).toRequestBody(null))
                    .also { identity.applyTo(it, context.token) }
                    .build()
                http.newCall(req).execute().close()
            } catch (_: Exception) {
                // swallow
            }
        }
    }
}
