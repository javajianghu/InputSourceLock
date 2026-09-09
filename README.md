# macOS 输入法工具集

一个命令同时搞定**输入法锁定**和**桌面状态悬浮窗**。

## 一键启动

```bash
cd InputSourceLock && bash build.sh

# 弹框选择：要锁定的输入法 + 初始中英文状态
./build/InputMethodStatus

# 快速通道：跳过弹框，直接锁定（命令行直接传目标输入法 ID）
./build/InputMethodStatus com.tencent.inputmethod.wetype.pinyin
```

按 `Ctrl+C` 退出。

## 启动对话框

不带任何参数运行时弹出「初始化输入法锁定」对话框：

- **锁定输入法**：下拉列出所有可用输入法；第一项「（不锁定，仅显示状态）」，其余按 `getAvailableInputSources` 顺序排列；同名输入法会自动拼上 ID 便于区分（如「微信输入法（com.tencent.inputmethod.wetype）」 vs 「微信输入法（com.tencent.inputmethod.wetype.pinyin）」）；默认启发式选中第一个中文输入法
- **初始输入法状态**：中文 / 英文 单选
- **开始**：按所选配置启动；**取消**：直接退出程序

命令行直接传目标输入法 ID 时跳过对话框，作为快速通道。

## 功能

- 🔒 输入法被切走时自动切回（0.15s 检测，3 次重试）
- 📍 桌面右上角悬浮窗，红底"中" / 蓝底"A"
- ⌨️ Shift / CapsLock 切换中英文模式时悬浮窗实时更新
- 🌟 始终置顶、点击穿透、全空间可见
- 🎯 启动对话框选择要锁定的输入法 + 设置初始中英文状态（无参运行时）

## 项目结构

```
input-dont-change/
├── InputMethodStatus/main.swift   # 主程序（锁定 + 悬浮窗 + 启动对话框）
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
