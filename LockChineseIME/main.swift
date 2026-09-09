import Cocoa

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// SIGINT 兜底（开发期在终端运行时，Ctrl+C 能干净退出）
signal(SIGINT) { _ in
    print("\n👋 收到退出信号")
    DispatchQueue.main.async {
        NSApp.terminate(nil)
    }
}

app.run()
