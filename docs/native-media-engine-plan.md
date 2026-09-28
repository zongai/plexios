# Native Media Engine — 完整任务书与实施计划

**状态：Phase 1 架构落地中；默认播放路径仍为 AVPlayer**  
**范围：仅 iOS / iPadOS（基准设备 iPhone 13）**  
**非目标：Windows / Android / tvOS / 跨平台 IPlayerEngine 抽象**

---

## 核心原则

> **AVPlayer 是 iOS 系统播放器能力，不是整个 Plex 播放器。**  
> **FFmpeg：Demux / Probe / 必要软解；VideoToolbox：优先硬解；Metal：渲染；独立 Audio/Subtitle 管线。**  
> **选择顺序：硬件解码 → 软件解码 → AVPlayer → Plex Transcode（按错误类型调整，禁止无限重试）。**

---

## 目标架构

```
Plex → Playback Decision → {
  AVPlayer          // HLS / Transcode / 原生兼容
  Native Media Engine // MKV/TS/WebM、复杂音轨字幕、自定义 Direct Play
  Plex Transcode    // 本地能力不足时
}
```

### AVPlayer 继续负责

PiP、AirPlay、Now Playing、系统远程控制、HLS、Plex Transcode 输出。

### Native Engine 负责

MKV / TS / M2TS / AVI / WebM 等；独立音轨/字幕；Metal 出画；与 PlaybackSession 同步。

---

## 模块布局（仓库）

```
Media/MediaEngine/
├── Core/           MediaEngine, Pipeline, State, Clock, Buffer, Seek
├── Probe/          MediaProbe, MediaInfo, track infos
├── Demux/          Demuxer, FFmpegDemuxer (Phase 2+), Packet
├── Video/          VideoToolbox / Software decoder, Metal renderer
├── Audio/          System + software audio, renderer
├── Subtitle/       Text / bitmap, overlay renderer
├── Compatibility/  Capabilities, Analyzer, FallbackPolicy
└── Integration/    AVPlayerBackend, NativeMediaBackend, PlayerEngineRouter
```

---

## 实施阶段（验收门禁）

| Phase | 内容 | 默认路径是否变更 |
|-------|------|------------------|
| **1** | PlayerEngine 协议、AVPlayerBackend、Native 骨架、Analyzer、FallbackPolicy | **否** |
| **2** | FFmpeg Demux + HTTP Range + Probe（MKV/MP4/TS/M2TS） | 否（仅探测） |
| **3** | VideoToolbox H.264/HEVC | 实验开关可选 |
| **4** | Metal：CVPixelBuffer → 屏幕（禁止 UIImage 路径） | 实验开关 |
| **5** | Audio：AAC/AC3/E-AC3/MP3/FLAC + 软解 PCM | 实验开关 |
| **6** | MediaClock、Buffer、PTS/DTS、Seek 同步 | 实验开关 |
| **7** | 字幕 SRT/WebVTT/ASS/SSA | 实验开关 |
| **8** | PGS / VobSub | 实验开关 |
| **9** | FFmpeg 视频软解 fallback | 实验开关 |
| **10** | Plex Direct Play/Stream/Transcode + Session 完整接入 | 策略化路由 |
| **11** | PiP / AirPlay / Now Playing 适配层 | 按能力 |
| **12** | iPhone 13 真机 + Instruments + Infuse 对照 | — |

---

## Fallback 策略

```
Native Hardware → Native Software → AVPlayer → Plex Transcode
```

兼容性判断仅为预测；运行时失败必须降级且有次数上限。

---

## 与现有代码关系

- 现有 `PlaybackEngine` 保持 UI / Session / Remote 门面。
- Phase 1 引入 `PlayerEngineRouter` + `PlaybackBackend`；默认仍委托现有 AVPlayer 逻辑。
- 不删除、不削弱当前已可播路径。
- 软解规划见 `docs/soft-decode-plan.md`（被本任务书吸收并扩展）。

---

## 最终验收（摘要）

1. AVPlayer 不再是唯一后端  
2. iPhone 13 上 H.264/HEVC 优先 VideoToolbox  
3. MKV/TS 经 FFmpeg Demux  
4. 帧路径：VT → CVPixelBuffer → Metal（非 UIImage）  
5. 音视频字幕独立  
6. Direct Play / Stream / Transcode 均可用  
7. 失败可解释（Diagnostics）并自动 fallback  
8. Session / Watch State 同步  
9. 仅 iOS/iPadOS；对照 Infuse 仅作 benchmark，不复制实现  

**当前交付：Phase 1 骨架（见 `Media/MediaEngine/`）。**
