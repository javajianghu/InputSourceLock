#!/bin/bash

# macOS 输入法工具集 - 编译脚本
# InputMethodStatus = 状态悬浮窗 + 可选输入法锁定（合并版）
# InputSourceLock    = 纯终端锁定（无 GUI，旧版保留）

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔨 编译输入法工具集..."
mkdir -p "$SCRIPT_DIR/build"

# ---- 1. 合并版：状态显示 + 输入法锁定 ----
echo ""
echo "📦 InputMethodStatus（悬浮窗 + 锁定）..."
swiftc -o "$SCRIPT_DIR/build/InputMethodStatus" \
    -framework Cocoa -framework Carbon \
    "$PROJECT_DIR/InputMethodStatus/main.swift"
echo "   ✅ → build/InputMethodStatus"

# ---- 2. 旧版纯终端锁定（保留兼容） ----
echo ""
echo "📦 InputSourceLock（纯终端）..."
swiftc -o "$SCRIPT_DIR/build/InputSourceLock" \
    -framework Cocoa -framework Carbon \
    "$SCRIPT_DIR/InputSourceLock/main.swift"
echo "   ✅ → build/InputSourceLock"

echo ""
echo "=========================================="
echo "✨ 编译完成！"
echo "=========================================="
echo ""
echo "  # 仅显示状态悬浮窗（不锁定）"
echo "  ./build/InputMethodStatus"
echo ""
echo "  # 锁定 + 状态悬浮窗（推荐）"
echo "  ./build/InputMethodStatus com.tencent.inputmethod.wetype.pinyin"
echo ""
echo "  # 查看可用输入法"
echo "  ./build/InputMethodStatus --list"
echo "  ./build/InputSourceLock"
echo ""
