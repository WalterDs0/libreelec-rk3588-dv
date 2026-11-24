# LibreELEC for Radxa Rock 5T (RK3588) — TV-led Dolby Vision

本仓库基于 **LibreELEC 13 (`master` / Linux `6.19.0` + Kodi `22 Piers`)** 构建，面向 **Radxa Rock 5T (RK3588)**，提供 4K60/HDR、**Standard (TV-led) Dolby Vision**、双轨蓝光原盘播放、HDMI 源码音频直通与多项中文字幕/云盘播放优化（架构参考 [dangerouslaser/libreelec-rpi-dv](https://github.com/dangerouslaser/libreelec-rpi-dv)，部分播放与字幕优化移植自 [flhs0606/LibreELEC-Hades](https://github.com/flhs0606/LibreELEC-Hades)）。

---

## 已实现功能

### 1. 内核与 HDMI 显示/音频链路（Linux `6.19.0`）
- **Dolby Vision DRM/HDMI 信号通路（`rockchip-0188`–`0192`）**：实现通用 DRM Connector `"Dolby Vision"` 属性与 Dolby VSIF 发送、VOP2 YUV 背景修正、Broadcast RGB 默认 Full Range，保证 8-bit RGB 4:4:4 Bit-Exact 无损直通输出。
- **HDMI 音频次时代直通（`rockchip-0193`）**：`dw-hdmi-qp` 支持基于 `rockchip_i2s_tdm` + `IEC958_AES0_NONAUDIO` 的 8 声道 `AUD_HBR` 模式。
- **GPU / Vulkan**：开启 `VULKAN="vulkan-loader"` 与 Mesa `PanVK` 驱动（Mali-G610），供 `pi-dv-engine` Vulkan 着色器与 DMA-BUF 零拷贝导入使用。

### 2. Standard (TV-led) Dolby Vision 播放引擎（`pi-dv-engine` + Kodi `0001`–`0013`）
- 适配 RK3588 线性 **`NV15`** 10-bit 硬件解码帧（`rkvdec` / `v4l2request`）与 DMA-BUF 零拷贝输入。
- 支持 **Profile 5 / Profile 7 / Profile 8.1**，支持 CM v4.0 元数据、裁切流（cropped）、字幕与 GUI 脏区合成进杜比视界输出画面。
- 支持 `ext_mapping_idc` RPU 与重复 pivot 曲线（如 `0,0,1023`），并在 Player Info 信息面板显示输入/处理/输出链路状态。

### 3. 双轨 Dolby Vision Profile 7（蓝光 ISO / M2TS）（Kodi `0014`–`0015`, `0023`–`0027` + `pi-dv-engine 0004`–`0006`）
- 解复用层自动识别并配对蓝光双轨（支持无 PMT `HDMV` 描述符时按 PID `0x1011` + `0x1015` 配对）。
- 采用**双独立解码器架构**（BL/EL 各自走原始码流，`DemuxPacket::elData/elSize/elPts` 独立传递），优先采用 EL 帧携带的 RPU。
- 使用双精度 `elPts` 与 `PAIR_TOLERANCE_US`（2 ms）配对容差，消除时间戳舍入导致的偶发丢帧。

### 4. HDR Vivid 实时转 Dolby Vision Profile 8.1（Kodi `0020`）
- 自动检测 HEVC ITU-T T.35 HDR Vivid SEI，在 `DVDVideoCodecDRMPRIME` 硬件解码出口逐帧将动态亮度元数据转换为标准 Profile 8.1 `AVDOVIMetadata` 输出。
- 可在 **设置 → 播放器 → 视频 → Dolby Vision → HDR Vivid as Dolby Vision** 中开关（默认开启）。

### 5. HDMI 音频源码直通（`appliance.xml` + `simple-card.conf` + Kodi `0021` + Linux `0193`）
- 恢复 Kodi **设置 → 系统 → 音频 → 允许直通** 选项，默认设备修正为 `ALSA:hdmi:CARD=hdmi0,DEV=0`。
- `AESinkALSA` 识别 `sysdefault:CARD=hdmiX` 与 ELD，直通时使用 `hw:` 并配置 `IEC958 Playback Default`（退出直通后自动恢复 PCM 状态，保证 GUI 提示音正常）。
- 已实机验证 AC3 / TrueHD 等源码直通。

### 6. 中文字幕优化与本地 PGS OCR 识别（Kodi `0016`–`0017`, `0019` + `onnxruntime` + `pgs-ocr-model`）
- **中文字幕偏好与优先级（`0016`）**：支持中文简/繁/双语优先选轨。
- **动态字幕偏移（`0017`）**：支持播放时动态调节字幕垂直位置与局部移动。
- **本地中文 PGS 字幕 OCR 与快速切轨（`0019`）**：内置 CPU 版 ONNX Runtime (`1.23.2`) 与 `ppocrv5-mobile-rec-int8.onnx` 模型，后台自动识别中文 PGS 字幕类型（简/繁/双语/特效/强制），支持自动切轨及无 Seek 瞬间切换字幕。

### 7. 云盘蓝光直连播放优化（Kodi `0018`）
- 优化远程/云盘蓝光 ISO 的 UDF 块读取缓存与目录访问，显著降低起播和寻道卡顿。

---

## 构建与升级方式

### 本地/构建机交叉编译
```bash
PROJECT=Rockchip ARCH=aarch64 DEVICE=RK3588 UBOOT_SYSTEM=rock-5t make image
```
同时仓库内提供 GitHub Actions 工作流（`.github/workflows/build-rock5t.yml`），可自动产出 `.img.gz` 与 `.tar`。

### 首次刷机与在线升级
- **首次刷机**：将 `.img.gz` 写入 SD 卡/eMMC 后，建议确认启动分区 `extlinux/extlinux.conf` 中已指定：
  ```
  FDT /rockchip/rk3588-rock-5t.dtb
  ```
- **系统升级**：将生成的 `.tar`（及 `.tar.sha256`）拷贝至 Rock 5T 的 `/storage/.update/` 目录后执行 `reboot` 即可自动完成更新。

---

## 已知问题与待优化项
- 部分重度 Profile 7 FEL 双轨蓝光原盘（如《变形金刚》系列）在特定场景下仍存在绿屏/闪屏现象，正在结合 `pi-dv-engine` 逐帧元数据日志排查修复中。
