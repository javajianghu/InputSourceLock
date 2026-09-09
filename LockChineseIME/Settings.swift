import Cocoa
import ApplicationServices

/// 设置窗口：单页垂直滚动布局
///   ┌──────────────────────────────┐
///   │ 当前状态                      │
///   │ 输入法 / 中英文 / 锁定         │
///   ├──────────────────────────────┤
///   │ 锁定设置                      │
///   │ 目标输入法 + 初始状态          │
///   ├──────────────────────────────┤
///   │ 悬浮窗                        │
///   │ 启用切换                      │
///   ├──────────────────────────────┤
///   │ 权限                          │
///   │ 辅助功能状态 + 打开设置按钮    │
///   ├──────────────────────────────┤
///   │ 开机启动                      │
///   │ 启用切换                      │
///   ├──────────────────────────────┤
///   │ 关于                          │
///   │ 版本 / Bundle ID / 链接       │
///   └──────────────────────────────┘
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private weak var manager: InputMethodManager?
    private var statusBarRef: StatusBarController?

    // 控件引用（便于后续更新状态）
    private let currentIMELabel = NSTextField(labelWithString: "—")
    private let currentModeLabel = NSTextField(labelWithString: "—")
    private let lockStatusLabel = NSTextField(labelWithString: "—")
    private let targetPopup = NSPopUpButton(frame: .zero)
    private let initialStatePopup = NSPopUpButton(frame: .zero)
    private let overlayEnabledCheckbox = NSButton(checkboxWithTitle: "显示状态悬浮窗（跟随光标）", target: nil, action: nil)
    private let accessibilityStatusLabel = NSTextField(labelWithString: "—")
    private let openAccessibilityButton = NSButton(title: "打开系统设置", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "开机时自动启动", target: nil, action: nil)

    /// 启动时间记录，用于"目标输入法"显示 ID 区分
    private var cachedSources: [(id: String, name: String)] = []

    /// 关闭按钮不退出应用（菜单栏图标负责生命周期）
    var onCloseRequested: (() -> Void)?

    init(manager: InputMethodManager, statusBar: StatusBarController) {
        self.manager = manager
        self.statusBarRef = statusBar

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "锁定中文输入法"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentView = buildContentView()

        refreshAll()
        manager.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.refreshStatusSection() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 560))

        var y: CGFloat = 20
        let leftPadding: CGFloat = 20
        let labelWidth: CGFloat = 100
        let fieldWidth: CGFloat = 280

        // —— 当前状态 ——
        y = addSectionHeader("当前状态", into: container, atY: y)
        y = addKeyValue("输入法：", valueLabel: currentIMELabel, into: container, atY: y,
                        leftPadding: leftPadding, labelWidth: labelWidth)
        y = addKeyValue("中英文：", valueLabel: currentModeLabel, into: container, atY: y,
                        leftPadding: leftPadding, labelWidth: labelWidth)
        y = addKeyValue("锁定：", valueLabel: lockStatusLabel, into: container, atY: y,
                        leftPadding: leftPadding, labelWidth: labelWidth)
        y -= 10

        // —— 锁定设置 ——
        y = addSectionHeader("锁定设置", into: container, atY: y)

        let targetLabel = NSTextField(labelWithString: "目标输入法：")
        targetLabel.frame = NSRect(x: leftPadding, y: y - 4, width: labelWidth, height: 20)
        container.addSubview(targetLabel)

        targetPopup.frame = NSRect(x: leftPadding + labelWidth, y: y - 4, width: fieldWidth, height: 26)
        targetPopup.target = self
        targetPopup.action = #selector(handleTargetChanged)
        rebuildTargetPopup()
        container.addSubview(targetPopup)
        y -= 32

        let initialLabel = NSTextField(labelWithString: "初始状态：")
        initialLabel.frame = NSRect(x: leftPadding, y: y - 4, width: labelWidth, height: 20)
        container.addSubview(initialLabel)

        initialStatePopup.frame = NSRect(x: leftPadding + labelWidth, y: y - 4, width: fieldWidth, height: 26)
        initialStatePopup.addItems(withTitles: ["跟随当前输入法", "中文", "英文"])
        initialStatePopup.target = self
        initialStatePopup.action = #selector(handleInitialStateChanged)
        container.addSubview(initialStatePopup)
        y -= 40

        // —— 悬浮窗 ——
        y = addSectionHeader("悬浮窗", into: container, atY: y)
        overlayEnabledCheckbox.frame = NSRect(x: leftPadding, y: y - 4, width: 360, height: 20)
        overlayEnabledCheckbox.target = self
        overlayEnabledCheckbox.action = #selector(handleOverlayToggled)
        overlayEnabledCheckbox.state = UserDefaults.standard.bool(forKey: "overlayEnabled") ? .on : .off
        container.addSubview(overlayEnabledCheckbox)
        y -= 32

        // —— 权限 ——
        y = addSectionHeader("权限", into: container, atY: y)
        accessibilityStatusLabel.frame = NSRect(x: leftPadding, y: y - 4, width: fieldWidth, height: 20)
        container.addSubview(accessibilityStatusLabel)

        openAccessibilityButton.frame = NSRect(x: leftPadding, y: y - 32, width: 140, height: 28)
        openAccessibilityButton.target = self
        openAccessibilityButton.action = #selector(handleOpenAccessibility)
        container.addSubview(openAccessibilityButton)

        let refreshButton = NSButton(title: "刷新检测", target: self, action: #selector(handleRefreshPermissions))
        refreshButton.frame = NSRect(x: leftPadding + 150, y: y - 32, width: 100, height: 28)
        container.addSubview(refreshButton)
        y -= 70

        // —— 开机启动 ——
        y = addSectionHeader("开机启动", into: container, atY: y)
        launchAtLoginCheckbox.frame = NSRect(x: leftPadding, y: y - 4, width: 360, height: 20)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(handleLaunchAtLoginToggled)
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled() ? .on : .off
        container.addSubview(launchAtLoginCheckbox)
        y -= 40

        // —— 关于 ——
        y = addSectionHeader("关于", into: container, atY: y)
        let about = NSTextField(wrappingLabelWithString:
            "锁定中文输入法 v1.0\nBundle ID: com.tang.LockChineseIME\n" +
            "GitHub: github.com/tang/input-dont-change\n" +
            "MIT 许可证"
        )
        about.frame = NSRect(x: leftPadding, y: y - 80, width: 420, height: 80)
        about.font = NSFont.systemFont(ofSize: 11)
        about.textColor = .secondaryLabelColor
        container.addSubview(about)

        return container
    }

    private func addSectionHeader(_ title: String, into container: NSView, atY y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: y - 4, width: 420, height: 22)
        label.font = NSFont.boldSystemFont(ofSize: 13)
        label.textColor = .labelColor
        container.addSubview(label)

        let separator = NSBox(frame: NSRect(x: 20, y: y - 10, width: 420, height: 1))
        separator.boxType = .separator
        container.addSubview(separator)
        return y - 28
    }

    private func addKeyValue(_ key: String, valueLabel: NSTextField,
                             into container: NSView, atY y: CGFloat,
                             leftPadding: CGFloat, labelWidth: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: key)
        label.frame = NSRect(x: leftPadding, y: y - 4, width: labelWidth, height: 20)
        container.addSubview(label)

        valueLabel.frame = NSRect(x: leftPadding + labelWidth, y: y - 4, width: 300, height: 20)
        valueLabel.textColor = .secondaryLabelColor
        container.addSubview(valueLabel)
        return y - 26
    }

    // MARK: - Refresh

    private func refreshAll() {
        cachedSources = getAvailableInputSources()
        rebuildTargetPopup()
        refreshStatusSection()
        refreshAccessibilityStatus()
    }

    private func refreshStatusSection() {
        guard let mgr = manager else { return }
        if let id = mgr.currentInputSourceID {
            let name = cachedSources.first(where: { $0.id == id })?.name ?? id
            currentIMELabel.stringValue = "\(name)（\(id)）"
        } else {
            currentIMELabel.stringValue = "未知"
        }
        currentModeLabel.stringValue = mgr.isChineseMode ? "中文" : "英文"
        if let target = mgr.targetInputSourceID {
            let targetName = cachedSources.first(where: { $0.id == target })?.name ?? target
            lockStatusLabel.stringValue = targetName + (mgr.isOnTargetInputSource ? "（已锁定）" : "（切回中）")
        } else {
            lockStatusLabel.stringValue = "未启用锁定"
        }
    }

    private func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrustedWithOptions(nil)
        accessibilityStatusLabel.stringValue = trusted
            ? "✅ 辅助功能：已授权（Shift 检测可用）"
            : "⚠️  辅助功能：未授权（无法检测输入法内部 Shift 切换）"
        accessibilityStatusLabel.textColor = trusted ? .systemGreen : .systemOrange
    }

    private func rebuildTargetPopup() {
        targetPopup.removeAllItems()
        targetPopup.addItem(withTitle: "（不锁定，仅显示状态）")
        for source in cachedSources {
            targetPopup.addItem(withTitle: "\(source.name)（\(source.id)）")
        }
        // 同步当前 target
        if let target = manager?.targetInputSourceID,
           let idx = cachedSources.firstIndex(where: { $0.id == target }) {
            targetPopup.selectItem(at: idx + 1)
        } else {
            targetPopup.selectItem(at: 0)
        }
    }

    // MARK: - Actions

    @objc private func handleTargetChanged() {
        let idx = targetPopup.indexOfSelectedItem
        let newTarget: String?
        if idx <= 0 {
            newTarget = nil
        } else {
            let realIdx = idx - 1
            newTarget = realIdx < cachedSources.count ? cachedSources[realIdx].id : nil
        }
        manager?.setTargetInputSourceID(newTarget)
        refreshStatusSection()
    }

    @objc private func handleInitialStateChanged() {
        switch initialStatePopup.indexOfSelectedItem {
        case 1: manager?.initialIsChinese = true
        case 2: manager?.initialIsChinese = false
        default: manager?.initialIsChinese = nil
        }
    }

    @objc private func handleOverlayToggled() {
        let enabled = overlayEnabledCheckbox.state == .on
        UserDefaults.standard.set(enabled, forKey: "overlayEnabled")
        // 悬浮窗始终由 manager 显示/隐藏
        if enabled {
            manager?.start()
        }
    }

    @objc private func handleRefreshPermissions() {
        refreshAccessibilityStatus()
    }

    @objc private func handleOpenAccessibility() {
        // 跳到系统设置的辅助功能页
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleLaunchAtLoginToggled() {
        let wantEnable = launchAtLoginCheckbox.state == .on
        let success = wantEnable ? LaunchAtLogin.enable() : LaunchAtLogin.disable()
        if !success {
            // 回滚 UI 状态
            launchAtLoginCheckbox.state = wantEnable ? .off : .on
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onCloseRequested?()
    }
}
