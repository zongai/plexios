# Phase Soft-Decode — App 内软解与回退策略

**状态：规划中（稍后实现）**  
**策略：先试 AVPlayer → 失败再软解 / 服务器转码**

本文档是任务清单与设计约束，**不要求立即编码**。实现前需单独确认依赖选型（FFmpeg vs VLCKit）与 App Store / 授权合规。

---

## 1. 目标

在 **不依赖 PMS 转码**（或转码失败 / 关闭）时，仍能播放 AVPlayer 无法硬解的片源，尤其是：

| 问题编码 | 典型场景 |
|----------|----------|
| **VP9** 视频 | WebM / MKV / YouTube 类源 |
| **OPUS** 音频 | 与 VP9 常一起出现 |
| （可选）部分冷门容器 | 在 AVPlayer 起播失败时兜底 |

用户可感知的路径：

```
决策引擎
  ├─ 原生可播（H.264/HEVC + AAC…）→ AVPlayer Direct Play / Direct Stream
  ├─ 需服务器转码且 PMS 可用 → Universal Transcode（现状）
  └─ 开启「允许软解」且片源匹配
        → 先 AVPlayer 试播（短超时）
        → 失败 → Local Soft Decode
        → 再失败 → 服务器转码（若可用）或明确错误
```

---

## 2. 非目标（本阶段不做）

- [ ] 替换全部播放为自定义播放器（成功路径仍优先 AVPlayer）
- [ ] Dolby Vision / 复杂 HDR 管线
- [ ] 软解路径完整 AirPlay 镜像视频（可先仅音频或禁用）
- [ ] 软解路径系统 PiP（可二期）
- [ ] 从 GPL 源码翻译 / 拷贝 plex-for-kodi 解码逻辑

---

## 3. 回退状态机

```
┌─────────────┐
│  decide()   │
└──────┬──────┘
       ▼
┌──────────────────┐    成功     ┌────────────┐
│ try AVPlayer     │───────────►│  playing   │
│ (timeout T=3–5s) │            └────────────┘
└────────┬─────────┘
         │ 失败 / 黑屏检测 / error
         ▼
┌──────────────────┐  软解关或未集成  ┌─────────────────┐
│ soft decode?     │────────────────►│ server transcode│
└────────┬─────────┘                 └────────┬────────┘
         │ 开且库可用                          │ 失败
         ▼                                     ▼
┌──────────────────┐                    ┌────────────┐
│ FFmpeg/VLC path  │──失败─────────────►│ user error │
└──────────────────┘                    └────────────┘
```

**失败判定（AVPlayer 试播）建议：**

- [ ] `AVPlayerItem.status == .failed`
- [ ] 超时仍 `timeControlStatus == .waitingToPlayAtSpecifiedRate` 且无有效 `rate`/帧
- [ ] （可选）首帧超时：`AVPlayerItem.isPlaybackLikelyToKeepUp` 长时间 false 且 buffer 不增长

---

## 4. 任务清单

### 4.1 调研与选型（先做）

| ID | 任务 | 产出 | 优先级 |
|----|------|------|--------|
| SD-0.1 | 对比 **FFmpeg 自建** vs **VLCKit**（包体、授权、API、维护） | 选型结论写入本文 §5 | P0 |
| SD-0.2 | App Store 与 LGPL/GPL 分发方式（动态链接 / 源码提供声明） | 合规检查表 | P0 |
| SD-0.3 | 真机测：1080p VP9 软解 CPU%、电量、发热基线 | 数字记入 `ios-capabilities.md` | P0 |
| SD-0.4 | 确认 OPUS → PCM 延迟与音频会话冲突（与现有 `AudioSessionCoordinator`） | 风险列表 | P1 |

### 4.2 决策与设置

| ID | 任务 | 产出 | 优先级 |
|----|------|------|--------|
| SD-1.1 | `PlaybackMode` 增加 `localSoftDecode`（或并行 `PlaybackPath` 枚举） | 模型 + 单测 | P0 |
| SD-1.2 | `PlaybackPreferences` / Settings：`allowSoftwareDecode`（默认 **关**） | UI + UserDefaults | P0 |
| SD-1.3 | 决策：VP9/OPUS 在 `allowSoftwareDecode == false` 时仍 **transcode**（保持现状） | 与现逻辑一致 | P0 |
| SD-1.4 | 决策：`allowSoftwareDecode == true` 时标记 `candidateSoftDecode = true`，仍可先试 AVPlayer | Decision 字段 | P0 |
| SD-1.5 | Settings 文案：软解耗电、仅实验性、失败回退转码 | 文案 | P1 |

### 4.3 AVPlayer 试播与失败检测

| ID | 任务 | 产出 | 优先级 |
|----|------|------|--------|
| SD-2.1 | `PlaybackEngine`：`play` 流程拆成 `attemptAVPlayer` / `attemptSoftDecode` / `attemptTranscode` | 引擎重构 | P0 |
| SD-2.2 | 可配置试播超时（默认 4s） | 常量 / Settings | P0 |
| SD-2.3 | Item failed / 超时 → 取消 AVPlayer 资源，进入下一路径 | 无泄漏 | P0 |
| SD-2.4 | 日志：`playback.path=avplayer|soft|transcode` + reason | 可诊断 | P0 |
| SD-2.5 | 播放器 UI 显示当前路径（类似现有 mode 标签） | PlayerView | P1 |

### 4.4 软解播放器核心

| ID | 任务 | 产出 | 优先级 |
|----|------|------|--------|
| SD-3.1 | 引入选定解码依赖（SPM / XCFramework / 脚本编译） | 工程可编译 | P0 |
| SD-3.2 | `SoftDecodePlayer` 协议：`play(url:)` / `pause` / `seek` / `rate` / `stop` | 与 Engine 解耦 | P0 |
| SD-3.3 | 视频：解码 → Metal 或 `MTKView` / `SampleBufferDisplayLayer` | 出画 | P0 |
| SD-3.4 | 音频：解码 → `AVAudioEngine`，与 `AudioSessionCoordinator` 协同 | 出声 | P0 |
| SD-3.5 | A/V 时钟同步（以音频时钟为主） | 无长期音画不同步 | P0 |
| SD-3.6 | Seek（关键帧 + 音频 flush） | 可用 | P0 |
| SD-3.7 | 倍速（0.5x–2x，与现设置对齐） | 与 Settings 一致 | P1 |
| SD-3.8 | 缓冲 / 网络读（直链 Direct Play URL + Token） | 可播远程 part | P0 |
| SD-3.9 | 错误映射到 `PlexError` / 用户可读文案 | 统一错误 | P1 |

### 4.5 字幕（软解路径）

| ID | 任务 | 产出 | 优先级 |
|----|------|------|--------|
| SD-4.1 | WEBVTT / SRT 拉取（`stream.key` 或外挂） | 文本轨 | P0 |
| SD-4.2 | 按时间轴叠字（SwiftUI overlay 或 CoreText） | 可见字幕 | P0 |
| SD-4.3 | PGS 等图像字幕：本阶段 **不做**，回退转码 burn-in | 文档说明 | P0 |

### 4.6 与现有能力的关系

| ID | 任务 | 产出 | 优先级 |
|----|------|------|--------|
| SD-5.1 | Timeline / scrobble：软解路径仍上报 position | 进度不错乱 | P0 |
| SD-5.2 | 锁屏 / RemoteCommand：软解路径接 play/pause/seek | 基础可用 | P1 |
| SD-5.3 | Now Playing 元数据 | 与现一致 | P1 |
| SD-5.4 | PiP / AirPlay：**标明不支持** 或二期 | 设置/UI 提示 | P2 |
| SD-5.5 | 下一集自动播放：软解结束事件接入现有 autoplay | 行为一致 | P1 |

### 4.7 测试与验收

| ID | 任务 | 产出 | 优先级 |
|----|------|------|--------|
| SD-6.1 | 单测：决策在 soft 开关开/关下的 mode | XCTest | P0 |
| SD-6.2 | 样片：VP9+OPUS+WEBVTT 软解可播 | 真机清单 | P0 |
| SD-6.3 | 样片：H.264+AAC 仍走 AVPlayer（不误入软解） | 回归 | P0 |
| SD-6.4 | 软解失败 → 自动转码成功 | 回退验收 | P0 |
| SD-6.5 | 关闭软解时行为与现网一致 | 回归 | P0 |
| SD-6.6 | 性能：1080p VP9 持续 10min 无崩溃、可接受卡顿标准 | 记录阈值 | P1 |

---

## 5. 选型备注（实现前填写）

| 项 | FFmpeg 自建 | VLCKit |
|----|-------------|--------|
| 包体 | 可裁到 VP9/OPUS 相关 demux/decode | 通常更大 |
| 控制力 | 高（时钟、渲染自控） | 中（走 VLC 管线） |
| 集成量 | 大 | 中 |
| 授权 | LGPL 常见需动态库/声明 | 需核对其许可证 |
| 与 AVPlayer 双栈 | 需自绘 UI 层 | 同样双栈 |

**选定：** _（待填）_  
**版本 / 引入方式：** _（待填）_  
**裁剪 codec 列表：** 建议仅 `vp9`, `opus`, `vorbis`, 必要 demux（`webm`, `matroska`, `mp4`）

---

## 6. 建议实现顺序（开工时）

1. SD-0.x 选型与合规  
2. SD-1.x 开关与决策字段（即使软解未就绪，UI 可先灰显）  
3. SD-2.x AVPlayer 试播失败检测（失败后暂时只回退 **transcode**，验证状态机）  
4. SD-3.x 最小软解：本地/远程 VP9 出画+出声  
5. SD-4.x WEBVTT  
6. SD-5.x timeline / remote  
7. SD-6.x 验收  

**里程碑 A：** 状态机完整，软解未接入时失败 → 转码（无行为倒退）  
**里程碑 B：** VP9+OPUS 软解可播  
**里程碑 C：** 字幕 + 上报 + 设置默认项打磨  

---

## 7. 风险

- 软解 1080p 发热导致系统降频、卡顿  
- 双播放器栈（AVPlayer + Soft）增加崩溃面与测试矩阵  
- 授权与审核被拒  
- 外挂字幕时间轴与 seek 不同步  
- Token 直链与重定向、证书（plex.direct）在软解 HTTP 栈需单独处理  

---

## 8. 与现有文档的关系

- `plex-playback.md`：补充 `localSoftDecode` 模式与回退顺序  
- `ios-capabilities.md`：明确 VP9/OPUS **非** AVPlayer 能力；软解为可选扩展  
- `implementation-plan.md`：增加 Phase Soft-Decode 引用本文件  

---

## 9. 验收标准（全部完成后）

- [ ] 默认设置下行为与当前版本一致（VP9 → 服务器转码）  
- [ ] 开启软解后，VP9+OPUS 在 **无转码** 环境下可播放  
- [ ] AVPlayer 可播源不错误落入软解  
- [ ] 软解失败自动转码或给出明确错误  
- [ ] 进度上报、暂停/seek/倍速基本可用  
- [ ] 文档与 Settings 说明耗电与限制  

**开始实现前请回复：执行 Soft-Decode 里程碑 A / B / C 或指定任务 ID。**
