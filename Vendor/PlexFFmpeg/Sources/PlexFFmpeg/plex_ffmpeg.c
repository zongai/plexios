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

/* ========== Software video decoder ========== */

#include <libswscale/swscale.h>

struct PlexFFVideoDecoder {
    AVCodecContext *codec_ctx;
    AVFrame *frame;
    AVPacket *packet;
    struct SwsContext *sws;
    int width;
    int height;
};

static enum AVCodecID codec_id_from_name(const char *name) {
    if (!name) return AV_CODEC_ID_NONE;
    if (!strcmp(name, "h264") || !strcmp(name, "avc")) return AV_CODEC_ID_H264;
    if (!strcmp(name, "hevc") || !strcmp(name, "h265")) return AV_CODEC_ID_HEVC;
    if (!strcmp(name, "vp9")) return AV_CODEC_ID_VP9;
    if (!strcmp(name, "av1")) return AV_CODEC_ID_AV1;
    if (!strcmp(name, "mpeg2video") || !strcmp(name, "mpeg2")) return AV_CODEC_ID_MPEG2VIDEO;
    if (!strcmp(name, "mpeg4")) return AV_CODEC_ID_MPEG4;
    const AVCodec *c = avcodec_find_decoder_by_name(name);
    return c ? c->id : AV_CODEC_ID_NONE;
}

PlexFFVideoDecoder *plex_ff_video_open(
    const char *codec_name,
    int width,
    int height,
    const uint8_t *extradata,
    int extradata_size
) {
    enum AVCodecID id = codec_id_from_name(codec_name);
    if (id == AV_CODEC_ID_NONE) return NULL;

    const AVCodec *codec = avcodec_find_decoder(id);
    if (!codec) return NULL;

    PlexFFVideoDecoder *dec = calloc(1, sizeof(*dec));
    if (!dec) return NULL;

    dec->codec_ctx = avcodec_alloc_context3(codec);
    dec->frame = av_frame_alloc();
    dec->packet = av_packet_alloc();
    if (!dec->codec_ctx || !dec->frame || !dec->packet) {
        plex_ff_video_close(dec);
        return NULL;
    }

    if (width > 0) dec->codec_ctx->width = width;
    if (height > 0) dec->codec_ctx->height = height;
    dec->width = width;
    dec->height = height;

    if (extradata && extradata_size > 0) {
        dec->codec_ctx->extradata = av_mallocz((size_t)extradata_size + AV_INPUT_BUFFER_PADDING_SIZE);
        if (!dec->codec_ctx->extradata) {
            plex_ff_video_close(dec);
            return NULL;
        }
        memcpy(dec->codec_ctx->extradata, extradata, (size_t)extradata_size);
        dec->codec_ctx->extradata_size = extradata_size;
    }

    /* Prefer single-thread for predictable latency on mobile soft path */
    dec->codec_ctx->thread_count = 2;
    dec->codec_ctx->thread_type = FF_THREAD_FRAME;

    if (avcodec_open2(dec->codec_ctx, codec, NULL) < 0) {
        plex_ff_video_close(dec);
        return NULL;
    }
    return dec;
}

void plex_ff_video_close(PlexFFVideoDecoder *dec) {
    if (!dec) return;
    if (dec->sws) {
        sws_freeContext(dec->sws);
        dec->sws = NULL;
    }
    if (dec->packet) av_packet_free(&dec->packet);
    if (dec->frame) av_frame_free(&dec->frame);
    if (dec->codec_ctx) {
        avcodec_free_context(&dec->codec_ctx);
    }
    free(dec);
}

static PlexFFVideoFrame *frame_to_nv12(PlexFFVideoDecoder *dec, AVFrame *src, int64_t pts_ms) {
    int w = src->width;
    int h = src->height;
    if (w <= 0 || h <= 0) return NULL;

    enum AVPixelFormat dst_fmt = AV_PIX_FMT_NV12;
    dec->sws = sws_getCachedContext(
        dec->sws,
        w, h, (enum AVPixelFormat)src->format,
        w, h, dst_fmt,
        SWS_BILINEAR, NULL, NULL, NULL
    );
    if (!dec->sws) return NULL;

    int y_size = w * h;
    int nv_size = y_size + y_size / 2;
    uint8_t *nv12 = (uint8_t *)av_malloc((size_t)nv_size);
    if (!nv12) return NULL;

    uint8_t *dst_data[4] = { nv12, nv12 + y_size, NULL, NULL };
    int dst_linesize[4] = { w, w, 0, 0 };

    sws_scale(dec->sws, (const uint8_t * const *)src->data, src->linesize, 0, h, dst_data, dst_linesize);

    PlexFFVideoFrame *out = calloc(1, sizeof(*out));
    if (!out) {
        av_free(nv12);
        return NULL;
    }
    out->width = w;
    out->height = h;
    out->pts_ms = pts_ms;
    out->is_keyframe = src->flags & AV_FRAME_FLAG_KEY ? 1 : 0;
    out->nv12 = nv12;
    out->nv12_size = nv_size;
    return out;
}

int plex_ff_video_decode(
    PlexFFVideoDecoder *dec,
    const uint8_t *data,
    int size,
    int64_t pts_ms,
    int is_keyframe,
    PlexFFVideoFrame **out_frames,
    int *out_count
) {
    if (!dec || !out_frames || !out_count) return -1;
    *out_frames = NULL;
    *out_count = 0;

    if (data && size > 0) {
        av_packet_unref(dec->packet);
        if (av_new_packet(dec->packet, size) < 0) return -1;
        memcpy(dec->packet->data, data, (size_t)size);
        if (pts_ms >= 0) {
            dec->packet->pts = pts_ms;
            dec->packet->dts = pts_ms;
        }
        if (is_keyframe) dec->packet->flags |= AV_PKT_FLAG_KEY;

        int send = avcodec_send_packet(dec->codec_ctx, dec->packet);
        if (send == AVERROR(EAGAIN)) {
            /* drain then retry once */
        } else if (send < 0 && send != AVERROR_EOF) {
            return send;
        }
    } else {
        /* flush */
        avcodec_send_packet(dec->codec_ctx, NULL);
    }

    /* Collect up to 8 frames */
    PlexFFVideoFrame *frames[8];
    int count = 0;
    while (count < 8) {
        int rec = avcodec_receive_frame(dec->codec_ctx, dec->frame);
        if (rec == AVERROR(EAGAIN) || rec == AVERROR_EOF) break;
        if (rec < 0) return rec;

        int64_t pts = pts_ms;
        if (dec->frame->pts != AV_NOPTS_VALUE) {
            pts = dec->frame->pts; /* already ms-ish if we set packet pts in ms */
        }
        PlexFFVideoFrame *vf = frame_to_nv12(dec, dec->frame, pts);
        if (vf) {
            frames[count++] = vf;
        }
        av_frame_unref(dec->frame);
    }

    if (count == 0) return 1;
    PlexFFVideoFrame *arr = calloc((size_t)count, sizeof(PlexFFVideoFrame));
    if (!arr) {
        for (int i = 0; i < count; i++) plex_ff_video_frame_free(frames[i]);
        return -1;
    }
    /* Store as contiguous array of structs owning nv12 pointers */
    for (int i = 0; i < count; i++) {
        arr[i] = *frames[i];
        free(frames[i]); /* free shell, keep nv12 ownership in arr[i] */
    }
    *out_frames = arr;
    *out_count = count;
    return 0;
}

void plex_ff_video_frame_free(PlexFFVideoFrame *frame) {
    if (!frame) return;
    if (frame->nv12) {
        av_free(frame->nv12);
        frame->nv12 = NULL;
    }
    /* When freeing single heap frame from intermediate; array free is separate */
}

void plex_ff_video_flush(PlexFFVideoDecoder *dec) {
    if (!dec || !dec->codec_ctx) return;
    avcodec_flush_buffers(dec->codec_ctx);
}
