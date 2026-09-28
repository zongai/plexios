#ifndef PLEX_FFMPEG_H
#define PLEX_FFMPEG_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PlexFFContext PlexFFContext;

typedef struct PlexFFPacket {
    int stream_index;
    int media_type; /* 0=unknown 1=video 2=audio 3=subtitle */
    uint8_t *data;
    int size;
    int64_t pts_ms;
    int64_t dts_ms;
    int64_t duration_ms;
    int is_keyframe;
} PlexFFPacket;

typedef struct PlexFFStreamInfo {
    int index;
    int media_type;
    char codec_name[64];
    int width;
    int height;
    int sample_rate;
    int channels;
    int64_t bitrate;
} PlexFFStreamInfo;

/// Open media URL (http/https/file). headers may be NULL or "Key: Value\r\nKey2: Value2\r\n".
PlexFFContext *plex_ff_open(const char *url, const char *headers);

void plex_ff_close(PlexFFContext *ctx);

int plex_ff_stream_count(PlexFFContext *ctx);
int plex_ff_stream_info(PlexFFContext *ctx, int index, PlexFFStreamInfo *out);

/// Copies codec extradata (avcC/hvcc/etc). Returns byte count written, or -1.
/// If buffer is NULL, returns required size.
int plex_ff_stream_extradata(PlexFFContext *ctx, int index, uint8_t *buffer, int buffer_size);

int64_t plex_ff_duration_ms(PlexFFContext *ctx);
const char *plex_ff_format_name(PlexFFContext *ctx);

/// Read next packet. Caller must plex_ff_packet_free.
/// Returns 0 on success, 1 on EOF, negative on error.
int plex_ff_read(PlexFFContext *ctx, PlexFFPacket *out);
void plex_ff_packet_free(PlexFFPacket *pkt);

/// Seek to timestamp in milliseconds. Returns 0 on success.
int plex_ff_seek_ms(PlexFFContext *ctx, int64_t ms);

/* ---- Software video decoder (avcodec) ---- */

typedef struct PlexFFVideoDecoder PlexFFVideoDecoder;

typedef struct PlexFFVideoFrame {
    int width;
    int height;
    int64_t pts_ms;
    int is_keyframe;
    /* NV12 contiguous: Y plane size = width*height, UV = width*height/2 */
    uint8_t *nv12;
    int nv12_size;
} PlexFFVideoFrame;

/// codec_name: "h264","hevc","vp9","av1", etc.
PlexFFVideoDecoder *plex_ff_video_open(
    const char *codec_name,
    int width,
    int height,
    const uint8_t *extradata,
    int extradata_size
);

void plex_ff_video_close(PlexFFVideoDecoder *dec);

/// Decode one compressed packet. May produce 0..n frames via repeated calls with same packet / flush.
/// Returns 0 on success (check *out_count), 1 need more data, negative error.
/// Caller frees each frame with plex_ff_video_frame_free.
int plex_ff_video_decode(
    PlexFFVideoDecoder *dec,
    const uint8_t *data,
    int size,
    int64_t pts_ms,
    int is_keyframe,
    PlexFFVideoFrame **out_frames,
    int *out_count
);

void plex_ff_video_frame_free(PlexFFVideoFrame *frame);
void plex_ff_video_flush(PlexFFVideoDecoder *dec);

#ifdef __cplusplus
}
#endif

#endif
