# NME Implementation Audit (Phases 1–12)

**Date:** 2026-09-28  
**Scope:** Native Media Engine + integration with existing AVPlayer Plex client

## Task completion matrix

| Phase | Deliverable | Code location | Runtime completeness |
|-------|-------------|---------------|----------------------|
| 1 Architecture | Backend enums, Analyzer, Fallback, Router, Native stub | `Media/MediaEngine/**` | ✅ |
| 2 Demux/Probe | HTTP Range, MP4/TS/MKV sniff, Builtin demux, FFmpeg stub | `Demux/*`, `Probe/*` | ✅ probe / ⚠️ packet demux needs FFmpeg |
| 3 VideoToolbox | H.264/HEVC decoder, capabilities | `Video/VideoToolbox*` | ✅ API ready |
| 4 Metal | Shaders, renderer, SwiftUI host | `Video/Metal*`, `Shaders.metal` | ✅ not wired into PlayerView yet |
| 5 Audio | System + soft stubs, AVAudioEngine | `Audio/*` | ✅ / ⚠️ Opus/DTS need FFmpeg |
| 6 Sync | Clock, buffers, pipeline loop | `Core/MediaClock`, `BufferManager`, `PlaybackPipeline` | ✅ |
| 7 Text subs | SRT/WebVTT/ASS | `Subtitle/Text*` | ✅ |
| 8 Bitmap subs | PGS RLE, VobSub stub | `Subtitle/Bitmap*` | ⚠️ PGS best-effort; VobSub incomplete |
| 9 Soft video | Fallback chain VT→soft→transcode | `SoftwareVideoDecoder`, `VideoDecodeFallbackChain` | ⚠️ soft needs FFmpeg |
| 10 Plex integrate | Settings flag, try Native, timeline, session | `PlaybackEngine`, Settings, Router | ✅ default Off |
| 11 System media | Now Playing, remote route, capability honesty | `NativeSystemMediaBridge` | ✅ PiP/AirPlay video N/A on Metal |
| 12 Validation docs | Matrix, Instruments, Infuse, limitations | `docs/nme-phase12-*` | ✅ |

## Bugs fixed in this audit

1. **Non-exhaustive `VideoCodecID` switches** after adding `vp9`/`av1` — fixed in `VideoToolboxCapabilities` and `VideoFrame.cmVideoCodecType` (would not compile).
2. **NativeMediaBackend consumed first packet** via `nextPacket()` probe before `pipeline.start` — would drop first frame when FFmpeg is linked; now fails closed without FFmpeg and does not pre-read packets when FFmpeg is enabled.

## Remaining issues (not blockers for default AVPlayer)

| Severity | Issue | Notes |
|----------|-------|--------|
| High (Native only) | No FFmpeg XCFramework in repo | Native Direct Play cannot produce frames; always falls back |
| Medium | PlayerView always uses AVPlayer layer | Even if Native played, Metal surface not shown in UI |
| Medium | `presenter: nil` in pipeline configure | Decoded frames not attached to Metal view |
| Low | SystemAudioDecoder complex buffer path | Fragile for real AC3 streams; transcode remains safe path |
| Low | PGS duration hardcoded ~3s | No END duration from stream in all cases |
| Info | Experimental toggle default **false** | Production path unchanged |

## Default product path (must remain green)

Sign-in → library → AVPlayer Direct/Stream/Transcode → timeline → PiP/AirPlay → settings rate/aspect/subs.

Native is opt-in and self-limits without FFmpeg.
