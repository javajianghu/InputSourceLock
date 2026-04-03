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

# 编译 GUI 版本（简化版）
if [ -d "InputSourceLockSimpleGUI" ]; then
    echo "📦 编译图形界面版本 (Cocoa)..."
    
    # 创建 App Bundle
    APP_NAME="InputSourceLock.app"
    mkdir -p "$APP_NAME/Contents/MacOS"
    mkdir -p "$APP_NAME/Contents/Resources"
    
    # 编译 Swift 文件 (使用纯 Cocoa，不依赖 SwiftUI)
    swiftc -o "$APP_NAME/Contents/MacOS/InputSourceLock" \
        -framework Cocoa \
        -framework Carbon \
        InputSourceLockSimpleGUI/main.swift
    
    if [ $? -eq 0 ]; then
        # 创建 Info.plist
        cat > "$APP_NAME/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>InputSourceLock</string>
    <key>CFBundleIdentifier</key>
    <string>com.wukong.InputSourceLock</string>
    <key>CFBundleName</key>
    <string>输入法锁定工具</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF
        
        # 复制应用图标
        if [ -f "Assets/AppIcon.icns" ]; then
            cp Assets/AppIcon.icns "$APP_NAME/Contents/Resources/AppIcon.icns"
            echo "✅ 应用图标已添加"
        fi
        
        # 赋予执行权限
        chmod +x "$APP_NAME/Contents/MacOS/InputSourceLock"
        
        echo "✅ 图形界面版本编译成功：$APP_NAME"
    else
        echo "⚠️  图形界面版本编译失败，但命令行版本可用"
    fi
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
echo "  3. 运行 GUI 版本 (如果编译成功):"
echo "     open InputSourceLock.app"
echo ""
