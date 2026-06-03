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

// MARK: - InputMethodManager (合并锁定 + 状态显示)

final class InputMethodManager: NSObject {

    // MARK: Config

    let targetInputSourceID: String?   // nil = 仅显示状态，不锁定（public for AppDelegate）

    // MARK: UI

    private let window: StatusOverlayWindow

    // MARK: State

    private var currentInputSourceID: String?
    private var isChineseMode: Bool = true

    // MARK: Shift tracking (CGEventTap)

    private var eventTap: CFMachPort?
    private var hasEventTap = false

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

    // MARK: Start

    func start() {
        // 初始显示
        if let id = getCurrentInputSourceID() {
            currentInputSourceID = id
            // 切到目标（锁定）输入法 → 中文模式；切到其他 → 英文模式
            isChineseMode = (targetInputSourceID != nil && id == targetInputSourceID)
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

        // Shift / CapsLock 全局监听
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
            isChineseMode = (targetInputSourceID != nil && currentID == targetInputSourceID)
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
        var retry = 0
        while retry < maxLockRetry {
            guard let arr = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return }
            let count = CFArrayGetCount(arr)
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isChineseMode {
                self.window.showChinese()
            } else {
                self.window.showEnglish()
            }
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

        hasEventTap = true
        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("✅ 键盘监听已启动（Shift / CapsLock 切换可感知）")
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
        guard shiftHeld else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if !shiftKeyCodes.contains(code) {
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
        manager.start()

        if let target = manager.targetInputSourceID {
            print("🔒 输入法锁定 + 状态显示")
            print("   目标: \(target)")
        } else {
            print("📊 输入法状态显示")
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

    // 可选参数：输入法 ID（提供 → 锁定；不提供 → 仅状态显示）
    let targetID: String? = args.count >= 2 ? args[1] : nil

    // 无参数时列出可用输入法后退出（方便用户查看可用 ID）
    if targetID == nil {
        let sources = getAvailableInputSources()
        if !sources.isEmpty {
            print("📋 可用输入法:\n")
            for (i, s) in sources.enumerated() {
                print("  \(i + 1). \(s.name)")
                print("     ID: \(s.id)\n")
            }
        }
        print("用法: \(args[0]) [输入法ID]")
        print("  不带参数 → 仅显示状态悬浮窗")
        print("  带输入法ID → 锁定到该输入法 + 显示状态")
        print("\n示例:")
        print("  \(args[0])")
        print("  \(args[0]) com.tencent.inputmethod.wetype.pinyin")
        print("  \(args[0]) com.apple.keylayout.ABC")
    }

    let app = NSApplication.shared
    let delegate = AppDelegate(targetInputSourceID: targetID)
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\n👋 收到退出信号")
        NSApp.terminate(nil)
    }

    app.run()
}
