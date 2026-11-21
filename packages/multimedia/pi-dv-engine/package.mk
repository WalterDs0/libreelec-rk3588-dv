# SPDX-License-Identifier: GPL-2.0-or-later

PKG_NAME="pi-dv-engine"
PKG_VERSION="0.5.0"
PKG_SHA256="5e256d79db91a16a7ba5705f76cef00841face6b8a0bc7ea412c81c61cd02306"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/dangerouslaser/libreelec-rpi-dv"
PKG_URL="https://github.com/dangerouslaser/libreelec-rpi-dv/releases/download/engine-${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain ffmpeg vulkan-headers vulkan-loader libdrm"
PKG_TOOLCHAIN="cmake"
PKG_CMAKE_OPTS_TARGET="-DPI_BUILD_BENCH=ON -DPI_SHARED=ON"

pre_configure_target() {
  cp -f ${PKG_DIR}/files/*.spv ${PKG_BUILD}/engine/shaders/spirv/
}
