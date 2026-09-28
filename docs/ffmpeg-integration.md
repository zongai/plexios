# FFmpeg Integration (NME Phase 2+)

## Current state

| Capability | Status |
|------------|--------|
| HTTP Range data source | **Implemented** (`HTTPRangeDataSource`) |
| MP4/MOV box probe | **Implemented** (pure Swift) |
| MPEG-TS / M2TS sniff | **Implemented** |
| MKV/WebM EBML sniff | **Implemented** |
| Full demux packets | Requires `NATIVE_FFMPEG` + XCFramework |
| FFmpeg `avformat` demux | Stub (`FFmpegDemuxer`) |

Without FFmpeg linked, `DemuxerFactory.make()` returns `BuiltinContainerDemuxer` (probe-only).

## Enabling full FFmpeg

1. Build a static XCFramework (ios-arm64 + simulator) with at least:

   ```text
   libavformat, libavcodec, libavutil, libswresample
   ```

   Suggested configure (minimal, LGPL):

   ```bash
   # Example outline — run on macOS with gas-preprocessor / clang iOS SDKs
   ./configure \
     --enable-cross-compile \
     --arch=arm64 \
     --target-os=darwin \
     --disable-programs --disable-doc \
     --enable-avformat --enable-avcodec --enable-avutil \
     --enable-demuxer=matroska,mov,mpegts,mpegtsraw,avi,flv,asf \
     --enable-parser=h264,hevc,aac,ac3 \
     --enable-decoder=h264,hevc,aac,ac3,eac3,flac,opus,mp3 \
     --disable-debug --enable-optimizations
   ```

2. Produce `FFmpegSupport.xcframework` and a thin C shim:

   - `ffmpeg_open(url, headers)`
   - `ffmpeg_read_packet(...)`
   - `ffmpeg_seek(ms)`
   - `ffmpeg_close()`

   Prefer custom `AVIOContext` that calls into `HTTPRangeDataSource` for Plex tokenized URLs.

3. Xcode / XcodeGen:

   ```yaml
   settings:
     SWIFT_ACTIVE_COMPILATION_CONDITIONS: NATIVE_FFMPEG
   dependencies:
     - framework: Vendor/FFmpegSupport.xcframework
   ```

4. Implement bodies under `#if NATIVE_FFMPEG` in `FFmpegDemuxer.swift`.

## License

Use **LGPL** builds and dynamic linking where required; keep GPL flags off unless legal review approves. Document version and configure line in release notes.

## CI

Unsigned IPA workflow does **not** build FFmpeg by default (time + binary size). Optional job: `ffmpeg-ios.yml` when Vendor framework is present.


## Phase 9 — Video soft decode

When `NATIVE_FFMPEG` is enabled, implement in `FFmpegSupport`:

```c
void *ffmpeg_video_open(const char *codec, int w, int h, const uint8_t *extradata, int extra_size);
int ffmpeg_video_decode(void *ctx, const uint8_t *data, int size, int64_t pts,
                        uint8_t **y, int *y_stride, uint8_t **uv, int *uv_stride, int *out_w, int *out_h);
void ffmpeg_video_close(void *ctx);
```

Swift `SoftwareVideoDecoder` maps output to NV12 `CVPixelBuffer` via `makeNV12PixelBuffer`.
Without the framework, setup throws and PlaybackFallbackPolicy escalates to **Plex Transcode**.
