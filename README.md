# macOS 输入法锁定工具

一款专为 macOS 设计的输入法管理工具，可防止系统自动切换到 ABC 输入法，保持你选择的输入法（如微信输入法、搜狗输入法等）始终激活。

## 🎯 功能特性

- **实时监控**: 持续监控输入法状态变化（0.3 秒检测间隔）
- **自动拦截**: 检测到切换到 ABC 时立即切换回目标输入法

## 使用展示

![使用展示](./使用展示.png)

## 📦 项目结构

```
InputSourceLock/
├── InputSourceLock/              # 命令行版本
│   └── main.swift
├── Package.swift                 # Swift Package 配置
├── build.sh                      # 编译脚本
└── README.md                     # 项目说明
```

## 🚀 使用方法

```bash
# 1. 进入 build 目录
cd build

# 2. 运行程序（不带参数查看所有可用输入法）
./InputSourceLock

# 3. 锁定到指定输入法
./InputSourceLock com.tencent.inputmethod.wetype.pinyin
```

## 🔍 常见输入法 ID

| 输入法名称 | 输入法 ID |
|-----------|----------|
| 微信输入法 | `com.tencent.inputmethod.WeChatIM.Pinyin` |
| 搜狗输入法 | `com.sogou.inputmethod.SogouPinyin` |
| 百度输入法 | `com.baidu.inputmethod.BaiduIM.Pinyin` |
| QQ 输入法 | `com.tencent.inputmethod.QQPinyin` |
| 拼音 - 简体 | `com.apple.inputmethod.SCIM.ITABC` |
| 五笔字型 | `com.apple.inputmethod.SCIM.WBIM` |
| 英文 ABC | `com.apple.keylayout.ABC` |

> ⚠️ **提示**: 实际 ID 可能因版本不同而有差异，请先运行 `./InputSourceLock` 不带参数查看所有可用输入法。

## 🛠️ 技术实现

本应用使用 macOS Carbon 框架的 Text Input Source (TIS) API:

- `TISCopyCurrentKeyboardInputSource()` - 获取当前输入法
- `TISCreateInputSourceList()` - 获取所有可用输入法
- `TISSelectInputSource()` - 切换到指定输入法
- `TISGetInputSourceProperty()` - 获取输入法属性

监控逻辑在主线程 RunLoop 中运行，确保 HIToolbox API 的正确调用。

## ❓ 常见问题

### Q: 为什么有时会看到切换到 ABC？
A: 某些应用（特别是系统级应用）可能会强制切换输入法。程序会在 0.3 秒内检测并切换回来。

### Q: 会影响其他输入法的正常使用吗？
A: 不会。程序只阻止切换到 ABC 输入法，你可以在目标输入法内部正常切换中英文模式。

### Q: 如何完全退出程序？
A: 按 `Ctrl+C` 终止命令行程序。

### Q: 找不到我的输入法怎么办？
A: 运行 `./InputSourceLock` 不带参数，会列出所有可用输入法。

### Q: 可以锁定到其他非 ABC 输入法吗？
A: 可以！选择任何你想要的输入法作为目标即可，不仅限于阻止 ABC。

## 📝 开发环境要求

- macOS 13.0 或更高版本
- Xcode 15.0+（可选，用于 GUI 开发）
- Swift 5.9+

## 📄 许可证

MIT License

## 👨‍💻 作者

忘忧 - Java 江湖侠客岛

---

**💡 如果这个工具对你有帮助，欢迎 Star ⭐ 分享给更多需要的朋友！**
