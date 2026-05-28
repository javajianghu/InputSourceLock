# macOS 输入法工具集

一个命令同时搞定**输入法锁定**和**桌面状态悬浮窗**。

## 一键启动

```bash
cd InputSourceLock && bash build.sh

# 锁定 + 状态悬浮窗（推荐）
./build/InputMethodStatus com.tencent.inputmethod.wetype.pinyin

# 仅状态悬浮窗（不锁定）
./build/InputMethodStatus
```

按 `Ctrl+C` 退出。

## 功能

- 🔒 输入法被切走时自动切回（0.15s 检测，3 次重试）
- 📍 桌面右上角悬浮窗，红底"中" / 蓝底"A"
- ⌨️ Shift / CapsLock 切换中英文模式时悬浮窗实时更新
- 🌟 始终置顶、点击穿透、全空间可见

## 项目结构

```
input-dont-change/
├── InputMethodStatus/main.swift   # 主程序（锁定 + 悬浮窗）
├── InputSourceLock/               # 旧版纯终端（保留兼容）+ 编译脚本
│   ├── InputSourceLock/main.swift
│   ├── build.sh
│   └── build/
└── README.md
```

## 权限

Shift 检测需 **辅助功能权限** → 系统设置 → 隐私与安全性 → 辅助功能 → 勾选终端/iTerm。
未授权时仍可运行，但只能感知输入源切换（中文输入法 vs ABC），无法感知输入法内部的 Shift 切换。

## 许可证

MIT
