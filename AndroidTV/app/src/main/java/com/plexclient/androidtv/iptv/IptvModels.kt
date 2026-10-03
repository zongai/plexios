package com.plexclient.androidtv.iptv

data class IptvPlaylist(
    val id: String,
    var name: String,
    var url: String,
    var enabled: Boolean = true,
    var lastUpdated: Long? = null,
    var channelCount: Int = 0,
    var epgUrl: String? = null
)

data class IptvChannel(
    val id: String,
    val name: String,
    val logoUrl: String? = null,
    val group: String? = null,
    val tvgId: String? = null,
    val streamUrl: String,
    val playlistId: String
)

data class M3UEntry(
    val name: String,
    val tvgId: String? = null,
    val tvgLogo: String? = null,
    val groupTitle: String? = null,
    val streamUrl: String
)

data class M3UParseResult(
    val epgUrl: String? = null,
    val entries: List<M3UEntry> = emptyList()
)
