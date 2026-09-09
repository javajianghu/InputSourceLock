import Cocoa
import ApplicationServices

/// 设置窗口：单页垂直布局（内容用 NSScrollView 包裹，超出窗口时可滚动）
/// 每个 section 是独立的卡片（圆角 + 浅边框 + 内边距），视觉上一目了然。
///
///   ┌──────────────────────────────┐
///   │ 当前状态                      │  ← 卡片
///   │ 输入法：xxx                  │
///   │ 中英文：xxx                  │
///   │ 锁定：  xxx                  │
///   ├──────────────────────────────┤  ← 间距
///   │ 锁定设置                      │  ← 卡片
///   │ 目标输入法：xxx              │
///   │ 初始状态：  xxx              │
///   ├──────────────────────────────┤
///   │ 悬浮窗                        │  ← 卡片
///   │ ☐ 显示状态悬浮窗              │
///   ├──────────────────────────────┤
///   │ 权限                          │  ← 卡片
///   │ ✅ 辅助功能：xxx              │
///   │ [打开系统设置] [刷新检测]      │
///   ├──────────────────────────────┤
///   │ 开机启动                      │  ← 卡片
///   │ ☐ 开机时自动启动              │
///   ├──────────────────────────────┤
///   │ 关于                          │  ← 卡片
///   │ 版本 / Bundle ID / 链接       │
///   └──────────────────────────────┘
final class SettingsWindowController: NSWindowController {

    private weak var manager: InputMethodManager?

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

    /// 已启用输入法缓存，供下拉框与状态区共用
    private var cachedSources: [(id: String, name: String)] = []

    /// 是否已经提示过「重启生效」，避免重复弹窗
    private var hasPromptedRestart = false

    init(manager: InputMethodManager) {
        self.manager = manager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "锁定中文输入法"
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 520, height: 500)

        super.init(window: window)
        window.contentView = buildContentView()

        refreshAll()

        // 状态变化 → 刷新「当前状态」卡片
        NotificationCenter.default.addObserver(
            forName: .inputMethodStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatusSection()
        }

        // 从系统设置返回时自动刷新辅助功能授权状态
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAccessibilityStatus()
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
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor

        // 内层 stack view（垂直堆叠各 section 卡片）
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 添加各 section（每个都是一张卡片）
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

        // 包装 scrollView 到 contentView
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

    // MARK: - Section Card Builder

    /// 创建一个卡片式 section 容器：浅背景 + 圆角 + 边框 + 内边距
    private func makeCard() -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        return card
    }

    /// 在卡片内堆叠：标题 + 内容区，返回用于 addArrangedSubview 的容器
    private func makeSectionCard(title: String, content: NSView) -> NSView {
        let card = makeCard()

        let header = NSTextField(labelWithString: title)
        header.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .labelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(header)

        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),

            content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        // 让卡片在 stack 中撑满宽度
        return card
    }

    // MARK: - Sections

    private func buildCurrentStatusSection() -> NSView {
        let imeLabel = makeFieldLabel("输入法：")
        let modeLabel = makeFieldLabel("中英文：")
        let lockLabel = makeFieldLabel("锁定：")
        for l in [imeLabel, modeLabel, lockLabel] {
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: 70).isActive = true
        }
        currentIMELabel.textColor = .secondaryLabelColor
        currentModeLabel.textColor = .secondaryLabelColor
        lockStatusLabel.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [imeLabel, currentIMELabel],
            [modeLabel, currentModeLabel],
            [lockLabel, lockStatusLabel]
        ])
        grid.columnSpacing = 16
        grid.rowSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        return makeSectionCard(title: "当前状态", content: grid)
    }

    private func buildLockSection() -> NSView {
        targetPopup.target = self
        targetPopup.action = #selector(handleTargetChanged)

        initialStatePopup.addItems(withTitles: ["跟随当前输入法", "中文", "英文"])
        initialStatePopup.target = self
        initialStatePopup.action = #selector(handleInitialStateChanged)

        let targetLabel = makeFieldLabel("目标输入法：")
        let initialLabel = makeFieldLabel("初始状态：")
        for l in [targetLabel, initialLabel] {
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: 90).isActive = true
        }
        targetPopup.translatesAutoresizingMaskIntoConstraints = false
        initialStatePopup.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [
            [targetLabel, targetPopup],
            [initialLabel, initialStatePopup]
        ])
        grid.columnSpacing = 16
        grid.rowSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            targetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            initialStatePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
        return makeSectionCard(title: "锁定设置", content: grid)
    }

    private func buildOverlaySection() -> NSView {
        overlayEnabledCheckbox.target = self
        overlayEnabledCheckbox.action = #selector(handleOverlayToggled)
        overlayEnabledCheckbox.state = UserDefaults.standard.bool(forKey: "overlayEnabled") ? .on : .off

        let content = NSStackView(views: [overlayEnabledCheckbox])
        content.orientation = .vertical
        content.alignment = .leading
        content.translatesAutoresizingMaskIntoConstraints = false
        return makeSectionCard(title: "悬浮窗", content: content)
    }

    private func buildPermissionsSection() -> NSView {
        accessibilityStatusLabel.textColor = .secondaryLabelColor
        accessibilityStatusLabel.maximumNumberOfLines = 2

        let refreshButton = NSButton(title: "刷新检测", target: self, action: #selector(handleRefreshPermissions))
        openAccessibilityButton.target = self
        openAccessibilityButton.action = #selector(handleOpenAccessibility)

        let buttonRow = NSStackView(views: [openAccessibilityButton, refreshButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [accessibilityStatusLabel, buttonRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        return makeSectionCard(title: "权限", content: content)
    }

    private func buildLaunchAtLoginSection() -> NSView {
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(handleLaunchAtLoginToggled)
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled() ? .on : .off

        let content = NSStackView(views: [launchAtLoginCheckbox])
        content.orientation = .vertical
        content.alignment = .leading
        content.translatesAutoresizingMaskIntoConstraints = false
        return makeSectionCard(title: "开机启动", content: content)
    }

    private func buildAboutSection() -> NSView {
        let about = NSTextField(wrappingLabelWithString:
            "锁定中文输入法 v1.0\nBundle ID: com.tang.LockChineseIME\n" +
            "GitHub: github.com/tang/input-dont-change\n" +
            "MIT 许可证"
        )
        about.font = NSFont.systemFont(ofSize: 11)
        about.textColor = .secondaryLabelColor
        about.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [about])
        content.orientation = .vertical
        content.alignment = .leading
        content.translatesAutoresizingMaskIntoConstraints = false
        return makeSectionCard(title: "关于", content: content)
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
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
        let tapActive = manager?.isEventTapActive ?? false

        if trusted && !tapActive {
            // 已授权但键盘监听还没装上 → 需要重启应用生效
            accessibilityStatusLabel.stringValue = "✅ 辅助功能：已授权（需重启应用生效）"
            accessibilityStatusLabel.textColor = .systemOrange
            maybePromptRestart()
        } else if trusted {
            accessibilityStatusLabel.stringValue = "✅ 辅助功能：已授权（Shift 检测可用）"
            accessibilityStatusLabel.textColor = .systemGreen
        } else {
            accessibilityStatusLabel.stringValue = "⚠️  辅助功能：未授权（无法检测输入法内部 Shift 切换）"
            accessibilityStatusLabel.textColor = .systemOrange
        }
    }

    /// 授权完成但监听未生效时，提示用户重启；可一键自动重启当前应用。
    private func maybePromptRestart() {
        guard !hasPromptedRestart else { return }
        hasPromptedRestart = true

        let alert = NSAlert()
        alert.messageText = "辅助功能已授权"
        alert.informativeText = "键盘监听（单独 Shift 检测）需要重启应用才能生效。现在重启吗？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            relaunchApp()
        }
    }

    /// 重启当前应用：先让 launchd 拉起一个新实例，再退出当前实例。
    private func relaunchApp() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try task.run()
        } catch {
            print("⚠️  自动重启失败：\(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
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
        manager?.setOverlayEnabled(enabled)
    }

    @objc private func handleRefreshPermissions() {
        refreshAccessibilityStatus()
    }

    @objc private func handleOpenAccessibility() {
        // 关键：只在「尚未授权」时才弹系统授权框。
        // 已授权时重复调用带 prompt 的 API 会把 TCC 授权重置，导致刚勾选又被取消。
        if !AXIsProcessTrustedWithOptions(nil) {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }
        refreshAccessibilityStatus()

        // 兜底：打开系统设置「辅助功能」页，方便手动勾选
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
}
