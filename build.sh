#!/bin/bash
set -e

# AstrBot Launcher - 构建脚本
# 编译并打包为 AstrbotLauncher.app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="AstrbotLauncher"
APP_BUNDLE="$SCRIPT_DIR/${APP_NAME}.app"
CONFIG="${CONFIG:-release}"

# 选择可用的 Xcode。
# CommandLineTools 不含 SwiftUI 的宏插件（libSwiftUIMacros.dylib），
# 用它编译会以 "external macro implementation type 'SwiftUIMacros.StateMacro'
# could not be found" 失败，因此必须指向一份完整 Xcode。
detect_developer_dir() {
    # 1. 用户已显式指定
    if [ -n "$DEVELOPER_DIR" ] && [ -d "$DEVELOPER_DIR" ]; then
        echo "$DEVELOPER_DIR"; return 0
    fi
    # 2. xcode-select 当前指向的若是完整 Xcode，直接用
    local selected
    selected="$(xcode-select -p 2>/dev/null || true)"
    case "$selected" in
        */CommandLineTools|"") selected="" ;;
    esac
    if [ -n "$selected" ]; then
        echo "$selected"; return 0
    fi
    # 3. 扫描 /Applications：优先正式版 Xcode.app，其次变体（-beta 等）
    local official="/Applications/Xcode.app/Contents/Developer"
    if [ -d "$official" ]; then
        echo "$official"; return 0
    fi
    local candidate
    for candidate in $(ls -d /Applications/Xcode*.app/Contents/Developer 2>/dev/null | sort -r); do
        echo "$candidate"; return 0
    done
    return 1
}

if ! DETECTED_DEVELOPER_DIR="$(detect_developer_dir)"; then
    echo "❌ 未找到可用的 Xcode（CommandLineTools 无法编译本项目）"
    echo "   请安装 Xcode，或设置 DEVELOPER_DIR 指向完整 Xcode"
    exit 1
fi
export DEVELOPER_DIR="$DETECTED_DEVELOPER_DIR"
echo "==> 工具链: $DEVELOPER_DIR"

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

# 复制图标
# 优先用 macOS 14+ 的 .icon 文件夹格式（自动编译成 .icns）
ICON_SOURCE_DIR="$HOME/Downloads/Astrbot_Launcher.icon"
if [ -d "$ICON_SOURCE_DIR" ] && [ -f "$ICON_SOURCE_DIR/icon.json" ]; then
    # 从 .icon 编译成 .icns（用 sips 生成多分辨率，iconutil 打包）
    TMP_ICONSET=$(mktemp -d)
    SRC_PNG="$ICON_SOURCE_DIR/Assets/astrbot_launcher.png"
    if [ ! -f "$SRC_PNG" ] || [ $(sips -g pixelWidth "$SRC_PNG" 2>/dev/null | awk '{print $2}') -lt 256 ]; then
        echo "    ⚠️ 源 PNG 太小（<256px），用现有 astrbot_launcher.icns"
    else
        sips --resampleWidth 16   "$SRC_PNG" --out "$TMP_ICONSET/icon_16x16.png"     > /dev/null
        sips --resampleWidth 32   "$SRC_PNG" --out "$TMP_ICONSET/icon_16x16@2x.png"  > /dev/null
        sips --resampleWidth 32   "$SRC_PNG" --out "$TMP_ICONSET/icon_32x32.png"     > /dev/null
        sips --resampleWidth 64   "$SRC_PNG" --out "$TMP_ICONSET/icon_32x32@2x.png"  > /dev/null
        sips --resampleWidth 128  "$SRC_PNG" --out "$TMP_ICONSET/icon_128x128.png"   > /dev/null
        sips --resampleWidth 256  "$SRC_PNG" --out "$TMP_ICONSET/icon_128x128@2x.png" > /dev/null
        sips --resampleWidth 256  "$SRC_PNG" --out "$TMP_ICONSET/icon_256x256.png"   > /dev/null
        sips --resampleWidth 512  "$SRC_PNG" --out "$TMP_ICONSET/icon_256x256@2x.png" > /dev/null
        sips --resampleWidth 512  "$SRC_PNG" --out "$TMP_ICONSET/icon_512x512.png"   > /dev/null
        cp "$SRC_PNG" "$TMP_ICONSET/icon_512x512@2x.png"
        iconutil --convert icns --output "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$TMP_ICONSET"
        rm -rf "$TMP_ICONSET"
        echo "    ✓ 图标已编译 (.icon → .icns)"
        # 同时把最新的 .icns 复制到项目根，下次 build 优先用它
        cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "astrbot_launcher.icns"
    fi
fi
# 优先用 Pictures 里的新 .icns（如果存在且大于 50KB）
PICTURES_ICNS="$HOME/Pictures/icons/astrbot_launcher.icns"
if [ -f "$PICTURES_ICNS" ] && [ $(stat -f "%z" "$PICTURES_ICNS" 2>/dev/null) -gt 50000 ]; then
    cp "$PICTURES_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "    ✓ 图标已复制 (~/Pictures/icons/astrbot_launcher.icns)"
elif [ -f "astrbot_launcher.icns" ]; then
    cp "astrbot_launcher.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "    ✓ 图标已复制 (.icns 缓存)"
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
