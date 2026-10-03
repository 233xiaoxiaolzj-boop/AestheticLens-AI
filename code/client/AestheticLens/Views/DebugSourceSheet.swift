import SwiftUI

/// 隐藏调试与数据源切换面板 (现场演示防翻车双保险)
public struct DebugSourceSheet: View {
    @ObservedObject var apiClient = APIClient.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var customURLInput: String = "http://192.168.1.100:8000"
    @State private var isRegisteringToken: Bool = false
    @State private var registerStatusText: String = ""
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("实机演示数据源模式 (双保险)")) {
                    Picker("当前数据源", selection: $apiClient.currentMode) {
                        ForEach(DataSourceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if apiClient.currentMode == .mock {
                        Text("✅ 已切入本地离线模式：跳过网络请求与鉴权，直接读取内置黄金构图与调色数据桩，适合会场弱网演示。")
                            .font(.footnote)
                            .foregroundColor(.green)
                    } else {
                        Text("🌐 当前为云端在线模式：直连 Docker/Zeabur 容器微服务与阿里云百炼 VLM。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("服务端部署环境选择")) {
                    Picker("网络环境", selection: $apiClient.selectedEnv) {
                        ForEach(ServerEnvironment.allCases) { env in
                            Text(env.rawValue).tag(env)
                        }
                    }
                    
                    if apiClient.selectedEnv == .custom {
                        HStack {
                            Text("自定义地址")
                            TextField("http://IP:8000", text: $customURLInput, onCommit: {
                                apiClient.baseURL = customURLInput
                                apiClient.checkHealth()
                            })
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        }
                    }
                }
                
                Section(header: Text("云端网关连通性状态")) {
                    HStack {
                        Text("目标服务网关")
                        Spacer()
                        Text(apiClient.baseURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("健康探针 (/health)")
                        Spacer()
                        if apiClient.isHealthOk {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("在线 (200 OK)").foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text("离线 / 超时").foregroundColor(.red)
                            }
                        }
                    }
                    
                    HStack {
                        Text("JWT 令牌状态")
                        Spacer()
                        if apiClient.jwtToken != nil {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("已签发有效").foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 8, height: 8)
                                Text("未申请").foregroundColor(.orange)
                            }
                        }
                    }
                    
                    if !registerStatusText.isEmpty {
                        Text(registerStatusText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("立即测试连通并获取 Token") {
                        apiClient.checkHealth()
                        isRegisteringToken = true
                        registerStatusText = "正在请求设备注册..."
                        apiClient.registerDevice { result in
                            isRegisteringToken = false
                            switch result {
                            case .success(let token):
                                registerStatusText = "✅ Token 签发成功: \(token.prefix(12))..."
                            case .failure(let err):
                                registerStatusText = "❌ 注册失败: \(err.localizedDescription)"
                            }
                        }
                    }
                }
                
                Section(header: Text("客户端技术规格")) {
                    HStack {
                        Text("图形渲染管线")
                        Spacer()
                        Text("Metal 3D LUT (60fps)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("空间惯导传感器")
                        Spacer()
                        Text("CoreMotion (60Hz)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("编译版本")
                        Spacer()
                        Text("v2.0.0 (Phase 4 联调版)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("开发者与联调中台")
            .navigationBarItems(trailing: Button("完成") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
