package com.plexclient.androidtv.iptv

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

class IptvRepository(
    context: Context,
    private val http: OkHttpClient
) {
    private val prefs = context.getSharedPreferences("iptv_store", Context.MODE_PRIVATE)

    fun loadPlaylists(): List<IptvPlaylist> {
        val raw = prefs.getString("playlists", "[]") ?: "[]"
        val arr = JSONArray(raw)
        return buildList {
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                add(
                    IptvPlaylist(
                        id = o.getString("id"),
                        name = o.getString("name"),
                        url = o.getString("url"),
                        enabled = o.optBoolean("enabled", true),
                        lastUpdated = if (o.has("lastUpdated")) o.getLong("lastUpdated") else null,
                        channelCount = o.optInt("channelCount", 0),
                        epgUrl = o.optString("epgUrl").takeIf { it.isNotEmpty() }
                    )
                )
            }
        }
    }

    fun savePlaylists(list: List<IptvPlaylist>) {
        val arr = JSONArray()
        list.forEach { p ->
            arr.put(JSONObject().apply {
                put("id", p.id)
                put("name", p.name)
                put("url", p.url)
                put("enabled", p.enabled)
                put("channelCount", p.channelCount)
                p.lastUpdated?.let { put("lastUpdated", it) }
                p.epgUrl?.let { put("epgUrl", it) }
            })
        }
        prefs.edit().putString("playlists", arr.toString()).apply()
    }

    fun loadChannels(playlistId: String): List<IptvChannel> {
        val raw = prefs.getString("ch_$playlistId", "[]") ?: "[]"
        val arr = JSONArray(raw)
        return buildList {
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                add(
                    IptvChannel(
                        id = o.getString("id"),
                        name = o.getString("name"),
                        logoUrl = o.optString("logoUrl").takeIf { it.isNotEmpty() },
                        group = o.optString("group").takeIf { it.isNotEmpty() },
                        tvgId = o.optString("tvgId").takeIf { it.isNotEmpty() },
                        streamUrl = o.getString("streamUrl"),
                        playlistId = o.getString("playlistId")
                    )
                )
            }
        }
    }

    fun saveChannels(playlistId: String, channels: List<IptvChannel>) {
        val arr = JSONArray()
        channels.forEach { c ->
            arr.put(JSONObject().apply {
                put("id", c.id)
                put("name", c.name)
                c.logoUrl?.let { put("logoUrl", it) }
                c.group?.let { put("group", it) }
                c.tvgId?.let { put("tvgId", it) }
                put("streamUrl", c.streamUrl)
                put("playlistId", c.playlistId)
            })
        }
        prefs.edit().putString("ch_$playlistId", arr.toString()).apply()
    }

    fun allEnabledChannels(): List<IptvChannel> =
        loadPlaylists().filter { it.enabled }.flatMap { loadChannels(it.id) }

    fun addPlaylist(pl: IptvPlaylist) {
        val list = loadPlaylists().toMutableList()
        list.add(pl)
        savePlaylists(list)
    }

    fun deletePlaylist(id: String) {
        savePlaylists(loadPlaylists().filter { it.id != id })
        prefs.edit().remove("ch_$id").apply()
    }

    suspend fun refreshPlaylist(playlist: IptvPlaylist): IptvPlaylist = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(playlist.url)
            .header("User-Agent", "PlexAndroidTV-IPTV/1.0")
            .get().build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            val body = resp.body?.string() ?: error("Empty playlist")
            val parsed = M3UParser.parse(body)
            val channels = parsed.entries.map { e ->
                IptvChannel(
                    id = stableId(playlist.id, e.tvgId, e.name, e.streamUrl),
                    name = e.name,
                    logoUrl = e.tvgLogo,
                    group = e.groupTitle,
                    tvgId = e.tvgId,
                    streamUrl = e.streamUrl,
                    playlistId = playlist.id
                )
            }
            playlist.channelCount = channels.size
            playlist.lastUpdated = System.currentTimeMillis()
            if (!parsed.epgUrl.isNullOrBlank()) playlist.epgUrl = parsed.epgUrl
            saveChannels(playlist.id, channels)
            val all = loadPlaylists().map { if (it.id == playlist.id) playlist else it }
            savePlaylists(all)
            playlist
        }
    }

    companion object {
        fun newId() = UUID.randomUUID().toString()

        private fun stableId(playlistId: String, tvgId: String?, name: String, url: String): String {
            val md = MessageDigest.getInstance("SHA-256")
            val dig = md.digest("$playlistId|$tvgId|$name|$url".toByteArray())
            return dig.joinToString("") { "%02x".format(it) }.take(16)
        }
    }
}
