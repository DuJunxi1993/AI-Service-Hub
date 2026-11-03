#!/bin/bash
# 共享工具链探测 —— 由 build.sh / run.sh source。
#
# CommandLineTools 不含 SwiftUI 的宏插件（libSwiftUIMacros.dylib），
# 用它编译会以 "external macro implementation type 'SwiftUIMacros.StateMacro'
# could not be found" 失败，因此必须指向一份完整 Xcode。

# detect_developer_dir —— 打印可用的 DEVELOPER_DIR，失败返回 1
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

# require_developer_dir —— 探测并导出 DEVELOPER_DIR，失败则报错退出
require_developer_dir() {
    if ! DETECTED_DEVELOPER_DIR="$(detect_developer_dir)"; then
        echo "❌ 未找到可用的 Xcode（CommandLineTools 无法编译本项目）"
        echo "   请安装 Xcode，或设置 DEVELOPER_DIR 指向完整 Xcode"
        exit 1
    fi
    export DEVELOPER_DIR="$DETECTED_DEVELOPER_DIR"
    echo "==> 工具链: $DEVELOPER_DIR"
}
