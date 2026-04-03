import Cocoa
import Carbon.HIToolbox

// 主应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?
    var monitor: InputSourceMonitor?
    
    // UI 组件
    var sourcePopup: NSPopUpButton!
    var statusLabel: NSTextField!
    var startStopButton: NSButton!
    
    var availableSources: [(id: String, name: String)] = []
    var isMonitoring: Bool = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        setupUI()
        refreshSources()
        loadConfiguration()
    }
    
    func setupWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "输入法锁定工具"
        window.makeKeyAndOrderFront(nil)
        
        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.title = "🔒"
            button.action = #selector(showWindow)
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示窗口", action: #selector(showWindow), keyEquivalent: ""))
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
    
    func setupUI() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
        window.contentView = contentView
        
        var yOffset = 185
        
        // 标题
        let titleLabel = NSTextField(labelWithString: "🔒 输入法锁定工具")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 22)
        titleLabel.frame = NSRect(x: 20, y: yOffset, width: 380, height: 30)
        contentView.addSubview(titleLabel)
        
        yOffset -= 40
        
        // 状态指示和开始/停止按钮（并排显示）
        let statusIndicator = NSView(frame: NSRect(x: 20, y: yOffset, width: 14, height: 14))
        statusIndicator.identifier = NSUserInterfaceItemIdentifier("statusIndicator")
        statusIndicator.wantsLayer = true
        statusIndicator.layer?.backgroundColor = NSColor.red.cgColor
        statusIndicator.layer?.cornerRadius = 7
        contentView.addSubview(statusIndicator)
        
        statusLabel = NSTextField(labelWithString: "未启动")
        statusLabel.font = NSFont.systemFont(ofSize: 14)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.frame = NSRect(x: 42, y: yOffset, width: 160, height: 22)
        contentView.addSubview(statusLabel)
        
        startStopButton = NSButton(title: "开始监控", target: self, action: #selector(toggleMonitoring))
        startStopButton.frame = NSRect(x: 220, y: yOffset - 2, width: 180, height: 32)
        startStopButton.bezelStyle = .rounded
        startStopButton.bezelColor = NSColor.systemGreen
        startStopButton.contentTintColor = NSColor.white
        startStopButton.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        contentView.addSubview(startStopButton)
        
        yOffset -= 50
        
        // 分隔线
        let line = NSView(frame: NSRect(x: 20, y: yOffset, width: 380, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.lightGray.cgColor
        contentView.addSubview(line)
        
        yOffset -= 45
        
        // 目标输入法选择
        let targetLabel = NSTextField(labelWithString: "锁定到:")
        targetLabel.font = NSFont.systemFont(ofSize: 14)
        targetLabel.frame = NSRect(x: 20, y: yOffset, width: 80, height: 22)
        contentView.addSubview(targetLabel)
        
        sourcePopup = NSPopUpButton(frame: NSRect(x: 110, y: yOffset, width: 290, height: 26))
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged)
        contentView.addSubview(sourcePopup)
        
        // 启动定时器更新当前输入法
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateCurrentInput), userInfo: nil, repeats: true)
    }
    
    @objc func updateCurrentInput() {
        guard let currentID = monitor?.getCurrentInputSourceID() else { return }
        
        if let currentValueLabel = window.contentView?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("currentValue") }) as? NSTextField {
            
            if let source = availableSources.first(where: { $0.id == currentID }) {
                currentValueLabel.stringValue = source.name
            } else {
                currentValueLabel.stringValue = getDirectInputSourceName(currentID)
            }
        }
    }
    
    @objc func sourceChanged() {
        // 保存选择
    }
    
    @objc func refreshSources() {
        let tempMonitor = InputSourceMonitor(targetInputSourceID: "")
        availableSources = tempMonitor.getAvailableInputSources()
        
        sourcePopup.removeAllItems()
        for source in availableSources {
            sourcePopup.addItem(withTitle: "\(source.name) (\(source.id))")
        }
        
        // 默认选中当前输入法
        if let currentID = tempMonitor.getCurrentInputSourceID(),
           let index = availableSources.firstIndex(where: { $0.id == currentID }) {
            sourcePopup.selectItem(at: index)
        }
    }
    
    @objc func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    func startMonitoring() {
        guard let selectedSource = getSelectedSource() else { return }
        
        monitor = InputSourceMonitor(targetInputSourceID: selectedSource.id)
        UserDefaults.standard.set(selectedSource.id, forKey: "targetInputSourceID")
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            DispatchQueue.main.async {
                self?.monitor?.startMonitoring(onSwitch: {
                    self?.monitor?.selectInputSource(withID: selectedSource.id)
                })
            }
        }
        
        isMonitoring = true
        startStopButton.title = "停止监控"
        startStopButton.bezelColor = NSColor.systemRed
        statusLabel.stringValue = "监控中"
        
        if let indicator = window.contentView?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("statusIndicator") }) {
            indicator.wantsLayer = true
            indicator.layer?.backgroundColor = NSColor.green.cgColor
        }
    }
    
    func stopMonitoring() {
        monitor?.stopMonitoring()
        monitor = nil
        isMonitoring = false
        startStopButton.title = "开始监控"
        startStopButton.bezelColor = NSColor.systemGreen
        statusLabel.stringValue = "未启动"
        
        if let indicator = window.contentView?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("statusIndicator") }) {
            indicator.wantsLayer = true
            indicator.layer?.backgroundColor = NSColor.red.cgColor
        }
    }
    
    func getSelectedSource() -> (id: String, name: String)? {
        let selectedIndex = sourcePopup.indexOfSelectedItem
        if selectedIndex >= 0 && selectedIndex < availableSources.count {
            return availableSources[selectedIndex]
        }
        return nil
    }
    
    func getDirectInputSourceName(_ inputSourceID: String) -> String {
        guard let inputSourceArrayRef = TISCreateInputSourceList(nil, false) else {
            return inputSourceID
        }
        
        let inputSourceArray = inputSourceArrayRef.takeRetainedValue()
        let count = CFArrayGetCount(inputSourceArray)
        
        for i in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(inputSourceArray, i), to: TISInputSource.self)
            
            if let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
               let id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String?,
               id == inputSourceID {
                if let namePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName),
                   let name = Unmanaged<CFString>.fromOpaque(namePointer).takeUnretainedValue() as String? {
                    return name
                }
            }
        }
        
        return inputSourceID
    }
    
    func loadConfiguration() {
        if let savedID = UserDefaults.standard.string(forKey: "targetInputSourceID"),
           let index = availableSources.firstIndex(where: { $0.id == savedID }) {
            sourcePopup.selectItem(at: index)
        }
    }
}

// MARK: - 输入法监控器
class InputSourceMonitor {
    private var timer: Timer?
    private var lastInputSourceID: String?
    private var targetInputSourceID: String
    private let checkInterval: TimeInterval = 0.3
    
    init(targetInputSourceID: String) {
        self.targetInputSourceID = targetInputSourceID
    }
    
    func getAvailableInputSources() -> [(id: String, name: String)] {
        var sources: [(id: String, name: String)] = []
        
        guard let inputSourceArrayRef = TISCreateInputSourceList(nil, false) else {
            return sources
        }
        
        let inputSourceArray = inputSourceArrayRef.takeRetainedValue()
        let count = CFArrayGetCount(inputSourceArray)
        
        for i in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(inputSourceArray, i), to: TISInputSource.self)
            
            if let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
               let id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String?,
               let namePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName),
               let name = Unmanaged<CFString>.fromOpaque(namePointer).takeUnretainedValue() as String? {
                sources.append((id: id, name: name))
            }
        }
        
        return sources
    }
    
    func getCurrentInputSourceID() -> String? {
        guard let inputSourceRef = TISCopyCurrentKeyboardInputSource() else {
            return nil
        }
        
        let inputSource = inputSourceRef.takeRetainedValue()
        
        guard let idPointer = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }
        
        let id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
        return id
    }
    
    func selectInputSource(withID inputSourceID: String) -> Bool {
        guard let inputSourceArrayRef = TISCreateInputSourceList(nil, false) else {
            return false
        }
        
        let inputSourceArray = inputSourceArrayRef.takeRetainedValue()
        let count = CFArrayGetCount(inputSourceArray)
        
        for i in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(inputSourceArray, i), to: TISInputSource.self)
            
            if let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
               let id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String?,
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
    }
    
    @objc private func checkInputSource() {
        guard let currentID = getCurrentInputSourceID(),
              let callback = timer?.userInfo as? () -> Void else {
            return
        }
        
        if currentID != lastInputSourceID {
            if isABCInputSource(currentID) {
                DispatchQueue.main.async {
                    callback()
                }
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
}

// 主程序入口
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
