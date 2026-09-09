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

# ---- 4. 生成应用图标（如有源 PNG，则用 sips + iconutil 生成 .icns）----
# 源文件约定：LockChineseIME/Resources/AppIcon-source.png
ICON_SRC="$SOURCE_DIR/Resources/AppIcon-source.png"
if [ -f "$ICON_SRC" ]; then
    echo ""
    echo "🎨 生成应用图标..."
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    # 用 sips 生成各尺寸
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"       > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"    > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"       > /dev/null 2>&1
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"    > /dev/null 2>&1
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"     > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png"  > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"     > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png"  > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"     > /dev/null 2>&1
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png"  > /dev/null 2>&1

    # 打包成 icns
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "   ✅ → $RESOURCES_DIR/AppIcon.icns"
else
    echo "   （未提供 AppIcon-source.png，将使用系统默认图标）"
fi

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
