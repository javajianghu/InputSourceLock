#!/bin/bash

# macOS 输入法锁定工具 - 开机自启设置脚本

echo "🔧 正在设置开机自启动..."
echo ""

# 获取当前用户
CURRENT_USER=$(whoami)

# 创建 LaunchAgents 目录 (如果不存在)
mkdir -p ~/Library/LaunchAgents

# 创建启动代理配置文件
cat > ~/Library/LaunchAgents/com.wukong.InputSourceLock.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wukong.InputSourceLock</string>
    <key>ProgramArguments</key>
    <array>
        <string>INPUT_SOURCE_LOCK_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/InputSourceLock.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/InputSourceLock.error.log</string>
</dict>
</plist>
EOF

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$SCRIPT_DIR/InputSourceLock.app/Contents/MacOS/InputSourceLock"

# 替换配置文件中的路径占位符
sed -i '' "s|INPUT_SOURCE_LOCK_PATH|$APP_PATH|g" ~/Library/LaunchAgents/com.wukong.InputSourceLock.plist

# 加载启动代理
launchctl unload ~/Library/LaunchAgents/com.wukong.InputSourceLock.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.wukong.InputSourceLock.plist

if [ $? -eq 0 ]; then
    echo "✅ 开机自启动设置成功!"
    echo ""
    echo "📝 配置详情:"
    echo "   - 配置文件：~/Library/LaunchAgents/com.wukong.InputSourceLock.plist"
    echo "   - 应用路径：$APP_PATH"
    echo ""
    echo "💡 下次开机时会自动启动输入法锁定工具"
    echo "   如需立即测试，请重启电脑或运行：launchctl start com.wukong.InputSourceLock"
else
    echo "❌ 设置失败，请检查权限"
    exit 1
fi

echo ""
echo "----------------------------------------"
echo "如需取消开机自启，运行以下命令:"
echo "  launchctl unload ~/Library/LaunchAgents/com.wukong.InputSourceLock.plist"
echo "  rm ~/Library/LaunchAgents/com.wukong.InputSourceLock.plist"
echo "----------------------------------------"
