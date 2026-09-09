#!/bin/bash

# macOS 输入法锁定 - 打包成可分发的 .dmg 安装包
# 适用于 Apple Silicon (M 系列)，macOS 13+
# 产出：build/锁定中文输入法.dmg（包含 .app + /Applications 快捷方式）

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

# DMG 临时装配目录
DMG_STAGING="$BUILD_DIR/dmg-staging"
# DMG 最终产物
DMG_VOL_NAME="$APP_NAME"
DMG_FILE="$BUILD_DIR/$APP_NAME.dmg"

echo "🔨 打包 $APP_NAME..."

# ---- 清理旧产物 ----
rm -rf "$APP_BUNDLE" "$DMG_STAGING" "$DMG_FILE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_STAGING"

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

# ---- 4. 生成应用图标 ----
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

    # 打包成 icns（用于 app）
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "   ✅ → $RESOURCES_DIR/AppIcon.icns"
else
    echo "   （未提供 AppIcon-source.png，将使用系统默认图标）"
fi

# ---- 5. 装配 DMG 内容 ----
echo ""
echo "💿 装配 DMG..."
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
# 创建 /Applications 软链接（用户拖拽目标）
ln -s /Applications "$DMG_STAGING/Applications"

# 把 .icns 复制到 staging 根目录作为卷图标
# macOS 会读取根目录下的 .VolumeIcon.icns 作为整个卷的图标
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$DMG_STAGING/.VolumeIcon.icns"
fi

# ---- 6. 创建临时可写 DMG ----
echo ""
echo "📀 创建 DMG..."
TMP_DMG="$BUILD_DIR/.tmp.dmg"
rm -f "$TMP_DMG"

# 第一步：UDRW（可读写）格式创建临时 DMG
hdiutil create \
    -volname "$DMG_VOL_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    "$TMP_DMG" > /dev/null

# 第二步：挂载临时 DMG，把 staging 里的 .VolumeIcon.icns 设置为卷图标属性
MOUNT_OUTPUT=$(hdiutil attach "$TMP_DMG" -nobrowse -noverify -noautoopen 2>&1)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | tail -1 | awk '{print $3}')
if [ -d "$MOUNT_POINT" ] && [ -f "$MOUNT_POINT/.VolumeIcon.icns" ]; then
    # 用 SetFile 设置 custom icon 属性
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
    hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1
fi

# 第三步：转成压缩的只读 UDZO DMG
rm -f "$DMG_FILE"
hdiutil convert "$TMP_DMG" \
    -format UDZO \
    -o "$DMG_FILE" \
    -ov > /dev/null

rm -f "$TMP_DMG"

# ---- 7. 清理 ----
rm -rf "$DMG_STAGING"

DMG_SIZE=$(du -sh "$DMG_FILE" | cut -f1)
echo ""
echo "=========================================="
echo "✨ 打包完成！"
echo "=========================================="
echo ""
echo "  📀 DMG 安装包: $DMG_FILE ($DMG_SIZE)"
echo ""
echo "  🚀 用户安装步骤："
echo "     1. 双击打开 锁定中文输入法.dmg"
echo "     2. 把 '锁定中文输入法' 拖到 'Applications' 文件夹"
echo "     3. 在 Applications 中右键 → 打开（首次启动需要确认）"
echo "     4. 系统设置 → 隐私与安全性 → 辅助功能 → 勾选"
echo ""
echo "  ⚠️  Apple Silicon 专属编译（arm64）。如需通用二进制，"
echo "     编辑 build-app.sh 删除 -target arm64-apple-macos13.0 参数"
echo ""
echo "  💡 提示：把 DMG 文件发给同事即可直接安装"
echo ""
