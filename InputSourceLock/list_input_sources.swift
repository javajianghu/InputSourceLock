#!/usr/bin/env swift
import Cocoa
import Carbon.HIToolbox

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

// 主程序
print("\n========================================")
print("   macOS 输入法查询工具")
print("========================================\n")

let sources = getAvailableInputSources()

print("📋 可用输入法列表:\n")
for (index, source) in sources.enumerated() {
    print("  \(index + 1). \(source.name)")
    print("     ID: \(source.id)\n")
}

print("----------------------------------------")
if let currentID = getCurrentInputSourceID() {
    print("✅ 当前输入法 ID: \(currentID)")
    
    if let currentSource = sources.first(where: { $0.id == currentID }) {
        print("   名称：\(currentSource.name)")
    }
} else {
    print("❌ 无法获取当前输入法")
}
print("----------------------------------------\n")

print("💡 提示:")
print("   - 微信输入法的 ID 通常包含 'tencent' 或 'WeChat' 或 'wetype'")
print("   - 复制上方显示的输入法 ID 用于锁定工具")
print("   - 如果看不到微信输入法，请确保已安装并启用了微信输入法\n")
