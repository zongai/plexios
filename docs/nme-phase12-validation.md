# NME Phase 12 — Performance & Compatibility Validation

**Baseline device:** iPhone 13 (A15)  
**OS target:** iOS 17+  
**Compare against:** Infuse (same files), official Plex iOS (optional)  
**Do not copy Infuse implementation — benchmark behavior only.**

---

## 1. Test environment checklist

| Item | Value / notes |
|------|----------------|
| Device | iPhone 13 |
| iOS version | |
| PMS version | |
| Network | LAN / Wi‑Fi 5GHz preferred |
| Build | unsigned IPA from Actions / local |
| Native Engine setting | Off (control) / On (experiment) |
| FFmpeg linked (`NATIVE_FFMPEG`) | Yes / No |

---

## 2. Media matrix (minimum)

For each row record: **mode** (Direct Play / Direct Stream / Transcode / Native), **success**, **seek**, **subs**, **CPU/GPU/Mem/Energy**, **dropped frames**, **rebuffer**.

| # | Container | Video | Audio | Subtitle | HDR | Notes |
|---|-----------|-------|-------|----------|-----|-------|
| 1 | MP4 | H.264 1080p | AAC | — | — | Baseline AVPlayer |
| 2 | MP4 | H.264 4K | AAC | — | — | |
| 3 | MP4 | HEVC 1080p | AAC | — | — | |
| 4 | MP4 | HEVC 4K | AAC | — | — | |
| 5 | MKV | HEVC 1080p 10-bit | AAC | — | — | |
| 6 | MKV | HEVC | AAC | SRT | — | Soft sub |
| 7 | MKV | HEVC | AAC | ASS | — | |
| 8 | MKV | HEVC | AAC | PGS | — | Bitmap / burn-in |
| 9 | MKV | HEVC | AC3 | — | — | |
| 10 | MKV | HEVC | E-AC3 | — | — | |
| 11 | MKV | HEVC | DTS | — | — | Expect transcode or soft audio |
| 12 | MKV | HEVC | DTS-HD MA | — | — | |
| 13 | MKV | HEVC | TrueHD | — | — | |
| 14 | MKV | H.264 | AAC | — | — | |
| 15 | TS | H.264 | AAC | — | — | |
| 16 | TS | HEVC | AAC | — | — | |
| 17 | WebM | VP9 | OPUS | WEBVTT | — | Transcode or soft |
| 18 | MP4 | HEVC | AAC | — | HDR10 | If available |

---

## 3. Per-run log template

```text
File: 
Device: iPhone 13 / iOS 
Native Engine: On / Off
Backend used: AVPlayer / Native
Decision mode: directPlay / directStream / transcode
Video decoder: VideoToolbox / Software / n/a
Audio decoder: system / software / n/a
Subtitle path: AV legible / text overlay / bitmap / burn-in / none

Startup time to first frame: ___ ms
Seek 0→mid: ___ ms
Seek mid→near end: ___ ms
Dropped frames (approx): 
Rebuffer count: 
CPU avg / peak: 
GPU avg: 
Memory peak: 
Energy (Instruments): Low / Medium / High / Very High
Thermal: Nominal / Fair / Serious

Result: PASS / FAIL
Failure stage: probe / demux / video / audio / subtitle / network
Fallback used: none / AVPlayer / Transcode
Notes:
```

---

## 4. Instruments protocol

1. **Time Profiler** — 10 min continuous playback (1080p HEVC + AAC).  
2. **Metal System Trace** — Native path only; check GPU frame time vs vsync.  
3. **Allocations** — peak live bytes; watch for demux/decode leaks on seek.  
4. **Energy Log** — 10 min same file; compare Native On vs Off.  
5. **Network** — confirm Range requests (not full download) on Direct Play.

### Acceptance (iPhone 13, 1080p HEVC)

| Metric | Target |
|--------|--------|
| Avg CPU (AVPlayer Direct Play) | < 25% |
| Avg CPU (Native VT + Metal) | < 40% (without FFmpeg soft) |
| Dropped frames | < 1% over 10 min |
| Seek to interactive | < 2 s on LAN |
| No unbounded memory growth | after 5 seeks |

*(Soft FFmpeg 1080p VP9 will exceed these — document as experimental.)*

---

## 5. Infuse / Plex client comparison grid

Same file on the same network:

| File | App | Mode | Play | Seek | Audio | Subs | Perf feel |
|------|-----|------|------|------|-------|------|-----------|
| | Infuse | | | | | | |
| | Plex iOS | | | | | | |
| | PlexiOS AVPlayer | | | | | | |
| | PlexiOS Native | | | | | | |

**Rules**

- Record observable behavior only.  
- Do not reverse-engineer or port Infuse code.  
- Gaps vs Infuse (e.g. DTS Direct Play) are expected until FFmpeg soft decode ships.

---

## 6. Functional regression (always)

With **Native Off** (default):

- [ ] Sign-in PIN  
- [ ] Home hubs / library / search  
- [ ] Play H.264 + AAC  
- [ ] Play HEVC (device-dependent)  
- [ ] Subtitles default on + menu switch  
- [ ] Speed + aspect settings  
- [ ] PiP + AirPlay (AVPlayer)  
- [ ] Lock screen controls  
- [ ] Resume position / timeline  
- [ ] Next episode autoplay  

With **Native On** (experimental):

- [ ] Compatible Direct Play attempts Native then falls back cleanly if demux missing  
- [ ] Timeline still reports in Native path  
- [ ] Pause / seek from lock screen  
- [ ] PiP not claimed (UI honest)  

---

## 7. Diagnostics checklist

On failure, capture log lines:

```text
Decision: ...
Router: path=... backend=...
Diagnostics: Container: ... Video: ...
Native engine failed, falling back...
Playback Failed Stage: ...
```

`PlaybackDiagnostics.displayLines` should explain container / codec / path / backend.

---

## 8. Phase 12 exit criteria

- [ ] Matrix §2 exercised on iPhone 13 for rows 1–10 at minimum  
- [ ] Instruments §4 one AVPlayer + one Native (or documented N/A without FFmpeg)  
- [ ] Infuse comparison §5 for at least 3 files  
- [ ] Default Native **Off** regression §6 all pass  
- [ ] Known gaps listed in release notes (VP9 soft, PiP on Metal, VobSub)  

**Phase 12 is validation + documentation, not a new feature gate.** Ship remaining gaps as known limitations until FFmpeg XCFramework and SampleBuffer PiP land.
