# macOS 输入法锁定工具

一个 macOS 命令行工具，可以锁定系统输入法到指定的输入法，防止意外切换。同时提供悬浮窗实时显示当前输入法的中英文状态。

## 功能特性

### 1. 输入法锁定 (`InputSourceLock`)

- 🔒 **自动锁定**：检测到输入法变化时自动切换回目标输入法
- 🔄 **重试机制**：切换失败时自动重试（最多3次）
- ⚡ **快速响应**：每0.1秒检测一次输入法状态
- ✅ **启动验证**：启动时验证目标输入法是否存在

### 2. 状态悬浮窗 (`InputMethodStatusWindow`)

- 📍 **实时显示**：悬浮窗口实时显示当前输入法的中英文状态
- 🎨 **颜色区分**：中文（绿色）、英文（蓝色）、未知（灰色）
- 🖱️ **可拖动**：支持鼠标拖动调整位置
- 🌟 **始终置顶**：窗口始终显示在最上层

## 快速开始

### 编译项目

```bash
cd ~/my/my-github/input-dont-change/InputSourceLock
bash build.sh
```

编译成功后会在 `build/` 目录下生成两个可执行文件：
- `InputSourceLock` - 输入法锁定工具
- `InputMethodStatusWindow` - 状态悬浮窗

### 查看可用输入法

```bash
./build/InputSourceLock
```

输出示例：
```
📋 可用输入法列表:

  1. Emoji & Symbols
     ID: com.apple.CharacterPaletteIM

  2. ABC
     ID: com.apple.keylayout.ABC

  3. 微信输入法
     ID: com.tencent.inputmethod.wetype.pinyin

  4. 微信输入法
     ID: com.tencent.inputmethod.wetype
```

### 使用输入法锁定工具

锁定到微信输入法（拼音模式）：

```bash
./build/InputSourceLock com.tencent.inputmethod.wetype.pinyin
```

程序会持续运行，按 `Ctrl+C` 停止。

### 使用状态悬浮窗

启动悬浮窗：

```bash
./build/InputMethodStatusWindow
```

悬浮窗会显示在屏幕右上角，可以用鼠标拖动到任意位置。按 `Cmd+Q` 退出。

## 高级用法

### 同时使用两个工具

你可以在不同的终端窗口中同时运行两个工具：

**终端 1** - 锁定输入法：
```bash
./build/InputSourceLock com.tencent.inputmethod.wetype.pinyin
```

**终端 2** - 显示状态悬浮窗：
```bash
./build/InputMethodStatusWindow
```

这样可以既保证输入法不会意外切换，又能实时看到当前的中英文状态。

### 锁定到其他输入法

```bash
# 锁定到 ABC 英文输入法
./build/InputSourceLock com.apple.keylayout.ABC

# 锁定到搜狗输入法（如果已安装）
./build/InputSourceLock com.sogou.inputmethod.sogou.pinyin
```

## 技术细节

### 输入法锁定原理

1. 使用 Carbon TIS API 获取当前输入法 ID
2. 定时器每 0.1 秒检测一次输入法是否变化
3. 如果检测到非目标输入法，立即切换回去
4. 切换失败时自动重试（最多3次，每次间隔0.02秒）

### 状态检测原理

1. 使用 TIS API 获取当前输入法 ID
2. 根据输入法 ID 推断中英文状态：
   - `com.tencent.inputmethod.wetype.pinyin` → 中文
   - `com.apple.keylayout.ABC` → 英文
   - 其他输入法根据 ID 关键词判断
3. 每 0.2 秒更新一次显示

### 权限要求

- **辅助功能权限**：首次运行时可能需要授予辅助功能权限
- 可以在「系统偏好设置」→「安全性与隐私」→「隐私」→「辅助功能」中管理权限

## 常见问题

### Q: 为什么有时候切换不成功？

A: 可能的原因：
1. 没有授予辅助功能权限
2. 输入法 ID 不正确
3. 输入法未完全加载

解决方法：
- 检查并授予辅助功能权限
- 使用 `./build/InputSourceLock` 查看正确的输入法 ID
- 确保目标输入法已安装并启用

### Q: 悬浮窗显示的状态准确吗？

A: 由于 macOS API 限制，只能根据输入法 ID 推断状态，无法获取输入法内部的中英文切换状态。对于微信输入法，拼音模式通常认为是中文状态。

### Q: 可以自定义悬浮窗样式吗？

A: 可以修改 `InputMethodStatusWindow/main.swift` 中的 `setupUI()` 方法来调整窗口大小、颜色、字体等样式。

### Q: 程序会占用很多资源吗？

A: 不会。两个程序都采用轻量级设计，CPU 占用率极低，可以放心长期使用。

## 项目结构

```
InputSourceLock/
├── InputSourceLock/          # 输入法锁定工具源码
│   └── main.swift
├── InputMethodStatusWindow/  # 状态悬浮窗源码
│   └── main.swift
├── build/                    # 编译输出目录
│   ├── InputSourceLock
│   └── InputMethodStatusWindow
├── build.sh                  # 构建脚本
├── list_input_sources.swift  # 输入法查询工具（可选）
├── README.md                 # 项目说明
└── README_悬浮窗.md          # 悬浮窗详细说明
```

## 开发说明

### 重新编译

修改代码后，运行 `bash build.sh` 重新编译。

### 调试技巧

- 输入法锁定工具会在终端输出详细的日志
- 状态悬浮窗会在控制台输出检测到的输入法 ID
- 可以使用 Console.app 查看更详细的系统日志

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
