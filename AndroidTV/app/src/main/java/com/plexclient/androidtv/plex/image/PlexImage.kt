package com.plexclient.androidtv.plex.image

import com.plexclient.androidtv.plex.model.ServerContext
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

object PlexImage {
    fun thumb(ctx: ServerContext?, path: String?, width: Int = 300, height: Int = 450): String? {
        if (ctx == null || path.isNullOrBlank()) return null
        val base = ctx.baseUrl.toString().trimEnd('/')
        val url = URLEncoder.encode(path, StandardCharsets.UTF_8)
        val token = URLEncoder.encode(ctx.token, StandardCharsets.UTF_8)
        return "$base/photo/:/transcode?width=$width&height=$height&minSize=1&upscale=1&url=$url&X-Plex-Token=$token"
    }

    fun art(ctx: ServerContext?, path: String?, width: Int = 1280, height: Int = 720): String? =
        thumb(ctx, path, width, height)

    fun direct(ctx: ServerContext?, path: String?): String? {
        if (ctx == null || path.isNullOrBlank()) return null
        val base = ctx.baseUrl.toString().trimEnd('/')
        val p = path.trimStart('/')
        val token = URLEncoder.encode(ctx.token, StandardCharsets.UTF_8)
        return "$base/$p?X-Plex-Token=$token"
    }
}
