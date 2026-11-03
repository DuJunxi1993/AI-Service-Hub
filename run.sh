#!/bin/bash
# AI Service Hub - 快速运行（开发模式）
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

SCRIPT_DIR="$(pwd)"
source "$SCRIPT_DIR/scripts/xcode-env.sh"

CONFIG="${CONFIG:-debug}"
BIN=".build/$CONFIG/AiServiceHub"

if [ ! -f "$BIN" ]; then
    require_developer_dir
    echo "==> 编译 ($CONFIG)..."
    swift build -c "$CONFIG"
fi

echo "==> 启动 AI Service Hub..."
"$BIN"
