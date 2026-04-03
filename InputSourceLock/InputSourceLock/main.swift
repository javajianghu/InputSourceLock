import Cocoa
import Carbon.HIToolbox

/// 输入法锁定应用 - 主程序
class InputSourceMonitor {
    private var timer: Timer?
    private var lastInputSourceID: String?
    private var targetInputSourceID: String
    private let checkInterval: TimeInterval = 0.5
    
    init(targetInputSourceID: String) {
        self.targetInputSourceID = targetInputSourceID
        print("🎯 目标输入法 ID: \(targetInputSourceID)")
        print("⏱️  检测间隔：\(checkInterval)秒")
    }
    
    /// 获取所有可用的输入法列表
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
    
    /// 获取当前输入法 ID
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
    
    /// 切换到指定的输入法
    func selectInputSource(withID inputSourceID: String) -> Bool {
        guard let inputSourceArrayRef = TISCreateInputSourceList(nil, false) else {
            print("❌ 无法获取输入法列表")
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
                if result == noErr {
                    print("✅ 已切换到输入法：\(id)")
                    return true
                } else {
                    print("❌ 切换失败，错误码：\(result)")
                    return false
                }
            }
        }
        
        print("❌ 未找到输入法：\(inputSourceID)")
        return false
    }
    
    /// 开始监控
    func startMonitoring() {
        print("🚀 开始监控输入法...")
        print("💡 按 Ctrl+C 停止监控")
        
        lastInputSourceID = getCurrentInputSourceID()
        if let currentID = lastInputSourceID {
            print("📍 当前输入法：\(currentID)")
        }
        
        timer = Timer.scheduledTimer(timeInterval: checkInterval,
                                     target: self,
                                     selector: #selector(checkInputSource),
                                     userInfo: nil,
                                     repeats: true)
        
        RunLoop.current.run()
    }
    
    /// 检查输入法变化
    @objc private func checkInputSource() {
        guard let currentID = getCurrentInputSourceID() else {
            return
        }
        
        if currentID != lastInputSourceID {
            print("📍 检测到输入法变化：\(lastInputSourceID ?? "未知") → \(currentID)")
            
            if isABCInputSource(currentID) {
                print("⚠️  检测到 ABC 输入法，正在切换回目标输入法...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    _ = self?.selectInputSource(withID: self!.targetInputSourceID)
                }
            }
            
            lastInputSourceID = currentID
        }
    }
    
    /// 判断是否为 ABC 输入法
    private func isABCInputSource(_ inputSourceID: String) -> Bool {
        return inputSourceID.contains("ABC") || 
               inputSourceID.contains("com.apple.keylayout.US") ||
               inputSourceID == "com.apple.keylayout.ABC"
    }
    
    /// 停止监控
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        print("⏹️  监控已停止")
    }
}

/// 打印使用说明
func printUsage() {
    print("\n========================================")
    print("   macOS 输入法锁定工具 v1.0")
    print("========================================\n")
    
    let monitor = InputSourceMonitor(targetInputSourceID: "")
    let sources = monitor.getAvailableInputSources()
    
    print("📋 可用输入法列表:\n")
    for (index, source) in sources.enumerated() {
        print("  \(index + 1). \(source.name)")
        print("     ID: \(source.id)\n")
    }
    
    print("----------------------------------------")
    print("使用方法:")
    print("  ./InputSourceLock <目标输入法 ID>")
    print("\n示例:")
    print("  ./InputSourceLock com.tencent.inputmethod.WeChatIM.Pinyin")
    print("\n提示:")
    print("  - 复制上方显示的输入法 ID 作为参数")
    print("  - 按 Ctrl+C 停止程序")
    print("----------------------------------------\n")
}

// 主程序入口
func main() {
    let args = CommandLine.arguments
    
    if args.count < 2 {
        printUsage()
        exit(0)
    }
    
    let targetInputSourceID = args[1]
    
    print("\n🔒 输入法锁定工具启动中...")
    print("🎯 目标输入法：\(targetInputSourceID)\n")
    
    let monitor = InputSourceMonitor(targetInputSourceID: targetInputSourceID)
    
    signal(SIGINT) { _ in
        print("\n\n👋 收到退出信号，正在退出...")
        exit(0)
    }
    
    monitor.startMonitoring()
}

main()
