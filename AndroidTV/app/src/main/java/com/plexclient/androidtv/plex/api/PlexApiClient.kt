package com.plexclient.androidtv.plex.api

import com.plexclient.androidtv.plex.identity.ClientIdentity
import com.plexclient.androidtv.plex.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class PlexApiClient(
    private val http: OkHttpClient,
    private val identity: ClientIdentity
) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    suspend fun createPin(): PlexPin = getJson("https://clients.plex.tv/api/v2/pins?strong=false") { root ->
        val o = root.jsonObject
        PlexPin(
            id = o.int("id"),
            code = o.str("code") ?: "",
            expiresIn = o.int("expiresIn"),
            authToken = o.str("authToken")
        )
    }

    suspend fun checkPin(id: Int, code: String): PlexPin =
        getJson("https://clients.plex.tv/api/v2/pins/$id?code=${enc(code)}") { root ->
            val o = root.jsonObject
            PlexPin(
                id = o.int("id"),
                code = o.str("code") ?: code,
                expiresIn = o.int("expiresIn"),
                authToken = o.str("authToken")
            )
        }

    suspend fun fetchServers(authToken: String): List<PlexServer> {
        val url = "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1"
        return getJson(url, authToken) { root ->
            val arr = root.jsonArrayOrNull() ?: return@getJson emptyList()
            arr.mapNotNull { el ->
                val o = el.jsonObject
                val provides = o.str("provides") ?: ""
                if (!provides.contains("server")) return@mapNotNull null
                val connections = o["connections"]?.jsonArray?.map { c ->
                    val co = c.jsonObject
                    PlexConnection(
                        uri = co.str("uri") ?: "",
                        address = co.str("address"),
                        port = co.intOrNull("port"),
                        protocol = co.str("protocol") ?: "http",
                        local = co.bool("local"),
                        relay = co.bool("relay"),
                        ipv6 = co.bool("IPv6")
                    )
                } ?: emptyList()
                PlexServer(
                    name = o.str("name") ?: "Server",
                    machineIdentifier = o.str("clientIdentifier") ?: o.str("machineIdentifier") ?: "",
                    accessToken = o.str("accessToken") ?: authToken,
                    product = o.str("product"),
                    provides = provides,
                    connections = connections
                )
            }
        }
    }

    suspend fun fetchLibrarySections(baseUrl: URI, token: String): List<PlexLibrary> =
        getPms(baseUrl, "library/sections", token) { root ->
            root.mediaContainerArray("Directory").map { o ->
                PlexLibrary(
                    key = o.str("key") ?: "",
                    title = o.str("title") ?: "",
                    type = when (o.str("type")) {
                        "movie" -> PlexLibraryType.Movie
                        "show" -> PlexLibraryType.Show
                        "artist" -> PlexLibraryType.Artist
                        "photo" -> PlexLibraryType.Photo
                        else -> PlexLibraryType.Unknown
                    },
                    agent = o.str("agent"),
                    uuid = o.str("uuid")
                )
            }
        }

    suspend fun fetchHomeHubs(baseUrl: URI, token: String): List<PlexHub> =
        getPms(baseUrl, "hubs", token) { root ->
            root.mediaContainerArray("Hub").map { o ->
                PlexHub(
                    hubKey = o.str("hubKey"),
                    title = o.str("title") ?: "",
                    type = o.str("type"),
                    items = o["Metadata"]?.jsonArray?.map { mapMetadata(it.jsonObject) } ?: emptyList()
                )
            }
        }

    suspend fun fetchLibraryAll(
        sectionKey: String,
        baseUrl: URI,
        token: String,
        start: Int = 0,
        size: Int = 50
    ): List<PlexMetadata> =
        getPms(baseUrl, "library/sections/$sectionKey/all?X-Plex-Container-Start=$start&X-Plex-Container-Size=$size", token) { root ->
            root.mediaContainerArray("Metadata").map { mapMetadata(it) }
        }

    suspend fun fetchMetadata(ratingKey: String, baseUrl: URI, token: String): PlexMetadata =
        getPms(baseUrl, "library/metadata/$ratingKey?includeMarkers=1&includeChildren=1", token) { root ->
            val first = root.mediaContainerArray("Metadata").firstOrNull()
                ?: error("Metadata not found")
            mapMetadata(first)
        }

    suspend fun search(query: String, baseUrl: URI, token: String): List<PlexHub> =
        getPms(baseUrl, "hubs/search?query=${enc(query)}", token) { root ->
            root.mediaContainerArray("Hub").map { o ->
                PlexHub(
                    hubKey = o.str("hubKey"),
                    title = o.str("title") ?: "",
                    type = o.str("type"),
                    items = o["Metadata"]?.jsonArray?.map { mapMetadata(it.jsonObject) } ?: emptyList()
                )
            }
        }

    suspend fun fetchChildren(ratingKey: String, baseUrl: URI, token: String): List<PlexMetadata> =
        getPms(baseUrl, "library/metadata/$ratingKey/children", token) { root ->
            root.mediaContainerArray("Metadata").map { mapMetadata(it) }
        }

    suspend fun fetchRelated(ratingKey: String, baseUrl: URI, token: String): List<PlexHub> =
        getPms(baseUrl, "library/metadata/$ratingKey/related", token) { root ->
            root.mediaContainerArray("Hub").map { o ->
                PlexHub(
                    hubKey = o.str("hubKey"),
                    title = o.str("title") ?: "",
                    type = o.str("type"),
                    items = o["Metadata"]?.jsonArray?.map { mapMetadata(it.jsonObject) } ?: emptyList()
                )
            }
        }

    suspend fun fetchPlaylists(baseUrl: URI, token: String): List<PlexMetadata> =
        getPms(baseUrl, "playlists", token) { root ->
            root.mediaContainerArray("Metadata").map { mapMetadata(it) }
        }

    suspend fun fetchPlaylistItems(ratingKey: String, baseUrl: URI, token: String): List<PlexMetadata> =
        getPms(baseUrl, "playlists/$ratingKey/items", token) { root ->
            root.mediaContainerArray("Metadata").map { mapMetadata(it) }
        }

    suspend fun fetchCollections(baseUrl: URI, token: String): List<PlexMetadata> =
        try {
            getPms(baseUrl, "library/collections", token) { root ->
                root.mediaContainerArray("Metadata").map { mapMetadata(it) }
            }
        } catch (_: Exception) {
            emptyList()
        }

    suspend fun fetchSectionCollections(sectionKey: String, baseUrl: URI, token: String): List<PlexMetadata> =
        try {
            getPms(baseUrl, "library/sections/$sectionKey/collections", token) { root ->
                root.mediaContainerArray("Metadata").map { mapMetadata(it) }
            }
        } catch (_: Exception) {
            emptyList()
        }

    suspend fun fetchCollectionChildren(ratingKey: String, baseUrl: URI, token: String): List<PlexMetadata> =
        try {
            getPms(baseUrl, "library/collections/$ratingKey/children", token) { root ->
                root.mediaContainerArray("Metadata").map { mapMetadata(it) }
            }
        } catch (_: Exception) {
            fetchChildren(ratingKey, baseUrl, token)
        }

    suspend fun fetchFavorites(baseUrl: URI, token: String, start: Int = 0, size: Int = 100): List<PlexMetadata> =
        getPms(baseUrl, "library/all?userRating>=1&X-Plex-Container-Start=$start&X-Plex-Container-Size=$size", token) { root ->
            root.mediaContainerArray("Metadata").map { mapMetadata(it) }
        }

    suspend fun rate(key: String, rating: Int, baseUrl: URI, token: String) {
        val path =
            ":/rate?key=${enc(key)}&identifier=com.plexapp.plugins.library&rating=$rating"
        putPms(baseUrl, path, token)
    }

    // --- helpers ---

    private fun mapMetadata(o: JsonObject): PlexMetadata {
        val media = o["Media"]?.jsonArray?.map { mEl ->
            val m = mEl.jsonObject
            val parts = m["Part"]?.jsonArray?.map { pEl ->
                val p = pEl.jsonObject
                val streams = p["Stream"]?.jsonArray?.map { sEl ->
                    val s = sEl.jsonObject
                    PlexStream(
                        id = s.int("id"),
                        streamType = when (s.int("streamType")) {
                            1 -> PlexStream.StreamType.Video
                            2 -> PlexStream.StreamType.Audio
                            3 -> PlexStream.StreamType.Subtitle
                            else -> PlexStream.StreamType.Unknown
                        },
                        codec = s.str("codec"),
                        language = s.str("language"),
                        languageCode = s.str("languageCode"),
                        title = s.str("title"),
                        displayTitle = s.str("displayTitle"),
                        extendedDisplayTitle = s.str("extendedDisplayTitle"),
                        channels = s.intOrNull("channels"),
                        format = s.str("format"),
                        selected = s.bool("selected")
                    )
                } ?: emptyList()
                PlexPart(
                    id = p.int("id"),
                    key = p.str("key") ?: "",
                    duration = p.longOrNull("duration"),
                    file = p.str("file"),
                    container = p.str("container"),
                    streams = streams
                )
            } ?: emptyList()
            PlexMedia(
                id = m.int("id"),
                duration = m.longOrNull("duration"),
                bitrate = m.intOrNull("bitrate"),
                width = m.intOrNull("width"),
                height = m.intOrNull("height"),
                videoCodec = m.str("videoCodec"),
                audioCodec = m.str("audioCodec"),
                container = m.str("container"),
                videoProfile = m.str("videoProfile"),
                parts = parts
            )
        } ?: emptyList()

        val markers = o.arr("Marker")?.mapNotNull { m ->
            val type = when (m.str("type")?.lowercase()) {
                "intro" -> PlexMarkerType.Intro
                "credits", "credit" -> PlexMarkerType.Credits
                "commercial" -> PlexMarkerType.Commercial
                else -> PlexMarkerType.Unknown
            }
            val start = m.longOrNull("startTimeOffset") ?: return@mapNotNull null
            val end = m.longOrNull("endTimeOffset") ?: return@mapNotNull null
            PlexMarker(
                id = m.int("id"),
                type = type,
                startTimeOffset = start,
                endTimeOffset = end
            )
        } ?: emptyList()

        return PlexMetadata(
            ratingKey = o.str("ratingKey") ?: "",
            key = o.str("key") ?: "",
            type = when (o.str("type")) {
                "movie" -> PlexMetadataType.Movie
                "show" -> PlexMetadataType.Show
                "season" -> PlexMetadataType.Season
                "episode" -> PlexMetadataType.Episode
                "artist" -> PlexMetadataType.Artist
                "album" -> PlexMetadataType.Album
                "track" -> PlexMetadataType.Track
                "playlist" -> PlexMetadataType.Playlist
                "collection" -> PlexMetadataType.Collection
                else -> PlexMetadataType.Unknown
            },
            title = o.str("title") ?: "",
            summary = o.str("summary"),
            year = o.intOrNull("year"),
            thumb = o.str("thumb"),
            art = o.str("art"),
            parentThumb = o.str("parentThumb"),
            grandparentThumb = o.str("grandparentThumb"),
            parentTitle = o.str("parentTitle"),
            grandparentTitle = o.str("grandparentTitle"),
            parentRatingKey = o.str("parentRatingKey"),
            grandparentRatingKey = o.str("grandparentRatingKey"),
            index = o.intOrNull("index"),
            parentIndex = o.intOrNull("parentIndex"),
            duration = o.longOrNull("duration"),
            viewOffset = o.longOrNull("viewOffset"),
            contentRating = o.str("contentRating"),
            studio = o.str("studio"),
            tagline = o.str("tagline"),
            userRating = o.doubleOrNull("userRating"),
            media = media,
            markers = markers
        )
    }

    private suspend fun <T> getJson(
        url: String,
        token: String? = null,
        map: (JsonElement) -> T
    ): T = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url).get().also { identity.applyTo(it, token) }.build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}: $url")
            val body = resp.body?.string() ?: error("Empty body")
            map(json.parseToJsonElement(body))
        }
    }

    private suspend fun <T> getPms(
        baseUrl: URI,
        pathAndQuery: String,
        token: String,
        map: (JsonElement) -> T
    ): T {
        val base = baseUrl.toString().trimEnd('/')
        val path = pathAndQuery.trimStart('/')
        return getJson("$base/$path", token, map)
    }

    private suspend fun putPms(baseUrl: URI, pathAndQuery: String, token: String) =
        withContext(Dispatchers.IO) {
            val base = baseUrl.toString().trimEnd('/')
            val path = pathAndQuery.trimStart('/')
            val url = "$base/$path"
            val empty = ByteArray(0).toRequestBody("application/octet-stream".toMediaTypeOrNull())
            val req = Request.Builder().url(url).put(empty)
                .also { identity.applyTo(it, token) }.build()
            http.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) error("HTTP ${resp.code}: $url")
            }
        }

    private fun enc(s: String) = URLEncoder.encode(s, StandardCharsets.UTF_8)

    private fun JsonElement.jsonArrayOrNull(): JsonArray? =
        if (this is JsonArray) this else null

    private fun JsonElement.mediaContainerArray(key: String): List<JsonObject> {
        val mc = this.jsonObject["MediaContainer"]?.jsonObject ?: return emptyList()
        return mc[key]?.jsonArray?.map { it.jsonObject } ?: emptyList()
    }

    private fun JsonObject.arr(key: String): List<JsonObject>? =
        this[key]?.jsonArray?.mapNotNull { it as? JsonObject } ?: this[key]?.let { el ->
            // single object form
            (el as? JsonObject)?.let { listOf(it) }
        }

    private fun JsonObject.str(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull
    private fun JsonObject.int(key: String): Int = this[key]?.jsonPrimitive?.intOrNull ?: 0
    private fun JsonObject.intOrNull(key: String): Int? = this[key]?.jsonPrimitive?.intOrNull
    private fun JsonObject.longOrNull(key: String): Long? = this[key]?.jsonPrimitive?.longOrNull
    private fun JsonObject.doubleOrNull(key: String): Double? =
        this[key]?.jsonPrimitive?.contentOrNull?.toDoubleOrNull()
    private fun JsonObject.bool(key: String): Boolean = this[key]?.jsonPrimitive?.booleanOrNull ?: false
}
