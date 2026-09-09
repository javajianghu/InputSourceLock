import Cocoa
import Carbon

// MARK: - Constants

/// 纯英文输入法 ID 集合（不具备中文输入能力）
private let asciiOnlyInputSourceIDs: Set<String> = [
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.US",
    "com.apple.keylayout.USExtended",
    "com.apple.keylayout.British",
    "com.apple.keylayout.British-PC",
    "com.apple.keylayout.Canadian",
    "com.apple.keylayout.Australian",
    "com.apple.keylayout.Irish",
    "com.apple.keylayout.Dvorak",
    "com.apple.keylayout.Colemak",
]

private let windowSize = NSSize(width: 22, height: 22)
private let pollingInterval: TimeInterval = 0.15
private let cursorTrackInterval: TimeInterval = 0.08
private let maxLockRetry: Int = 3
private let lockRetryDelay: TimeInterval = 0.02

// MARK: - TIS Helpers

func getCurrentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        return nil
    }
    return tisGetString(source, key: kTISPropertyInputSourceID)
}

func tisGetString(_ source: TISInputSource, key: CFString) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func isChineseCapableInputSource(_ sourceID: String) -> Bool {
    !asciiOnlyInputSourceIDs.contains(sourceID)
}

func tisGetLocalizedName(_ source: TISInputSource) -> String? {
    tisGetString(source, key: kTISPropertyLocalizedName)
}

/// 获取所有已启用的输入法
func getAvailableInputSources() -> [(id: String, name: String)] {
    var result: [(id: String, name: String)] = []
    guard let arr = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else {
        return result
    }
    let count = CFArrayGetCount(arr)
    for i in 0..<count {
        let src = unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: TISInputSource.self)
        if let id = tisGetString(src, key: kTISPropertyInputSourceID),
           let name = tisGetString(src, key: kTISPropertyLocalizedName) {
            result.append((id: id, name: name))
        }
    }
    return result
}

// MARK: - StatusOverlayWindow

/// 悬浮窗跟随光标的偏移量（光标右上角偏上）
private let cursorOffsetX: CGFloat = 12
private let cursorOffsetY: CGFloat = 24

final class StatusOverlayWindow: NSPanel {

    private let bgView: NSView
    private let label: NSTextField

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(initialCursor: NSPoint) {
        bgView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 5
        bgView.layer?.masksToBounds = true

        label = NSTextField(frame: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height))
        label.isEditable = false
        label.isBordered = false
        label.isSelectable = false
        label.alignment = .center
        label.backgroundColor = .clear
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        bgView.addSubview(label)

        let frame = NSRect(
            x: initialCursor.x + cursorOffsetX,
            y: initialCursor.y + cursorOffsetY,
            width: windowSize.width,
            height: windowSize.height
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        contentView?.addSubview(bgView)
    }

    /// 将悬浮窗重新定位到指定光标点的右上角
    func reposition(cursor: NSPoint) {
        setFrame(NSRect(
            x: cursor.x + cursorOffsetX,
            y: cursor.y + cursorOffsetY,
            width: windowSize.width,
            height: windowSize.height
        ), display: true, animate: false)
    }

    /// 显示中文状态（红底「中」）。
    func showChinese() {
        label.stringValue = "中"
        label.textColor = .white
        bgView.layer?.backgroundColor = NSColor(red: 0.88, green: 0.28, blue: 0.24, alpha: 0.82).cgColor
    }

    func showEnglish() {
        label.stringValue = "A"
        label.textColor = .white
        bgView.layer?.backgroundColor = NSColor(red: 0.22, green: 0.55, blue: 0.92, alpha: 0.82).cgColor
    }
}

// MARK: - Init Dialog

/// 启动时对话框的配置结果
struct InitConfig {
    /// 用户选择的要锁定的输入法 ID；nil = 不锁定，仅显示状态悬浮窗
    let targetInputSourceID: String?
    /// 初始的中英文模式：true = 中文；false = 英文
    let initialIsChinese: Bool
}

/// 弹出启动初始化对话框，让用户选择要锁定的输入法 + 设置初始中英文状态。
/// - Returns: 用户配置；若用户取消则返回 `nil`（调用方应退出程序）。
private func showInitDialog() -> InitConfig? {
    let sources = getAvailableInputSources()

    let alert = NSAlert()
    alert.messageText = "初始化输入法锁定"
    alert.informativeText = "选择要锁定的输入法，并设置初始输入法状态"
    alert.alertStyle = .informational

    // accessory view：上 = 输入法下拉；下 = 中英文状态单选
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 110))

    // —— 输入法下拉 ——
    let sourceLabel = NSTextField(labelWithString: "锁定输入法：")
    sourceLabel.frame = NSRect(x: 20, y: 75, width: 90, height: 24)
    sourceLabel.font = NSFont.systemFont(ofSize: 13)
    container.addSubview(sourceLabel)

    let popup = NSPopUpButton(frame: NSRect(x: 115, y: 73, width: 245, height: 26))
    popup.font = NSFont.systemFont(ofSize: 12)

    // 第一项：不锁定（仅显示状态悬浮窗）
    popup.addItem(withTitle: "（不锁定，仅显示状态）")

    for source in sources {
        // 同名输入法可能存在多条（如微信输入法的 wetype / wetype.pinyin），拼上 ID 便于区分
        popup.addItem(withTitle: "\(source.name)（\(source.id)）")
    }

    // 启发式默认选中第一个中文输入法；都没有则保持「不锁定」
    if let defaultIndex = sources.firstIndex(where: { isChineseCapableInputSource($0.id) }) {
        popup.selectItem(at: defaultIndex + 1) // +1 因为第一项是「不锁定」
    }

    if sources.isEmpty {
        popup.isEnabled = false
    }

    container.addSubview(popup)

    // —— 单选：当前输入法状态 ——
    let stateLabel = NSTextField(labelWithString: "初始输入法状态：")
    stateLabel.frame = NSRect(x: 20, y: 38, width: 90, height: 24)
    stateLabel.font = NSFont.systemFont(ofSize: 13)
    container.addSubview(stateLabel)

    let chineseRadio = NSButton()
    chineseRadio.title = "中文"
    chineseRadio.setButtonType(.radio)
    chineseRadio.frame = NSRect(x: 200, y: 40, width: 60, height: 20)
    chineseRadio.state = .on
    container.addSubview(chineseRadio)

    let englishRadio = NSButton()
    englishRadio.title = "英文"
    englishRadio.setButtonType(.radio)
    englishRadio.frame = NSRect(x: 265, y: 40, width: 60, height: 20)
    englishRadio.state = .off
    container.addSubview(englishRadio)

    // 手动联动：点击任一 radio 时把另一个置为 off，实现单选效果
    // （避免依赖 macOS 11+ 的 NSButtonGroup，兼容 build.sh 默认部署目标）
    _ = RadioSyncCoordinator(chinese: chineseRadio, english: englishRadio)

    alert.accessoryView = container
    alert.addButton(withTitle: "开始")
    alert.addButton(withTitle: "取消")

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return nil }

    // index 0 = 不锁定；index >= 1 对应 sources[index - 1]
    let selectedIndex = popup.indexOfSelectedItem
    let targetID: String?
    if selectedIndex <= 0 {
        targetID = nil
    } else {
        let realIndex = selectedIndex - 1
        targetID = (realIndex < sources.count) ? sources[realIndex].id : nil
    }

    return InitConfig(
        targetInputSourceID: targetID,
        initialIsChinese: chineseRadio.state == .on
    )
}

/// 把一组 radio button 绑定为单选：点击任一按钮时把其他按钮置为 off。
/// 替代 macOS 11+ 的 NSButtonGroup，兼容项目默认 deployment target。
private final class RadioSyncCoordinator: NSObject {
    private let buttons: [NSButton]

    init(buttons: NSButton...) {
        self.buttons = buttons
        super.init()
        for button in buttons {
            button.target = self
            button.action = #selector(radioClicked(_:))
        }
    }

    convenience init(chinese: NSButton, english: NSButton) {
        self.init(buttons: chinese, english)
    }

    @objc private func radioClicked(_ sender: NSButton) {
        for button in buttons where button !== sender {
            button.state = .off
        }
    }
}

// MARK: - InputMethodManager (合并锁定 + 状态显示)

final class InputMethodManager: NSObject {

    // MARK: Config

    /// nil = 仅显示状态，不锁定
    private(set) var targetInputSourceID: String?

    /// 由用户在启动对话框中选择的初始中英文模式；nil 表示沿用默认推导（currentID==target → 中文）
    private var initialIsChinese: Bool? = nil

    // MARK: UI

    private let window: StatusOverlayWindow

    // MARK: State

    private var currentInputSourceID: String?
    private var isChineseMode: Bool = true

    /// 当前是否停留在目标输入法上。锁定模式下用于推导中/英默认状态。
    private var isOnTargetInputSource: Bool {
        guard let target = targetInputSourceID else { return false }
        return currentInputSourceID == target
    }

    // MARK: Shift tracking (CGEventTap)

    private var eventTap: CFMachPort?

    /// Shift 当前是否按住
    private var shiftHeld = false
    /// 标记：Shift 按下期间是否有其他按键被按下（大写字母/快捷键 → 不触发切换）
    private var otherKeyUsedWhileShift = false

    /// 左右 Shift 的 keyCode
    private let shiftKeyCodes: Set<Int64> = [56, 60]

    // MARK: Timer

    private var pollingTimer: Timer?
    private var cursorTrackTimer: Timer?

    // MARK: Init

    init(window: StatusOverlayWindow, targetInputSourceID: String?) {
        self.window = window
        self.targetInputSourceID = targetInputSourceID
        super.init()
    }

    /// 由 AppDelegate 在启动对话框结束后调用，把用户配置写入管理器。
    func configure(initialIsChinese: Bool) {
        self.initialIsChinese = initialIsChinese
    }

    /// 由 AppDelegate 在启动对话框结束后调用，覆盖要锁定的输入法 ID。
    func setTargetInputSourceID(_ id: String?) {
        self.targetInputSourceID = id
    }

    // MARK: Start

    func start() {
        // 初始显示
        if let id = getCurrentInputSourceID() {
            currentInputSourceID = id
            // 默认推导：当前就是目标输入法 → 中文；否则 → 英文
            var initial = isOnTargetInputSource
            // 用户在启动对话框中明确指定了初始状态时，用用户配置覆盖默认推导
            if let configured = initialIsChinese {
                initial = configured
            }
            isChineseMode = initial
        }
        updateDisplay()

        // TIS 输入源切换通知
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.onTick()
            }
        }

        // 统一轮询：状态更新 + 锁定
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.onTick()
        }

        // Shift 全局监听（flagsChanged + keyDown 区分单独 Shift 与 Shift+组合键）
        setupEventTap()

        // 光标位置跟踪 — 让悬浮窗始终跟随输入光标
        cursorTrackTimer = Timer.scheduledTimer(withTimeInterval: cursorTrackInterval, repeats: true) { [weak self] _ in
            self?.trackCursor()
        }
    }

    // MARK: Tick

    private func onTick() {
        guard let currentID = getCurrentInputSourceID() else { return }

        // ---- 锁定 ----
        if let target = targetInputSourceID, currentID != target {
            // 输入源偏离 → 切回去
            selectAndLockSource(target)
            return
        }

        // ---- 状态更新 ----
        if currentID != currentInputSourceID {
            // 输入源发生变化（用户可能手动切换了）
            currentInputSourceID = currentID
            // 切到目标（锁定）输入法 → 中文模式；切到其他 → 英文模式
            isChineseMode = isOnTargetInputSource
            updateDisplay()
        }
        // 如果输入源没变，isChineseMode 由 Shift 事件驱动，这里不覆盖
    }

    // MARK: Cursor tracking

    private func trackCursor() {
        let cursor = NSEvent.mouseLocation
        window.reposition(cursor: cursor)
    }

    // MARK: Locking

    private func selectAndLockSource(_ targetID: String) {
        // 列表在重试间隔内不会变化，只取一次
        guard let arr = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return }
        let count = CFArrayGetCount(arr)

        var retry = 0
        while retry < maxLockRetry {
            var found = false

            for i in 0..<count {
                let src = unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: TISInputSource.self)
                if let id = tisGetString(src, key: kTISPropertyInputSourceID), id == targetID {
                    found = true
                    if TISSelectInputSource(src) == noErr {
                        currentInputSourceID = targetID
                        // 切回目标输入法 → 中文模式（Shift 仍可切到英文）
                        isChineseMode = true
                        updateDisplay()
                        return
                    }
                    break
                }
            }

            if !found { return }
            retry += 1
            if retry < maxLockRetry {
                Thread.sleep(forTimeInterval: lockRetryDelay)
            }
        }
    }

    // MARK: Display

    private func updateDisplay() {
        // 所有调用点（start / onTick / handleFlagsChanged）都在主线程，
        // 无需再 dispatch 到主队列。
        if isChineseMode {
            window.showChinese()
        } else {
            window.showEnglish()
        }
    }

    // MARK: Event Tap

    private func setupEventTap() {
        // flagsChanged: 修饰键按下/释放时触发，能准确捕获 Shift 状态
        // keyDown: 用于检测 Shift 按下期间是否有其他按键（排除大写字母/快捷键）
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (_: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let mgr = Unmanaged<InputMethodManager>.fromOpaque(userInfo).takeUnretainedValue()
                mgr.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️  无法创建键盘监听 — 辅助功能权限未授予")
            print("   → 系统设置 → 隐私与安全性 → 辅助功能 → 勾选「终端」")
            print("   → 当前仅根据输入源判断中/英文（中文输入法内 Shift 切换不可感知）")
            return
        }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("✅ 键盘监听已启动（单独 Shift 切换可感知）")
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)

        case .keyDown:
            handleKeyDown(event)

        default:
            break
        }
    }

    /// 修饰键状态变化（Shift 按下/释放 在这里处理）
    private func handleFlagsChanged(_ event: CGEvent) {
        let raw = event.flags.rawValue
        let nowShift = (raw & UInt64(CGEventFlags.maskShift.rawValue)) != 0

        if nowShift && !shiftHeld {
            // Shift 刚按下
            shiftHeld = true
            otherKeyUsedWhileShift = false
        } else if !nowShift && shiftHeld {
            // Shift 刚释放
            if !otherKeyUsedWhileShift {
                // 单独按下 Shift → 输入法中英文切换
                if isChineseCapableInputSource(currentInputSourceID ?? "") {
                    isChineseMode.toggle()
                    updateDisplay()
                }
            }
            shiftHeld = false
            otherKeyUsedWhileShift = false
        }
    }

    /// 普通按键按下（用于排除 Shift+key 组合）
    private func handleKeyDown(_ event: CGEvent) {
        let flags = event.flags
        let isShiftPressed = flags.contains(.maskShift)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // 如果 Shift 按住，且当前按键不是 Shift 本身 → 组合键，不切换
        if isShiftPressed && !shiftKeyCodes.contains(keyCode) {
            otherKeyUsedWhileShift = true
        }
    }

    // MARK: Cleanup

    func cleanup() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        cursorTrackTimer?.invalidate()
        cursorTrackTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        window.close()
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    let manager: InputMethodManager
    let window: StatusOverlayWindow

    init(targetInputSourceID: String?) {
        let cursor = NSEvent.mouseLocation
        window = StatusOverlayWindow(initialCursor: cursor)
        manager = InputMethodManager(window: window, targetInputSourceID: targetInputSourceID)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window.orderFront(nil)

        // 命令行未提供目标输入法时弹初始化对话框；
        // 提供了则跳过弹框，直接进入锁定模式（快速通道）。
        if manager.targetInputSourceID == nil {
            guard let config = showInitDialog() else {
                // 用户取消：没有目标输入法也没法跑，直接退出
                print("👋 已取消，退出")
                NSApp.terminate(nil)
                return
            }
            manager.setTargetInputSourceID(config.targetInputSourceID)
            manager.configure(initialIsChinese: config.initialIsChinese)
        }

        manager.start()

        if let target = manager.targetInputSourceID {
            print("🔒 输入法锁定 + 状态显示")
            print("   目标: \(target)")
        } else {
            print("📊 仅输入法状态显示")
        }
        print("   悬浮窗 → 跟随光标右上角，Cmd+Q / Ctrl+C 退出")
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.cleanup()
        print("👋 已退出")
    }
}

// MARK: - Entry Point

autoreleasepool {
    let args = CommandLine.arguments

    // 可选参数：输入法 ID（提供 → 跳过弹框，直接锁定；不提供 → 弹框让用户选）
    let targetID: String? = args.count >= 2 ? args[1] : nil

    let app = NSApplication.shared
    let delegate = AppDelegate(targetInputSourceID: targetID)
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\n👋 收到退出信号")
        NSApp.terminate(nil)
    }

    app.run()
}
