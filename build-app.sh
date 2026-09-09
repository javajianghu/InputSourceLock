#!/bin/bash

# macOS 输入法锁定 - 打包成完整 .app 应用
# 适用于 Apple Silicon (M 系列)，macOS 13+
# 产出：build/锁定中文输入法.app

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="锁定中文输入法"
EXEC_NAME="LockChineseIME"
BUNDLE_ID="com.tang.LockChineseIME"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SOURCE_DIR="$SCRIPT_DIR/LockChineseIME"

echo "🔨 打包 $APP_NAME.app..."

# ---- 清理旧产物 ----
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# ---- 1. 编译 Swift 源码 ----
echo ""
echo "📦 编译 Swift 源码..."
SWIFT_SOURCES=(
    "$SOURCE_DIR/main.swift"
    "$SOURCE_DIR/AppDelegate.swift"
    "$SOURCE_DIR/AppCore.swift"
    "$SOURCE_DIR/StatusBar.swift"
    "$SOURCE_DIR/Settings.swift"
    "$SOURCE_DIR/LaunchAtLogin.swift"
)

swiftc -o "$MACOS_DIR/$EXEC_NAME" \
    -framework Cocoa \
    -framework Carbon \
    -framework ServiceManagement \
    -framework ApplicationServices \
    -target arm64-apple-macos13.0 \
    "${SWIFT_SOURCES[@]}"

echo "   ✅ → $MACOS_DIR/$EXEC_NAME"

# ---- 2. 复制 Info.plist ----
echo ""
echo "📋 写入 Info.plist..."
cp "$SOURCE_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

# ---- 3. 生成 PkgInfo ----
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# ---- 4. 可选：复制应用图标（如有图标源文件则复制，否则跳过）----
# 如需自定义图标：把 icon_512x512.png 放到 LockChineseIME/Resources/AppIcon.png 后重新打包
ICON_SRC="$SOURCE_DIR/Resources/AppIcon.png"
if [ -f "$ICON_SRC" ]; then
    echo ""
    echo "🎨 复制应用图标..."
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.png"
fi
echo "   （未提供 AppIcon.png，将使用系统默认图标）"

echo ""
echo "=========================================="
echo "✨ 打包完成！"
echo "=========================================="
echo ""
echo "  📦 产物: $APP_BUNDLE"
echo ""
echo "  🚀 安装方式："
echo "     1. 把 '锁定中文输入法.app' 拖到 /Applications 文件夹"
echo "     2. 双击启动（首次启动需要：右键 → 打开 → 确认）"
echo "     3. 在 系统设置 → 隐私与安全性 → 辅助功能 中授权"
echo ""
echo "  ⚠️  Apple Silicon 专属编译（arm64）。如需通用二进制，"
echo "     编辑 build-app.sh 删除 -target arm64-apple-macos13.0 参数"
echo ""
