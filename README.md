# 锁定中文输入法

一个 macOS 应用，自动锁定目标输入法 + 在屏幕右上角显示当前中英文状态（"中" / "A"），并自动跟随输入法内部的 Shift 切换。

## 安装使用

```bash
git clone <repo>
cd input-dont-change

# 打包成 .app
bash build-app.sh

# 产物在 build/锁定中文输入法.app
# 拖到 /Applications 文件夹，双击启动
```

**首次启动**：右键 → 打开 → 确认（未公证应用的标准流程）。

## 功能

| 功能 | 说明 |
|---|---|
| 🔒 输入法锁定 | 检测到输入法被切走时自动切回（0.15s 检测，3 次重试） |
| 📍 悬浮窗 | 跟随光标，红底"中" / 蓝底"A"，实时反映输入法内部中英文状态 |
| ⌨️ Shift 感知 | `flagsChanged` CGEventTap 精确捕获输入法内部中英文切换 |
| 🪟 菜单栏图标 | 动态显示当前中英文状态（"中" / "A"），点开看完整菜单 |
| ⚙️ 设置窗口 | Dock 图标 / 菜单栏 → 打开设置（单页垂直滚动） |
| 🚀 开机启动 | `SMAppService` 注册（macOS 13+） |

## 权限

首次启动后，需要在 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选「锁定中文输入法」：

```
系统设置 → 隐私与安全性 → 辅助功能 → 勾选「锁定中文输入法」
```

设置窗口有快捷按钮可直接跳转到该页面。

未授权时仍可运行，但只能感知输入源切换（中文输入法 vs ABC），无法感知输入法内部的 Shift 切换。

## 应用结构

```
input-dont-change/
├── LockChineseIME/                # 推荐：完整 App 源码
│   ├── main.swift                 # 入口
│   ├── AppDelegate.swift          # NSApplicationDelegate
│   ├── AppCore.swift              # TIS helpers + InputMethodManager + StatusOverlayWindow
│   ├── StatusBar.swift            # NSStatusItem + 菜单
│   ├── Settings.swift             # NSWindowController（设置窗口）
│   ├── LaunchAtLogin.swift        # SMAppService 包装
│   ├── Info.plist                 # Bundle 元数据（含 NSAccessibilityUsageDescription）
│   └── Resources/                 # 可选图标等
├── build-app.sh                   # 打包脚本 → build/锁定中文输入法.app
│
├── InputSourceLock/               # 旧版：纯 CLI 工具（保留兼容）
│   ├── InputSourceLock/main.swift
│   ├── list_input_sources.swift
│   └── build.sh                   # 编译 CLI 工具
│
├── InputMethodStatus/             # 旧版：CLI 单文件实现（保留）
│   └── main.swift
│
├── 使用展示.png                   # 悬浮窗效果截图
├── CLAUDE.md                      # Claude / AI Agent 项目指南
└── README.md
```

## 状态检测原理

```
┌────────────────────────────────────────┐
│ TIS API (轮询 + kTISNotify 通知)       │
│ → 检测输入源切换                        │
│   中文输入法 = 默认中文模式              │
│   ABC 键盘   = 英文模式                 │
├────────────────────────────────────────┤
│ CGEventTap (flagsChanged + keyDown)    │
│ → Shift 单独按下/释放 → 中/英翻转       │
│ → Shift+其他键 → 不触发（排除大写字母）   │
├────────────────────────────────────────┤
│ NSPanel 悬浮窗                         │
│ "中" = 红底  |  "A" = 蓝底             │
├────────────────────────────────────────┤
│ NSStatusItem 菜单栏图标                 │
│ "中" / "A" 动态文字，点击弹出菜单        │
└────────────────────────────────────────┘
```

## 开发命令

```bash
# 打包 .app
bash build-app.sh

# 编译旧版 CLI（保留兼容）
cd InputSourceLock && bash build.sh

# 查看可用输入法 ID（独立 helper）
swift InputSourceLock/list_input_sources.swift
```

## 平台要求

- macOS 13.0+（`SMAppService` 需要）
- Apple Silicon (M 系列)

未公证：首次启动需要右键 → 打开。这是个人工具项目的有意选择。

## 许可证

MIT
