#include "PlexFFmpeg.h"

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/dict.h>
#include <stdlib.h>
#include <string.h>

struct PlexFFContext {
    AVFormatContext *fmt;
    char format_name[64];
};

static int media_type_from_av(enum AVMediaType t) {
    switch (t) {
        case AVMEDIA_TYPE_VIDEO: return 1;
        case AVMEDIA_TYPE_AUDIO: return 2;
        case AVMEDIA_TYPE_SUBTITLE: return 3;
        default: return 0;
    }
}

static int64_t ts_to_ms(int64_t ts, AVRational tb) {
    if (ts == AV_NOPTS_VALUE) return -1;
    return av_rescale_q(ts, tb, (AVRational){1, 1000});
}

PlexFFContext *plex_ff_open(const char *url, const char *headers) {
    if (!url) return NULL;
    PlexFFContext *ctx = calloc(1, sizeof(PlexFFContext));
    if (!ctx) return NULL;

    AVDictionary *opts = NULL;
    if (headers && headers[0]) {
        av_dict_set(&opts, "headers", headers, 0);
    }
    av_dict_set(&opts, "user_agent", "PlexiOS-Native/1.0", 0);
    av_dict_set(&opts, "reconnect", "1", 0);
    av_dict_set(&opts, "reconnect_streamed", "1", 0);

    AVFormatContext *fmt = NULL;
    int err = avformat_open_input(&fmt, url, NULL, &opts);
    av_dict_free(&opts);
    if (err < 0) {
        free(ctx);
        return NULL;
    }
    err = avformat_find_stream_info(fmt, NULL);
    if (err < 0) {
        avformat_close_input(&fmt);
        free(ctx);
        return NULL;
    }
    ctx->fmt = fmt;
    if (fmt->iformat && fmt->iformat->name) {
        strncpy(ctx->format_name, fmt->iformat->name, sizeof(ctx->format_name) - 1);
    }
    return ctx;
}

void plex_ff_close(PlexFFContext *ctx) {
    if (!ctx) return;
    if (ctx->fmt) {
        avformat_close_input(&ctx->fmt);
    }
    free(ctx);
}

int plex_ff_stream_count(PlexFFContext *ctx) {
    if (!ctx || !ctx->fmt) return 0;
    return (int)ctx->fmt->nb_streams;
}

int plex_ff_stream_info(PlexFFContext *ctx, int index, PlexFFStreamInfo *out) {
    if (!ctx || !ctx->fmt || !out || index < 0 || index >= (int)ctx->fmt->nb_streams) return -1;
    AVStream *st = ctx->fmt->streams[index];
    AVCodecParameters *p = st->codecpar;
    memset(out, 0, sizeof(*out));
    out->index = index;
    out->media_type = media_type_from_av(p->codec_type);
    const char *name = avcodec_get_name(p->codec_id);
    if (name) strncpy(out->codec_name, name, sizeof(out->codec_name) - 1);
    out->width = p->width;
    out->height = p->height;
    out->sample_rate = p->sample_rate;
    #if LIBAVCODEC_VERSION_MAJOR >= 60
    out->channels = p->ch_layout.nb_channels;
#else
    out->channels = p->channels;
#endif
    out->bitrate = p->bit_rate;
    return 0;
}

int64_t plex_ff_duration_ms(PlexFFContext *ctx) {
    if (!ctx || !ctx->fmt) return -1;
    if (ctx->fmt->duration == AV_NOPTS_VALUE) return -1;
    return ctx->fmt->duration / (AV_TIME_BASE / 1000);
}

const char *plex_ff_format_name(PlexFFContext *ctx) {
    if (!ctx) return NULL;
    return ctx->format_name[0] ? ctx->format_name : NULL;
}

int plex_ff_read(PlexFFContext *ctx, PlexFFPacket *out) {
    if (!ctx || !ctx->fmt || !out) return -1;
    memset(out, 0, sizeof(*out));
    AVPacket *pkt = av_packet_alloc();
    if (!pkt) return -1;
    int err = av_read_frame(ctx->fmt, pkt);
    if (err == AVERROR_EOF) {
        av_packet_free(&pkt);
        return 1;
    }
    if (err < 0) {
        av_packet_free(&pkt);
        return err;
    }
    out->stream_index = pkt->stream_index;
    if (pkt->stream_index >= 0 && pkt->stream_index < (int)ctx->fmt->nb_streams) {
        AVStream *st = ctx->fmt->streams[pkt->stream_index];
        out->media_type = media_type_from_av(st->codecpar->codec_type);
        out->pts_ms = ts_to_ms(pkt->pts, st->time_base);
        out->dts_ms = ts_to_ms(pkt->dts, st->time_base);
        out->duration_ms = ts_to_ms(pkt->duration, st->time_base);
    }
    out->is_keyframe = (pkt->flags & AV_PKT_FLAG_KEY) ? 1 : 0;
    out->size = pkt->size;
    out->data = (uint8_t *)malloc((size_t)pkt->size);
    if (!out->data) {
        av_packet_free(&pkt);
        return -1;
    }
    memcpy(out->data, pkt->data, (size_t)pkt->size);
    av_packet_free(&pkt);
    return 0;
}

void plex_ff_packet_free(PlexFFPacket *pkt) {
    if (!pkt) return;
    free(pkt->data);
    pkt->data = NULL;
    pkt->size = 0;
}

int plex_ff_stream_extradata(PlexFFContext *ctx, int index, uint8_t *buffer, int buffer_size) {
    if (!ctx || !ctx->fmt || index < 0 || index >= (int)ctx->fmt->nb_streams) return -1;
    AVCodecParameters *p = ctx->fmt->streams[index]->codecpar;
    if (!p->extradata || p->extradata_size <= 0) return 0;
    if (!buffer) return p->extradata_size;
    if (buffer_size < p->extradata_size) return -1;
    memcpy(buffer, p->extradata, (size_t)p->extradata_size);
    return p->extradata_size;
}

int plex_ff_seek_ms(PlexFFContext *ctx, int64_t ms) {

    if (!ctx || !ctx->fmt) return -1;
    int64_t ts = ms * (AV_TIME_BASE / 1000);
    int err = av_seek_frame(ctx->fmt, -1, ts, AVSEEK_FLAG_BACKWARD);
    if (err < 0) return err;
    avformat_flush(ctx->fmt);
    return 0;
}
