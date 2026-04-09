#!/bin/bash

# 同时启动输入法锁定工具和状态悬浮窗

TARGET_INPUT_METHOD="${1:-com.tencent.inputmethod.wetype.pinyin}"

echo "=========================================="
echo "  启动输入法锁定工具 + 状态悬浮窗"
echo "=========================================="
echo ""
echo "🎯 目标输入法: $TARGET_INPUT_METHOD"
echo ""

# 检查可执行文件是否存在
if [ ! -f "./build/InputSourceLock" ]; then
    echo "❌ 错误: 找不到 InputSourceLock，请先运行 build.sh 编译"
    exit 1
fi

if [ ! -f "./build/InputMethodStatusWindow" ]; then
    echo "❌ 错误: 找不到 InputMethodStatusWindow，请先运行 build.sh 编译"
    exit 1
fi

# 在后台启动悬浮窗
echo "📍 正在启动状态悬浮窗..."
./build/InputMethodStatusWindow &
STATUS_WINDOW_PID=$!
echo "✅ 状态悬浮窗已启动 (PID: $STATUS_WINDOW_PID)"
echo ""

# 等待一下让悬浮窗先显示
sleep 1

# 启动输入法锁定工具（前台运行）
echo "🔒 正在启动输入法锁定工具..."
echo "💡 提示: 按 Ctrl+C 停止锁定工具，悬浮窗会自动关闭"
echo ""

# 设置信号处理，确保退出时关闭悬浮窗
trap "echo ''; echo '👋 正在退出...'; kill $STATUS_WINDOW_PID 2>/dev/null; exit 0" INT TERM

# 启动输入法锁定工具
./build/InputSourceLock "$TARGET_INPUT_METHOD"

# 如果锁定工具退出，也关闭悬浮窗
kill $STATUS_WINDOW_PID 2>/dev/null
