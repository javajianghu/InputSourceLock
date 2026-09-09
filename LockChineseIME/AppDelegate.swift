import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var manager: InputMethodManager!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController?

    /// 用户是否已经看过首次启动设置窗口
    private let hasShownFirstRunKey = "hasShownFirstRun_v1"
    /// 首次启动时根据这个 key 决定要不要弹设置
    ///   "1" → 已看过，以后不再自动弹
    ///   "0" / 不存在 → 首次启动，自动弹
    private var isFirstRun: Bool {
        !UserDefaults.standard.bool(forKey: hasShownFirstRunKey)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 关键：必须是 .regular 才能同时显示在 Dock 和菜单栏
        NSApp.setActivationPolicy(.regular)

        // 核心管理器（不锁定任何输入法，让用户在设置里选）
        manager = InputMethodManager(targetInputSourceID: nil)

        // 菜单栏
        statusBar = StatusBarController(
            manager: manager,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { [weak self] in self?.quitApp() }
        )

        // 启动后台工作
        manager.start()
        applyOverlayEnabledFromDefaults()

        // 首次启动：弹设置；之后：仅菜单栏/Dock 图标
        if isFirstRun {
            UserDefaults.standard.set(true, forKey: hasShownFirstRunKey)
            // 延后一点弹，避免与启动动画抢焦点
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.openSettings()
            }
        }

        // Dock 点击 → 打开设置（通过 reopen 处理）
        print("🚀 锁定中文输入法已启动")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock 图标被点击：弹出设置
        openSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关掉设置窗口不退出应用（菜单栏图标负责生命周期）
        return false
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(manager: manager)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func applyOverlayEnabledFromDefaults() {
        // 默认开启悬浮窗；尊重用户之前的关闭选择
        let enabled = UserDefaults.standard.object(forKey: "overlayEnabled") as? Bool ?? true
        manager.setOverlayEnabled(enabled)
    }

    // MARK: - Quit

    private func quitApp() {
        print("👋 退出锁定中文输入法")
        NSApp.terminate(nil)
    }

    // 处理 SIGINT（终端启动时仍可能收到）
    func applicationWillTerminate(_ notification: Notification) {
        manager?.cleanup()
    }
}
