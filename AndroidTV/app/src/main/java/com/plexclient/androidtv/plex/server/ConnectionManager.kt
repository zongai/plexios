package com.plexclient.androidtv.plex.server

import com.plexclient.androidtv.playback.NetworkClass
import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.model.PlexConnection
import com.plexclient.androidtv.plex.model.PlexServer
import com.plexclient.androidtv.plex.model.ServerContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URI
import java.util.concurrent.TimeUnit

data class RankedConnection(
    val server: PlexServer,
    val connection: PlexConnection,
    val latencyMs: Long,
    val score: Int
)

class ConnectionManager(
    private val api: PlexApiClient,
    private val http: OkHttpClient
) {
    var activeServer: PlexServer? = null
        private set
    var activeConnection: PlexConnection? = null
        private set
    var activeBaseUrl: URI? = null
        private set
    var activeToken: String? = null
        private set
    var rankedCache: List<RankedConnection> = emptyList()
        private set

    val context: ServerContext?
        get() {
            val s = activeServer ?: return null
            val url = activeBaseUrl ?: return null
            val token = activeToken ?: return null
            return ServerContext(url, token, s.machineIdentifier)
        }

    /** Derived from the active connection (Local / Remote / Relay). */
    val networkClass: NetworkClass
        get() {
            val c = activeConnection ?: return NetworkClass.Local
            return when {
                c.relay -> NetworkClass.Relay
                c.local -> NetworkClass.Local
                else -> NetworkClass.Remote
            }
        }

    suspend fun discoverAndRank(authToken: String): List<RankedConnection> = coroutineScope {
        val servers = api.fetchServers(authToken)
        val ranked = servers.flatMap { server ->
            server.connections.map { conn ->
                async(Dispatchers.IO) {
                    val latency = probe(conn.uri, server.accessToken)
                    val score = conn.rankScore + (latency / 10).toInt().coerceAtMost(50)
                    RankedConnection(server, conn, latency, score)
                }
            }
        }.awaitAll().sortedBy { it.score }
        rankedCache = ranked
        ranked
    }

    fun select(ranked: RankedConnection) {
        activeServer = ranked.server
        activeConnection = ranked.connection
        activeBaseUrl = URI(ranked.connection.uri)
        activeToken = ranked.server.accessToken
    }

    fun selectBest(ranked: List<RankedConnection>) {
        ranked.firstOrNull()?.let { select(it) }
    }

    private fun probe(uri: String, token: String): Long {
        val client = http.newBuilder()
            .callTimeout(3, TimeUnit.SECONDS)
            .build()
        val start = System.currentTimeMillis()
        return try {
            val req = Request.Builder()
                .url(uri.trimEnd('/') + "/identity")
                .header("X-Plex-Token", token)
                .get()
                .build()
            client.newCall(req).execute().use {
                if (it.isSuccessful) System.currentTimeMillis() - start else 9999L
            }
        } catch (_: Exception) {
            9999L
        }
    }
}
