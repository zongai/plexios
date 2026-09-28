# Native Media Engine — Known Limitations (post Phase 1–12)

| Area | Status | Mitigation |
|------|--------|------------|
| FFmpeg demux/decode | Not linked by default | AVPlayer + Plex Transcode; enable `NATIVE_FFMPEG` + XCFramework |
| VP9 / OPUS Direct Play | Needs soft decode | Server transcode |
| PiP on Native/Metal | Unsupported | Use AVPlayer backend |
| AirPlay Video on Native | Unsupported | Use AVPlayer backend |
| VobSub full SPU | Structural stub | Burn-in transcode or FFmpeg later |
| PGS | Best-effort RLE | Complex compositions may fail → burn-in |
| DTS / TrueHD audio | Soft path needs FFmpeg | Transcode |
| Native default | **Off** | Settings → experimental toggle |

## Capability matrix (Native Metal path)

| Now Playing | Lock Screen | Remote | Background audio | AirPlay audio | PiP | AirPlay video |
|-------------|-------------|--------|------------------|---------------|-----|---------------|
| Yes | Yes | Yes | Yes | Yes | No | No |
