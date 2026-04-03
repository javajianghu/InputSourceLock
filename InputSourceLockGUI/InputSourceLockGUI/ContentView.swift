import SwiftUI
import Carbon.HIToolbox

struct ContentView: View {
    @State private var availableSources: [(id: String, name: String)] = []
    @State private var selectedSourceID: String = ""
    @State private var isMonitoring: Bool = false
    @State private var statusMessage: String = "未启动"
    @State private var switchCount: Int = 0
    @State private var monitor: InputSourceMonitor?
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("🔒 输入法锁定工具")
                .font(.title)
                .fontWeight(.bold)
            
            Divider()
            
            // 当前输入法显示
            HStack {
                Text("当前输入法:")
                    .fontWeight(.medium)
                Spacer()
                Text(currentInputSourceName())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 250, alignment: .trailing)
            }
            
            // 目标输入法选择
            VStack(alignment: .leading, spacing: 8) {
                Text("锁定到:")
                    .fontWeight(.medium)
                
                Picker("目标输入法", selection: $selectedSourceID) {
                    ForEach(availableSources, id: \.id) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 状态显示
            HStack {
                Circle()
                    .fill(isMonitoring ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(statusMessage)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 拦截统计
            if isMonitoring {
                HStack {
                    Image(systemName: "shield.fill")
                        .foregroundColor(.blue)
                    Text("已拦截 \(switchCount) 次 ABC 切换")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            // 控制按钮
            HStack(spacing: 20) {
                Button(action: refreshSources) {
                    Label("刷新列表", systemImage: "arrow.clockwise")
                }
                
                Button(action: toggleMonitoring) {
                    Label(
                        isMonitoring ? "停止监控" : "开始监控",
                        systemImage: isMonitoring ? "stop.fill" : "play.fill"
                    )
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSourceID.isEmpty)
            }
            
            // 使用说明
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 使用说明:")
                    .fontWeight(.bold)
                    .font(.caption)
                
                Text("• 从下拉菜单选择要锁定的输入法（如微信输入法）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• 点击「开始监控」后，程序会自动阻止切换到 ABC 输入法")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• 程序会在菜单栏显示 🔒 图标")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• 建议添加到登录项实现开机自启")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding(30)
        .onAppear {
            refreshSources()
            loadSavedConfiguration()
        }
    }
    
    func currentInputSourceName() -> String {
        guard let monitor = monitor ?? createMonitor(),
              let currentID = monitor.getCurrentInputSourceID() else {
            return "未知"
        }
        
        if let source = availableSources.first(where: { $0.id == currentID }) {
            return source.name
        }
        
        // 如果不在列表中，尝试直接获取名称
        return getDirectInputSourceName(currentID)
    }
    
    func getDirectInputSourceName(_ inputSourceID: String) -> String {
        guard let inputSourceArray = TISCreateInputSourceList(nil, false) as? [TISInputSource] else {
            return inputSourceID
        }
        
        for source in inputSourceArray {
            if let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) as String?,
               id == inputSourceID {
                if let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) as String? {
                    return name
                }
            }
        }
        
        return inputSourceID
    }
    
    func refreshSources() {
        let tempMonitor = InputSourceMonitor(targetInputSourceID: "")
        availableSources = tempMonitor.getAvailableInputSources()
        
        // 如果没有选中任何输入法，默认选中当前输入法
        if selectedSourceID.isEmpty,
           let currentID = tempMonitor.getCurrentInputSourceID() {
            selectedSourceID = currentID
        }
    }
    
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    func startMonitoring() {
        guard !selectedSourceID.isEmpty else { return }
        
        monitor = InputSourceMonitor(targetInputSourceID: selectedSourceID)
        
        // 保存配置
        UserDefaults.standard.set(selectedSourceID, forKey: "targetInputSourceID")
        
        // 启动监控
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.monitor?.startMonitoring(onSwitch: {
                self?.monitor?.selectInputSource(withID: self!.selectedSourceID)
                DispatchQueue.main.async {
                    self?.switchCount = self?.monitor?.getSwitchCount() ?? 0
                }
            })
        }
        
        isMonitoring = true
        statusMessage = "监控中 - 锁定到：\(getSourceName(selectedSourceID))"
    }
    
    func stopMonitoring() {
        monitor?.stopMonitoring()
        monitor = nil
        isMonitoring = false
        statusMessage = "未启动"
        switchCount = 0
    }
    
    func getSourceName(_ id: String) -> String {
        if let source = availableSources.first(where: { $0.id == id }) {
            return source.name
        }
        return id
    }
    
    func createMonitor() -> InputSourceMonitor {
        return InputSourceMonitor(targetInputSourceID: "")
    }
    
    func loadSavedConfiguration() {
        if let savedID = UserDefaults.standard.string(forKey: "targetInputSourceID") {
            selectedSourceID = savedID
        }
    }
}

#Preview {
    ContentView()
}
