package com.plexclient.androidtv.di

import android.content.Context
import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.auth.AuthRepository
import com.plexclient.androidtv.plex.auth.SecureTokenStore
import com.plexclient.androidtv.plex.identity.ClientIdentity
import com.plexclient.androidtv.plex.server.ConnectionManager
import com.plexclient.androidtv.playback.PlaybackDecisionEngine
import com.plexclient.androidtv.playback.PlaybackPreferences
import com.plexclient.androidtv.playback.PlaybackUrlBuilder
import com.plexclient.androidtv.playback.TimelineReporter
import com.plexclient.androidtv.iptv.IptvRepository
import com.plexclient.androidtv.settings.AppSettings
import okhttp3.OkHttpClient
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/** Manual DI container — mirrors Windows App.Services / iOS environment objects. */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext
    val identity = ClientIdentity(appContext)
    val tokenStore = SecureTokenStore(appContext)
    val settings = AppSettings(appContext)

    val httpClient: OkHttpClient = buildTrustAllClient()
    val iptvRepository: IptvRepository = IptvRepository(appContext, httpClient)

    val api = PlexApiClient(httpClient, identity)
    val auth = AuthRepository(api, tokenStore, identity)
    val connections = ConnectionManager(api, httpClient)
    val urlBuilder = PlaybackUrlBuilder(identity)
    val timeline = TimelineReporter(httpClient, identity)

    /** Rebuilds engine so Settings changes (bitrate / autoplay-related prefs) apply. */
    fun decisionEngine(): PlaybackDecisionEngine =
        PlaybackDecisionEngine(
            prefs = PlaybackPreferences(
                autoPlayNextEpisode = settings.autoPlayNextEpisode,
                subtitlesEnabled = settings.subtitlesEnabled,
                preferredAudioLanguages = listOfNotNull(settings.preferredAudioLanguage),
                preferredSubtitleLanguages = listOfNotNull(settings.preferredSubtitleLanguage),
                maxRemoteBitrate = settings.maxRemoteBitrate
            )
        )

    private fun buildTrustAllClient(): OkHttpClient {
        val trustAll = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val ssl = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf<TrustManager>(trustAll), SecureRandom())
        }
        return OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .sslSocketFactory(ssl.socketFactory, trustAll)
            .hostnameVerifier { _, _ -> true }
            .build()
    }
}
