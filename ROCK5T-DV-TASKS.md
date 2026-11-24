# RK3588 / Rock 5T Dolby Vision 待办与问题排查任务单

最后更新：2026-11-24（基线提交：`44c813e`）

---

## 任务 1：修复长期存在的 FD 泄漏问题（高优先级）— ✅ 已完成并实机验证

### 现象
运行/播放期间进程文件描述符（FD）持续增长，实机复现 15 分钟内泄漏 **2,359 个 `anon_inode:sync_file`**（总 FD 达 2,416），并诱发播放卡顿与耗尽风险（`EMFILE`）。

### 已定位并修复的代码级根因
1. **高频泄漏：`CDVTunnelDRMPRIME` 的 `m_overlayFence` / `frame.overlay_fd`（`0028` + `pi-dv-engine 0007`）**
   - `CDVTunnelDRMPRIME::DrawOverlay()` 在 `areas.empty()` 分支未关闭并重置 `m_overlayFence`。
   - `CDVTunnelDRMPRIME::Render()` 未判断 `frame.overlay != nullptr`，无字幕/OSD 时仍每帧 `dup(m_overlayFence)` 写入 `frame.overlay_fd`。
   - `pi_engine.c:3130` 在 `f->overlay == NULL` 时将 `drawn_fd` 置为 `-1`，导致传入的 `f->overlay_fd` 从不被 `close()`，以 24–60 个/秒的速率泄漏 `anon_inode:sync_file`。
2. **低频边界泄漏：`CDRMAtomic::m_videoInFenceFd`（`0028`）**
   - `CDRMAtomic::DestroyDrm()` 未关闭残留的 `m_videoInFenceFd`。

### 修复与实机验证 Checklist
- [x] 在 `CDVTunnelDRMPRIME::DrawOverlay()` 的 `areas.empty()` 分支关闭并重置 `m_overlayFence = -1`（`0028-fix-dv-overlay-fence-and-drm-fd-leaks.patch`）
- [x] 在 `CDVTunnelDRMPRIME::Render()` 仅当 `frame.overlay != nullptr && m_overlayFence >= 0` 时调用 `dup(m_overlayFence)`（`0028`）
- [x] 在 `pi_engine.c` 的 `pi_render()` 入口当 `f->overlay == NULL` 时也强制关闭传入的 `f->overlay_fd`（`0007-fix-overlay-fd-leak.patch`）
- [x] 在 `CDRMAtomic::DestroyDrm()` 关闭残留的 `m_videoInFenceFd`（`0028`）
- [x] 在构建机（`192.168.1.180`）完成 `make image` 编译验证，并在 Rock 5T 实机播放《变形金刚 2》（双层 P7 FEL + TrueHD 8ch HDMI 直通）复测：总 FD 稳定在 **122**（`anon_inode:sync_file` 仅 **6–7** 个，+5 秒采样零增长），且 TrueHD 直通不再卡顿

---

## 任务 2：修复《变形金刚》系列双层 DV ISO 特定帧瞬间闪绿问题（高优先级）

### 现象与最新实机定位进展（已锁定根因方向）
- 双轨 Profile 7（蓝光 ISO）已可正常点亮杜比视界并播放，日志确认双轨 EL/BL 配对 100% 正常（`371/371` 零丢包、零失配）。
- 播放《变形金刚 2》2.5 秒时触发 `CDVTunnelDRMPRIME: MMR magnitudes too large for the split's frame bound: checked per sample`（命中 `p1_chroma.frag` 的 `SPLIT_GUARD` / `split_guarded()` 逐采样 64-bit 模拟路径）。
- **对照测试实证**：在播放视频设置中将 **Chroma MMR** 从 `Exact` 切为 **`Float`** 后，**瞬间闪绿完全消失**（且开启 HDMI TrueHD 直通流畅不卡顿）。
- **结论**：瞬间闪绿 100% 源于 `pi-dv-engine` 的 `Exact` / `SPLIT_GUARD`（`mmr_split_mag` / `mmr_exact64` / `uaddCarry` / `umulExtended`）在 Mali-G610 PanVK 上的边界/编译器问题。

### 后续根治 Checklist
- [x] 对照测试：将 **Chroma MMR** 切为 `Float`，确认《变形金刚 2》闪绿消失
- [ ] 深入排查 `p1_chroma.frag` 中 `mmr_split_mag()` / `split_guarded()` / `mmr_exact64()` 在 Mali-G610 PanVK 上的具体溢出/误算点（或评估在 PanVK 上默认将 Chroma MMR 设为 `Float` 作为稳健默认值）
- [ ] 优化 `0025` `SendLayer()` 背压逻辑（避免极端高码率下直接丢弃 EL 压缩包破坏 GOP）

---

## 任务 3：新增 DV → HDR10 / 10-bit SDR（WCG-SDR BT.2020）动态色调映射输出（中优先级，新特性规划）

### 目标与背景
- 面向**不支持杜比视界的显示设备**（普通 HDR10 电视、SDR 显示器/投影仪），实时解码杜比视界（含 Profile 5 `IPTPQc2`、Profile 7 FEL/MEL、Profile 8.1 及 `0020` HDR Vivid 转 DV），通过逐帧动态元数据（RPU L1）进行色调映射，输出高质量 **HDR10** 或 **10-bit SDR / WCG-SDR（BT.2020 广色域 + Gamma）** 画面。
- 参考 `LibreELEC-Hades` 的 `DV → SDR` 能力，但不照搬其 `libplacebo`（29 个自定义补丁）+ `dvbridge` GLES 路线，避免维护成本高、与当前 `pi-dv-engine` 管线割裂以及丢弃 FEL 优势的问题。

### 技术路线：扩展 `pi-dv-engine` PanVK `P2` 着色器（路线 A）
直接复用当前 `pi-dv-engine` 的 `P0`（RPU 解析）/ `P1`（`NV15` 零拷贝、Profile 5 `IPTPQc2` 解码、Profile 7 FEL 12-bit 重建、MMR/Poly 映射）全部能力，仅扩展 **`P2` 打包与色调映射阶段**及 Kodi 输出控制：
1. **`pi-dv-engine` 输出模式与 `p2_pack.frag` 扩展**
   - 在 `pi_options` 新增输出模式枚举：`PI_OUT_DV_STANDARD`（现有 HDMI 隧道）、`PI_OUT_HDR10`、`PI_OUT_SDR`（含目标峰值亮度 `target_nits`、目标色域 `BT.709 / BT.2020`、目标传递函数 `Gamma 2.2 / 2.4` 参数）。
   - 在 `p2_pack.frag` 新增非隧道分支：12-bit 重建画面 → 线性 BT.2020 RGB → 按逐帧 RPU **L1**（`min_pq / avg_pq / max_pq`）执行 **BT.2390 EETF** 动态色调映射 → 编码为 ST.2084 PQ（HDR10）或 Gamma 2.2/2.4 + 可选 BT.2020→BT.709 矩阵（SDR/WCG-SDR）+ 有序抖动 → 输出 **10-bit `XRGB2101010` / `XBGR2101010`** 缓冲（不再打包顶部 DV 元数据行）。
2. **Kodi 解码/渲染门控与 DRM 元数据控制**
   - 放宽 `0004` / `0005`（`DVDVideoCodecDRMPRIME` / `RendererDRMPRIME`）对 `SupportsDolbyVision()` 的硬门控：当用户开启 DV 转 HDR10/SDR 时，即使 EDID 无 DV VSDB 也允许进入 `CDVTunnelDRMPRIME` 管线。
   - 按输出模式配置 DRM 连接器属性：
     - `DV → HDR10`：下发 `HDR_OUTPUT_METADATA`（ST.2084 + BT.2020 + MaxCLL/MaxFALL）并设置 HDMI `Colorspace = BT2020_RGB`；
     - `DV → WCG-SDR`：清空 `HDR_OUTPUT_METADATA`（SDR 模式）并设置 HDMI `Colorspace = BT2020_RGB`；
     - `DV → 标准 SDR`：清空 `HDR_OUTPUT_METADATA` 并设置 `Colorspace = BT709`。
   - 在 Kodi 播放设置中增加 DV 输出模式（自动 / 强制 DV / 转 HDR10 / 转 10-bit SDR）、目标峰值亮度与 SDR 色域选项。

### 硬件前置验证（Rock 5T 开机后执行）
- [ ] 使用 `modetest` 确认 Rockchip VOP2 `vp0` 主视频平面支持的 10-bit RGB FourCC（`XR30` `XRGB2101010` / `XB30` `XBGR2101010`）及 DRM `Colorspace` 属性枚举值
- [ ] 验证 4K24/30 10-bit RGB（~371 MHz，HDMI 2.0 600 MHz 带宽内）直出；为 4K60 场景规划 8-bit 抖动（`XRGB8888`）或 YCbCr 4:2:0 降级回退方案

### 分阶段实施 Checklist
- [ ] **Phase 1（DV → HDR10）**：`pi-dv-engine` 支持 `PI_OUT_HDR10` + 10-bit RGB 打包，Kodi 放宽非 DV 显示器门控并正确下发 `HDR_OUTPUT_METADATA`，验证 Profile 5/7 FEL/8.1 在非 DV HDR10 设备上色彩与亮度正常
- [ ] **Phase 2（DV → 10-bit SDR / WCG-SDR + L1 BT.2390 DTM）**：在 `p2_pack.frag` 实现逐帧 RPU L1 BT.2390 动态色调映射、Gamma 2.2/2.4 与 BT.2020/BT.709 矩阵及抖动；支持目标峰值亮度与 WCG-SDR 设置
- [ ] **Phase 3（可选扩展）**：接入普通 HDR10 / HDR Vivid（`0020`）片源，统一通过 `pi-dv-engine` 输出到 SDR/WCG-SDR，补齐非 HDR 设备全片源画质增强

---

## 任务 4：新增 HDR10+ 实时转杜比视界 Profile 8.1（中优先级）

### 背景与现状
- 当前 FFmpeg/Kodi 已能解析 `AV_FRAME_DATA_DYNAMIC_HDR_PLUS`（`0011` 播放信息面板已可读出 `Target / MaxSCL / Average / Curve`），但主线 RK3588 HDMI/DRM 驱动无原生 HDR10+ VSIF 下发，播放 HDR10+ 片源时自动回退为静态 HDR10。
- 可直接复用 `0020`（HDR Vivid → DV P8.1）的成熟架构，实时将逐帧 HDR10+ 动态元数据转为 Profile 8.1 RPU 喂给 `pi-dv-engine`。

### 实施 Checklist
- [ ] 实现 `AVDynamicHDRPlus`（`maxscl` / `average_maxrgb` / 场景峰值）→ DV Profile 8.1 RPU（L1 动态元数据）转换器
- [ ] 在 `DVDVideoCodecDRMPRIME` / `DVDDemuxFFmpeg` 接入实时转换开关（`videoplayer.dolbyvisionfromhdr10plus`）并添加 Kodi 设置项
- [ ] 验证开启后在 DV 电视上正确点亮杜比视界且亮度/暗部过渡优于静态 HDR10

---

## 任务 5：新增 AV1 杜比视界 Profile 10（P10.0 / P10.1 / P10.4）支持（中优先级）

### 背景与现状
- RK3588 内置 VPU981 AV1 10-bit 硬件解码器可正常硬解，但 `0004` 中 `CDVTunnelDRMPRIME::Supports()` 硬编码仅放行 Profile 5 / 7 / 8，导致 P10.1/P10.4 回退为 HDR10/HLG，P10.0（`IPTPQc2`）因未进 `pi-dv-engine` 而紫绿偏色。
- 本质上 **P10.0 = AV1 版 P5、P10.1 = AV1 版 P8.1、P10.4 = AV1 版 P8.4**，RPU 语法与重塑/色域公式一致。

### 实施 Checklist
- [ ] 核对 RK3588 VPU981 AV1 硬解输出的 10-bit DRM 像素格式（`NV15` / `P010`）及 `pi-dv-engine` 兼容性
- [ ] 核对 FFmpeg V4L2-request AV1 硬解是否把 AV1 OBU `ITU-T T.35` DV RPU 正确挂到 `AV_FRAME_DATA_DOVI_RPU_BUFFER`（若未挂则在 `DVDVideoCodecDRMPRIME` 侧带提取）
- [ ] 在 `CDVTunnelDRMPRIME::Supports()` 与 `pi-dv-engine` 放行 Profile 10（按 `dv_bl_signal_compatibility_id` 映射 P10.0→P5、P10.1/10.4→P8）
- [ ] 使用 P10.0 / P10.1 测试片在 Rock 5T 上实机验证点亮杜比视界且色彩正常

---

## 任务 6：后续可选优化项（低优先级）

- [ ] 简体中文显示设置与 Estuary 皮肤本地化（参考 Hades `25ad00489d`，按当前 `strings.po` ID 对齐）
- [ ] 评估是否需要基于 `pi-dv-engine` 独立实现 DV Level 5 三态设置（Hades `6b5d1539f2` 强绑定 `dvbridge`，不可直接移植）
- [ ] 可选探索：在 `linux.aarch64.conf` 启用 `CONFIG_VIDEO_SYNOPSYS_HDMIRX=m` 测试 Rock 5T HDMI-IN（流光溢彩 Hyperion / V4L2 预览）
