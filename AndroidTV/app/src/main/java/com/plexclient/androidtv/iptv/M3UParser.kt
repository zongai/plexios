package com.plexclient.androidtv.iptv

/** EXTM3U parser aligned with iOS / Windows. */
object M3UParser {
    private val attrRegex = Regex("""([A-Za-z0-9_-]+)\s*=\s*"([^"]*)"""")

    fun parse(text: String): M3UParseResult {
        var data = text.replace("\r\n", "\n").replace('\r', '\n')
        if (data.startsWith("\uFEFF")) data = data.substring(1)

        var epgUrl: String? = null
        val entries = mutableListOf<M3UEntry>()
        var pendingName: String? = null
        var pendingAttrs: MutableMap<String, String>? = null

        for (raw in data.split('\n')) {
            var line = raw.trim()
            if (line.isEmpty()) continue
            val upper = line.uppercase()

            if (upper.startsWith("#EXTM3U")) {
                val attrs = parseAttrs(line)
                epgUrl = attrs["url-tvg"] ?: attrs["x-tvg-url"] ?: attrs["tvg-url"]
                continue
            }
            if (upper.startsWith("#EXTINF:")) {
                val body = line.removePrefix("#EXTINF:")
                val (attrs, name) = splitAttrsAndName(body)
                pendingName = name
                pendingAttrs = attrs.toMutableMap()
                continue
            }
            if (line.startsWith("#")) {
                if (pendingName != null && upper.startsWith("#EXTGRP:")) {
                    val g = line.removePrefix("#EXTGRP:").trim()
                    if (g.isNotEmpty()) {
                        pendingAttrs = (pendingAttrs ?: mutableMapOf()).also { it["group-title"] = g }
                    }
                }
                continue
            }
            if (pendingName != null) {
                entries += M3UEntry(
                    name = pendingName!!,
                    tvgId = pendingAttrs?.get("tvg-id"),
                    tvgLogo = pendingAttrs?.get("tvg-logo"),
                    groupTitle = pendingAttrs?.get("group-title"),
                    streamUrl = line
                )
            }
            pendingName = null
            pendingAttrs = null
        }
        return M3UParseResult(epgUrl = epgUrl, entries = entries)
    }

    private fun parseAttrs(line: String): Map<String, String> {
        val map = mutableMapOf<String, String>()
        attrRegex.findAll(line).forEach { m ->
            map[m.groupValues[1].lowercase()] = m.groupValues[2]
        }
        return map
    }

    private fun splitAttrsAndName(body: String): Pair<Map<String, String>, String> {
        var i = 0
        while (i < body.length && body[i] != ' ' && body[i] != ',') i++
        val rest = body.substring(i).trimStart()
        var inQuotes = false
        var lastComma = -1
        for (j in rest.indices) {
            val c = rest[j]
            if (c == '"') inQuotes = !inQuotes
            else if (c == ',' && !inQuotes) lastComma = j
        }
        val attrPart: String
        val name: String
        if (lastComma >= 0) {
            attrPart = rest.substring(0, lastComma)
            name = rest.substring(lastComma + 1).trim()
        } else {
            attrPart = rest
            name = rest
        }
        val attrs = parseAttrs(attrPart)
        val display = name.ifBlank { attrs["tvg-name"] ?: "Channel" }
        return attrs to display
    }
}
