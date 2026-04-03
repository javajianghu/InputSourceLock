#!/bin/bash

# macOS 输入法锁定工具 - 编译脚本

echo "🔨 开始编译输入法锁定工具..."

# 创建输出目录
mkdir -p build

# 编译命令行版本
echo "📦 编译命令行版本..."
swiftc -o build/InputSourceLock \
    -framework Cocoa \
    -framework Carbon \
    InputSourceLock/main.swift

if [ $? -eq 0 ]; then
    echo "✅ 命令行版本编译成功：build/InputSourceLock"
else
    echo "❌ 命令行版本编译失败"
    exit 1
fi

echo ""
echo "=========================================="
echo "✨ 编译完成!"
echo "=========================================="
echo ""
echo "使用方法:"
echo "  1. 查看可用输入法:"
echo "     ./build/InputSourceLock"
echo ""
echo "  2. 锁定到指定输入法:"
echo "     ./build/InputSourceLock <输入法 ID>"
echo ""
