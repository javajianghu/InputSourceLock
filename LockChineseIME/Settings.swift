import Cocoa
import ApplicationServices

/// 设置窗口：单页垂直布局（内容用 NSScrollView 包裹，超出窗口时可滚动）
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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "锁定中文输入法"
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 480, height: 480)

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
        // 外层滚动视图
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // 内层 stack view
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 添加各 section
        stack.addArrangedSubview(buildCurrentStatusSection())
        stack.addArrangedSubview(buildLockSection())
        stack.addArrangedSubview(buildOverlaySection())
        stack.addArrangedSubview(buildPermissionsSection())
        stack.addArrangedSubview(buildLaunchAtLoginSection())
        stack.addArrangedSubview(buildAboutSection())

        // 让 stack 撑满 scrollView 的宽度
        scrollView.documentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        // 包装 scrollView
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    // MARK: - Sections

    private func buildCurrentStatusSection() -> NSView {
        let box = makeSectionBox(title: "当前状态")
        let grid = NSGridView(views: [
            [makeFieldLabel("输入法："), currentIMELabel],
            [makeFieldLabel("中英文："), currentModeLabel],
            [makeFieldLabel("锁定："), lockStatusLabel]
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        currentIMELabel.textColor = .secondaryLabelColor
        currentModeLabel.textColor = .secondaryLabelColor
        lockStatusLabel.textColor = .secondaryLabelColor
        box.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -4),
            grid.topAnchor.constraint(equalTo: box.topAnchor),
            grid.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    private func buildLockSection() -> NSView {
        let box = makeSectionBox(title: "锁定设置")

        targetPopup.target = self
        targetPopup.action = #selector(handleTargetChanged)
        rebuildTargetPopup()

        initialStatePopup.addItems(withTitles: ["跟随当前输入法", "中文", "英文"])
        initialStatePopup.target = self
        initialStatePopup.action = #selector(handleInitialStateChanged)

        let grid = NSGridView(views: [
            [makeFieldLabel("目标输入法："), targetPopup],
            [makeFieldLabel("初始状态："), initialStatePopup]
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -4),
            grid.topAnchor.constraint(equalTo: box.topAnchor),
            grid.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        // 让 popup 自适应宽度
        targetPopup.translatesAutoresizingMaskIntoConstraints = false
        initialStatePopup.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            targetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            initialStatePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])
        return box
    }

    private func buildOverlaySection() -> NSView {
        let box = makeSectionBox(title: "悬浮窗")
        overlayEnabledCheckbox.target = self
        overlayEnabledCheckbox.action = #selector(handleOverlayToggled)
        overlayEnabledCheckbox.state = UserDefaults.standard.bool(forKey: "overlayEnabled") ? .on : .off
        box.addSubview(overlayEnabledCheckbox)
        overlayEnabledCheckbox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlayEnabledCheckbox.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            overlayEnabledCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -4),
            overlayEnabledCheckbox.topAnchor.constraint(equalTo: box.topAnchor),
            overlayEnabledCheckbox.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    private func buildPermissionsSection() -> NSView {
        let box = makeSectionBox(title: "权限")

        accessibilityStatusLabel.textColor = .secondaryLabelColor
        accessibilityStatusLabel.maximumNumberOfLines = 2

        let refreshButton = NSButton(title: "刷新检测", target: self, action: #selector(handleRefreshPermissions))
        openAccessibilityButton.target = self
        openAccessibilityButton.action = #selector(handleOpenAccessibility)

        let buttonRow = NSStackView(views: [openAccessibilityButton, refreshButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [accessibilityStatusLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    private func buildLaunchAtLoginSection() -> NSView {
        let box = makeSectionBox(title: "开机启动")
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(handleLaunchAtLoginToggled)
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled() ? .on : .off
        box.addSubview(launchAtLoginCheckbox)
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            launchAtLoginCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -4),
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: box.topAnchor),
            launchAtLoginCheckbox.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    private func buildAboutSection() -> NSView {
        let box = makeSectionBox(title: "关于")
        let about = NSTextField(wrappingLabelWithString:
            "锁定中文输入法 v1.0\nBundle ID: com.tang.LockChineseIME\n" +
            "GitHub: github.com/tang/input-dont-change\n" +
            "MIT 许可证"
        )
        about.font = NSFont.systemFont(ofSize: 11)
        about.textColor = .secondaryLabelColor
        box.addSubview(about)
        about.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            about.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            about.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -4),
            about.topAnchor.constraint(equalTo: box.topAnchor),
            about.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    // MARK: - Section helpers

    private func makeSectionBox(title: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title)
        header.font = NSFont.boldSystemFont(ofSize: 13)
        header.textColor = .labelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
        // 内容区在 separator 下方 8px
        container.wantsLayer = true
        return container
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.alignment = .right
        return label
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
