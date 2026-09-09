import Foundation
import ServiceManagement

/// 开机启动封装（macOS 13+ 使用 SMAppService.mainApp）
/// 注意：SMAppService 需要应用位于 /Applications 才能稳定工作；
/// 开发期间从 build/ 目录运行时也能注册，但状态可能不准。
enum LaunchAtLogin {

    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册失败时返回 false；调用方应提示用户去系统设置查看。
    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            print("⚠️  注册开机启动失败：\(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    static func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            print("⚠️  取消开机启动失败：\(error.localizedDescription)")
            return false
        }
    }
}
