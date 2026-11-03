#!/bin/bash
set -e

# AI Service Hub - 构建脚本
# 编译并打包为 AiServiceHub.app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="AiServiceHub"
APP_BUNDLE="$SCRIPT_DIR/${APP_NAME}.app"
ICON_FILE="Resources/ai_service_hub.icns"
ICON_DARK_FILE="Resources/ai_service_hub_dark.icns"
CONFIG="${CONFIG:-release}"

# 选择可用的 Xcode（详见 scripts/xcode-env.sh）
source "$SCRIPT_DIR/scripts/xcode-env.sh"
require_developer_dir

echo "==> 编译 ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "❌ 编译失败: $BIN_PATH 不存在"
    exit 1
fi

echo "==> 清理旧 bundle..."
rm -rf "$APP_BUNDLE"

echo "==> 创建 .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制产物
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 复制图标（仅使用仓库内版本，保证构建可复现）
# 浅色版是 bundle 图标（Finder / 未运行时），深色版供运行时切换 Dock 图标
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/ai_service_hub.icns"
    echo "    ✓ 图标已复制 ($ICON_FILE)"
else
    echo "    ⚠️ 缺少 $ICON_FILE，bundle 将使用系统默认图标"
fi

if [ -f "$ICON_DARK_FILE" ]; then
    cp "$ICON_DARK_FILE" "$APP_BUNDLE/Contents/Resources/ai_service_hub_dark.icns"
    echo "    ✓ 深色图标已复制 ($ICON_DARK_FILE)"
fi

# 菜单栏图标（模板图，自动适配菜单栏明暗）
if [ -f "Resources/menubar-icon.png" ]; then
    cp "Resources/menubar-icon.png" "$APP_BUNDLE/Contents/Resources/menubar-icon.png"
    echo "    ✓ 菜单栏图标已复制"
fi

# 设置可执行权限
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Ad-hoc 签名（避免 Gatekeeper 拦截 + 启用 SMAppService）
echo "==> Ad-hoc 签名..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | head -5

# 验证
echo "==> 验证 bundle..."
codesign -dv "$APP_BUNDLE" 2>&1 | head -5

BIN_SIZE=$(du -h "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | cut -f1)
echo ""
echo "✅ 构建完成!"
echo "   App:  $APP_BUNDLE"
echo "   Size: $BIN_SIZE"
echo ""
echo "首次启动："
echo "   open \"$APP_BUNDLE\""
echo ""
echo "如果被 Gatekeeper 拦截："
echo "   xattr -dr com.apple.quarantine \"$APP_BUNDLE\""
