import Cocoa
import Carbon.HIToolbox

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?
    var monitor: InputSourceMonitor?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建主窗口
        let contentView = ContentView()
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "输入法锁定工具"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        // 创建菜单栏图标
        setupStatusItem()
        
        // 加载上次的配置
        loadConfiguration()
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.title = "🔒"
            button.action = #selector(showWindow)
        }
        
        // 创建菜单
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示主窗口", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        monitor?.stopMonitoring()
        NSApp.terminate(nil)
    }
    
    func loadConfiguration() {
        // 从 UserDefaults 加载配置
        if let savedTarget = UserDefaults.standard.string(forKey: "targetInputSourceID") {
            print("已加载保存的配置：\(savedTarget)")
        }
    }
    
    func saveConfiguration(targetID: String) {
        UserDefaults.standard.set(targetID, forKey: "targetInputSourceID")
        print("已保存配置：\(targetID)")
    }
}

// MARK: - 输入法监控器
class InputSourceMonitor {
    private var timer: Timer?
    private var lastInputSourceID: String?
    private var targetInputSourceID: String
    private let checkInterval: TimeInterval = 0.3
    private var switchCount: Int = 0
    
    init(targetInputSourceID: String) {
        self.targetInputSourceID = targetInputSourceID
    }
    
    func getAvailableInputSources() -> [(id: String, name: String)] {
        var sources: [(id: String, name: String)] = []
        
        guard let inputSourceArray = TISCreateInputSourceList(nil, false) as? [TISInputSource] else {
            return sources
        }
        
        for source in inputSourceArray {
            if let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) as String?,
               let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) as String? {
                sources.append((id: id, name: name))
            }
        }
        
        return sources
    }
    
    func getCurrentInputSourceID() -> String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        guard let id = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) as String? else {
            return nil
        }
        
        return id
    }
    
    func selectInputSource(withID inputSourceID: String) -> Bool {
        guard let inputSourceArray = TISCreateInputSourceList(nil, false) as? [TISInputSource] else {
            return false
        }
        
        for source in inputSourceArray {
            if let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) as String?,
               id == inputSourceID {
                
                let result = TISSelectInputSource(source)
                return result == noErr
            }
        }
        
        return false
    }
    
    func startMonitoring(onSwitch: @escaping () -> Void) {
        lastInputSourceID = getCurrentInputSourceID()
        
        timer = Timer.scheduledTimer(timeInterval: checkInterval,
                                     target: self,
                                     selector: #selector(checkInputSource),
                                     userInfo: onSwitch,
                                     repeats: true)
        
        RunLoop.current.run()
    }
    
    @objc private func checkInputSource() {
        guard let currentID = getCurrentInputSourceID(),
              let callback = timer?.userInfo as? () -> Void else {
            return
        }
        
        if currentID != lastInputSourceID {
            // 检测是否切换到 ABC
            if isABCInputSource(currentID) {
                DispatchQueue.main.async {
                    callback()
                }
                switchCount += 1
            }
            lastInputSourceID = currentID
        }
    }
    
    private func isABCInputSource(_ inputSourceID: String) -> Bool {
        return inputSourceID.contains("ABC") || 
               inputSourceID.contains("com.apple.keylayout.US")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func getSwitchCount() -> Int {
        return switchCount
    }
}
