import Cocoa

/// 菜单栏图标 + 菜单控制器。
/// 图标动态显示当前中/英文状态（"中" / "A"）。
final class StatusBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private weak var manager: InputMethodManager?
    private var onOpenSettings: (() -> Void)?
    private var onQuit: (() -> Void)?

    // 状态行引用（menuNeedsUpdate 时直接更新）
    private var currentIMEItem: NSMenuItem!
    private var currentModeItem: NSMenuItem!
    private var lockStatusItem: NSMenuItem!

    private let chineseTitle = NSAttributedString(
        string: "中",
        attributes: [
            .foregroundColor: NSColor(red: 0.88, green: 0.28, blue: 0.24, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 14, weight: .bold)
        ]
    )

    private let englishTitle = NSAttributedString(
        string: "A",
        attributes: [
            .foregroundColor: NSColor(red: 0.22, green: 0.55, blue: 0.92, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 14, weight: .bold)
        ]
    )

    init(manager: InputMethodManager,
         onOpenSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.manager = manager
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.attributedTitle = englishTitle
        statusItem.menu = buildMenu()
        statusItem.menu?.delegate = self

        NotificationCenter.default.addObserver(
            forName: .inputMethodStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshIcon()
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 状态行（只读）
        let statusHeader = NSMenuItem(title: "当前状态", action: nil, keyEquivalent: "")
        statusHeader.isEnabled = false
        menu.addItem(statusHeader)

        currentIMEItem = NSMenuItem(title: "输入法：—", action: nil, keyEquivalent: "")
        currentIMEItem.isEnabled = false
        menu.addItem(currentIMEItem)

        currentModeItem = NSMenuItem(title: "中英文：—", action: nil, keyEquivalent: "")
        currentModeItem.isEnabled = false
        menu.addItem(currentModeItem)

        lockStatusItem = NSMenuItem(title: "锁定：—", action: nil, keyEquivalent: "")
        lockStatusItem.isEnabled = false
        menu.addItem(lockStatusItem)

        menu.addItem(NSMenuItem.separator())

        let openSettings = NSMenuItem(
            title: "打开设置…",
            action: #selector(handleOpenSettings),
            keyEquivalent: ","
        )
        openSettings.target = self
        menu.addItem(openSettings)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(
            title: "退出锁定中文输入法",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let mgr = manager else { return }

        if let id = mgr.currentInputSourceID {
            if let name = getAvailableInputSources().first(where: { $0.id == id })?.name {
                currentIMEItem.title = "输入法：\(name)"
            } else {
                currentIMEItem.title = "输入法：\(id)"
            }
        } else {
            currentIMEItem.title = "输入法：未知"
        }

        currentModeItem.title = "中英文：" + (mgr.isChineseMode ? "中文" : "英文")

        if let target = mgr.targetInputSourceID {
            let targetName = getAvailableInputSources().first(where: { $0.id == target })?.name ?? target
            lockStatusItem.title = "锁定：\(targetName)" + (mgr.isOnTargetInputSource ? "（已锁定）" : "（切回中）")
        } else {
            lockStatusItem.title = "锁定：未启用"
        }
    }

    // MARK: - Icon refresh

    private func refreshIcon() {
        guard let mgr = manager else { return }
        statusItem.button?.attributedTitle = mgr.isChineseMode ? chineseTitle : englishTitle
    }

    // MARK: - Actions

    @objc private func handleOpenSettings() {
        onOpenSettings?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}
