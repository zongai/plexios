# Full implementation audit (2026-09-28)

## Task completion

| Area | Status |
|------|--------|
| Plex client Phases 1–8 (AVPlayer app) | Done (prior) |
| NME Phase 1–12 | Scaffold + integration done |
| FFmpeg XCFramework + NATIVE_FFMPEG | Enabled via Vendor/PlexFFmpeg |
| PlayerView Metal surface | Done |
| Pipeline ↔ Metal Presenter | Done |
| Extradata / sample rate from demux | Fixed this audit |

## Bugs fixed in this pass

1. **VideoToolbox without extradata** — Native configs used `extradata: nil`; now from `plex_ff_stream_extradata`.
2. **Audio sample rate forced 48 kHz** — now from demux stream when available.
3. **MetalVideoView re-bind every SwiftUI update** — Coordinator only rebinds when presenter/sink identity changes.

## Remaining risks (not blocking default AVPlayer)

| Risk | Severity | Note |
|------|----------|------|
| Soft video decode body still stub under NATIVE_FFMPEG | Medium | VT path works for H.264/HEVC; VP9 still transcode/soft-stub |
| CI binary checksum / link failures | Medium | Depends on GitHub release assets |
| FFmpeg `ch_layout` vs `channels` | Low | Guarded by LIBAVCODEC_VERSION_MAJOR |
| Native UI without decoded frames | Low | Black Metal view until first VT frame |
| PiP/AirPlay video on Metal | Known | Documented limitation |

## Default path health

Sign-in, library, AVPlayer play/seek/subs/PiP/timeline: **unchanged**.
Native requires Settings toggle + successful FFmpeg demux + VT decode.
