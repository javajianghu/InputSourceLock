# macOS 输入法工具集

合并的输入法管理工具 — 一个命令同时搞定 **输入法锁定** + **中英文状态悬浮窗**。

## 功能

- 🔒 **输入法锁定**：检测到输入法被切走时自动切回（重试 3 次）
- 📍 **状态悬浮窗**：桌面右上角实时显示 "中" / "A"
- ⌨️ **Shift 感知**：`flagsChanged` CGEventTap 精确捕获输入法内部中英文切换
- 🎨 **颜色区分**：中文红底"中"、英文蓝底"A"
- 🌟 **始终置顶**：点击穿透、全空间可见

## 快速开始

```bash
cd InputSourceLock
bash build.sh

# 仅悬浮窗（不锁定）
./build/InputMethodStatus

# 锁定 + 悬浮窗（推荐）
./build/InputMethodStatus com.tencent.inputmethod.wetype.pinyin
```

按 `Ctrl+C` 或 `Cmd+Q` 退出。

## 合并后的用法

```
InputMethodStatus [输入法ID]

  无参数  → 启动悬浮窗，显示当前中英文状态
  带参数  → 锁定到指定输入法 + 并显示状态
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
└────────────────────────────────────────┘
```

## 权限要求

Shift 检测需要 **辅助功能权限**：
系统设置 → 隐私与安全性 → 辅助功能 → 勾选终端/iTerm

未授权时降级运行：仅根据输入源判断（中文输入法 = 中，ABC = 英），Shift 切换无法感知。

## 项目结构

```
input-dont-change/
├── InputMethodStatus/main.swift   # 合并版：悬浮窗 + 锁定
├── InputSourceLock/
│   ├── InputSourceLock/main.swift # 旧版纯终端锁定（保留）
│   ├── build.sh
│   ├── build/
│   │   ├── InputMethodStatus
│   │   └── InputSourceLock
│   └── README.md
└── README.md
```

## 许可证

MIT
