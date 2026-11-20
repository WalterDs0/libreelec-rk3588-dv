# LibreELEC for Radxa Rock 5T (RK3588) — TV-led Dolby Vision 移植仓库

本仓库基于 **LibreELEC.tv (`master` / LibreELEC 13)** 构建，目标是给 **Radxa Rock 5T (RK3588)** 带来完整的 4K60/HDR 与 **Standard (TV-led) Dolby Vision** 支持（参考 [dangerouslaser/libreelec-rpi-dv](https://github.com/dangerouslaser/libreelec-rpi-dv) 架构）。

## 当前进度：第一阶段（基线验证）

1. **内核**：保留 LibreELEC 官方 `rockchip`（Linux `6.19.0` + 187 个 Rockchip 补丁，已内置 **HDMI 2.0 600MHz Scrambling / 4K60**、**YUV420**、**VDPU381 硬解** 与 **VOP2 HDR WIP**）。
2. **GPU / Vulkan**：在 `projects/Rockchip/devices/RK3588/options` 开启 `VULKAN="vulkan-loader"`，启用 Mesa `PanVK` Vulkan 驱动（为第二阶段 `pi-dv-engine` 做准备）。
3. **Rock 5T 适配**：在 `scripts/uboot_helper` 中添加 `rock-5t` 目标（镜像内已包含主线 `rk3588-rock-5t.dtb`）。
4. **GitHub Actions**：新增 `.github/workflows/build-rock5t.yml`，支持在云端自动清理磁盘、缓存源码并交叉编译出 `.img.gz` 与 `.tar`。

> **刷机后关于 Rock 5T 设备树的提示**：
> 首次刷写 `.img.gz` 到 SD 卡/eMMC 后，建议在启动分区 `extlinux/extlinux.conf` 中显式指定：
> `FDT /rockchip/rk3588-rock-5t.dtb`
> （否则 U-Boot 默认会加载 `rk3588-rock-5b.dtb`）。

## 第二阶段规划（待基线实机验证通过后推进）

1. 移植 `libreelec-rpi-dv` 内核 `0001–0003` 通用 DRM HDMI `"Dolby Vision"` 属性与 VSIF 补丁到 `dw-hdmi-qp` / `VOP2`（确保 8-bit RGB 4:4:4 Bit-Exact 无损直通）。
2. 引入 `pi-dv-engine` 并在 Rock 5T 的 Mesa `PanVK` 上验证 Vulkan 计算着色器与 DMA-BUF 零拷贝导入。
3. 移植 Kodi `Piers` 的杜比视界补丁集。
