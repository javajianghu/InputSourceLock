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

extension Notification.Name {
    /// 输入法状态（当前输入源 / 中英文模式 / 锁定目标）变化时广播。
    /// 菜单栏图标与设置窗口都订阅此通知，避免单一回调互相覆盖。
    static let inputMethodStateDidChange = Notification.Name("com.tang.LockChineseIME.stateDidChange")
}

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
        orderFrontRegardless()
    }

    func showEnglish() {
        label.stringValue = "A"
        label.textColor = .white
        bgView.layer?.backgroundColor = NSColor(red: 0.22, green: 0.55, blue: 0.92, alpha: 0.82).cgColor
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}

// MARK: - InputMethodManager

/// 输入法锁定 + 中英文状态检测的核心管理器。
/// 持有悬浮窗、Cocoa 轮询 timer、CGEventTap。
final class InputMethodManager: NSObject {

    // MARK: Config

    private(set) var targetInputSourceID: String?
    /// 初始的中英文模式；nil 表示沿用默认推导（currentID==target → 中文）
    var initialIsChinese: Bool? {
        didSet { applyInitialStateIfNeeded() }
    }

    // MARK: UI

    private let window: StatusOverlayWindow

    // MARK: State

    private(set) var currentInputSourceID: String?
    private(set) var isChineseMode: Bool = true

    /// 当前是否停留在目标输入法上。锁定模式下用于推导中/英默认状态。
    var isOnTargetInputSource: Bool {
        guard let target = targetInputSourceID else { return false }
        return currentInputSourceID == target
    }

    // MARK: Shift tracking (CGEventTap)

    private var eventTap: CFMachPort?

    /// 键盘监听（event tap）是否已成功安装。
    /// 已授权但 event tap 未生效时，说明需要重启应用。
    var isEventTapActive: Bool { eventTap != nil }

    private var shiftHeld = false
    private var otherKeyUsedWhileShift = false
    private let shiftKeyCodes: Set<Int64> = [56, 60]

    // MARK: Timer

    private var pollingTimer: Timer?
    private var cursorTrackTimer: Timer?
    private var hasStarted = false

    /// 是否显示跟随光标的「中/A」悬浮窗
    private(set) var overlayEnabled: Bool = true

    // MARK: Init

    init(targetInputSourceID: String?) {
        let cursor = NSEvent.mouseLocation
        self.window = StatusOverlayWindow(initialCursor: cursor)
        self.targetInputSourceID = targetInputSourceID
        super.init()
    }

    func setTargetInputSourceID(_ id: String?) {
        targetInputSourceID = id
        // 切换目标后立即重新评估状态
        if let currentID = getCurrentInputSourceID() {
            currentInputSourceID = currentID
            isChineseMode = isOnTargetInputSource
            updateDisplay()
            notifyStateChange()
        }
    }

    // MARK: Start / Stop

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // 初始显示
        if let id = getCurrentInputSourceID() {
            currentInputSourceID = id
            var initial = isOnTargetInputSource
            if let configured = initialIsChinese {
                initial = configured
            }
            isChineseMode = initial
        }
        updateDisplay()
        notifyStateChange()

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

    // MARK: Overlay

    func setOverlayEnabled(_ enabled: Bool) {
        overlayEnabled = enabled
        if enabled {
            updateDisplay()
        } else {
            window.hide()
        }
    }

    // MARK: Tick

    private func onTick() {
        guard let currentID = getCurrentInputSourceID() else { return }

        // ---- 锁定 ----
        if let target = targetInputSourceID, currentID != target {
            selectAndLockSource(target)
            return
        }

        // ---- 状态更新 ----
        if currentID != currentInputSourceID {
            currentInputSourceID = currentID
            isChineseMode = isOnTargetInputSource
            updateDisplay()
            notifyStateChange()
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
                        isChineseMode = true
                        updateDisplay()
                        notifyStateChange()
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
        // 所有调用点（start / onTick / handleFlagsChanged）都在主线程
        guard overlayEnabled else {
            window.hide()
            return
        }
        if isChineseMode {
            window.showChinese()
        } else {
            window.showEnglish()
        }
    }

    /// 广播状态变化，让菜单栏图标与设置窗口各自刷新（替代易被覆盖的单回调）。
    private func notifyStateChange() {
        NotificationCenter.default.post(name: .inputMethodStateDidChange, object: self)
    }

    // MARK: Event Tap

    private func setupEventTap() {
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
            print("   → 系统设置 → 隐私与安全性 → 辅助功能 → 勾选「锁定中文输入法」")
            print("   → 当前仅根据输入源判断中/英文（输入法内部 Shift 切换不可感知）")
            notifyStateChange()
            return
        }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("✅ 键盘监听已启动（单独 Shift 切换可感知）")
        notifyStateChange()
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

    private func handleFlagsChanged(_ event: CGEvent) {
        let raw = event.flags.rawValue
        let nowShift = (raw & UInt64(CGEventFlags.maskShift.rawValue)) != 0

        if nowShift && !shiftHeld {
            shiftHeld = true
            otherKeyUsedWhileShift = false
        } else if !nowShift && shiftHeld {
            if !otherKeyUsedWhileShift {
                if isChineseCapableInputSource(currentInputSourceID ?? "") {
                    isChineseMode.toggle()
                    updateDisplay()
                    notifyStateChange()
                }
            }
            shiftHeld = false
            otherKeyUsedWhileShift = false
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        let flags = event.flags
        let isShiftPressed = flags.contains(.maskShift)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if isShiftPressed && !shiftKeyCodes.contains(keyCode) {
            otherKeyUsedWhileShift = true
        }
    }

    // MARK: Helpers

    private func applyInitialStateIfNeeded() {
        // 启动后用户修改 initialIsChinese 时的兜底（一般 start() 已处理）
        if let configured = initialIsChinese {
            isChineseMode = configured
            updateDisplay()
            notifyStateChange()
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
