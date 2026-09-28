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

#ifdef __cplusplus
}
#endif

#endif
