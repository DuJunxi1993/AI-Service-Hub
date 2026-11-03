#!/usr/bin/env bash
#
# 生成 AI Service Hub 的应用图标
#
#   scripts/make-icons.sh
#
# 产物：
#   Resources/ai_service_hub.icns       浅色版 —— bundle 图标（Finder / 未运行时）
#   Resources/ai_service_hub_dark.icns  深色版 —— 运行时切换（运行中的 Dock 图标）
#
# 为什么需要两套 .icns：
#   macOS 的 app 图标**不会**随系统明暗自动切换。asset catalog 里给 appiconset
#   标 "appearances: luminosity/dark" 是空操作 —— actool 会静默丢弃深色 rendition
#   （Assets.car 里只剩 "Any"）。iOS 18 才有这个能力，macOS 没有。
#
#   macOS 上唯一能跟随外观变化的是**运行中**的 Dock 图标
#   （NSApp.applicationIconImage），它在运行时可设，所以深色图标作为普通资源打包，
#   由 AppIconController 按有效外观切换。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LIGHT_SRC="$ROOT_DIR/logo-light.png"
DARK_SRC="$ROOT_DIR/logo-dark.png"
BAR_SRC="$ROOT_DIR/logo-bar.png"
OUT_DIR="$ROOT_DIR/Resources"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# 需要完整 Xcode（SwiftUI 宏插件问题同 build.sh）
source "$SCRIPT_DIR/xcode-env.sh"
require_developer_dir

for f in "$LIGHT_SRC" "$DARK_SRC" "$BAR_SRC"; do
    if [ ! -f "$f" ]; then
        echo "错误：缺少源图 $f" >&2
        exit 1
    fi
done

build_variant() {
    local src="$1" name="$2"
    local iconset="$BUILD_DIR/$name.iconset"

    echo "==> 生成 $name（$(basename "$src")）"
    swift "$SCRIPT_DIR/make-icon.swift" "$src" "$iconset"

    # iconutil 要求目录以 .iconset 结尾
    rm -rf "$BUILD_DIR/$name.iconset.tmp"
    iconutil -c icns "$iconset" -o "$BUILD_DIR/$name.icns"
}

build_variant "$LIGHT_SRC" "ai_service_hub"
build_variant "$DARK_SRC" "ai_service_hub_dark"

# 菜单栏图标：模板图（template image），macOS 只取 alpha 通道并按菜单栏明暗着色，
# 所以一份就够。输出 36×36（18pt @2x），运行时会再按 18pt 显示。
sips -z 36 36 "$BAR_SRC" --out "$OUT_DIR/menubar-icon.png" >/dev/null

mkdir -p "$OUT_DIR"
cp "$BUILD_DIR/ai_service_hub.icns" "$OUT_DIR/ai_service_hub.icns"
cp "$BUILD_DIR/ai_service_hub_dark.icns" "$OUT_DIR/ai_service_hub_dark.icns"

echo "✅ 图标已生成："
ls -la "$OUT_DIR"/ai_service_hub.icns "$OUT_DIR"/ai_service_hub_dark.icns "$OUT_DIR"/menubar-icon.png
