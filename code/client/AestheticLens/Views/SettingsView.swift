import SwiftUI

/// 系统设置与偏好视图
/// 包含阿里云灵积 DashScope 视觉大模型配置、端侧双引擎诊断与隐藏调试面板
public struct SettingsView: View {
    @ObservedObject private var apiClient = APIClient.shared
    @State private var inputKey: String = ""
    @State private var testStatusText: String = ""
    @State private var isTesting: Bool = false
    @State private var showDebugSheet = false
    @Environment(\.presentationMode) var presentationMode
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                // 1. 阿里云视觉大模型配置 (用户重点需求)
                Section(header: Text("阿里云灵积 (DashScope) 视觉大模型"), footer: Text("用于驱动 Qwen-VL-Plus 多模态视觉大模型进行全景减法与黄金局部圈选。若未配置或处于离线/弱网环境，系统将自动无缝切换至端侧 Apple Vision 视觉神经引擎，100% 保证构图分析调用成功。")) {
                    SecureField("输入 DashScope API Key (sk-...)", text: $inputKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    HStack {
                        Button(action: handleTestConnection) {
                            if isTesting {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("正在测试连通性...")
                                }
                            } else {
                                Text("测试连接并保存")
                                    .fontWeight(.medium)
                            }
                        }
                        .disabled(isTesting || inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Spacer()
                        
                        if !inputKey.isEmpty {
                            Button("清空") {
                                inputKey = ""
                                apiClient.aliyunApiKey = ""
                                testStatusText = "已恢复使用内置高可用服务与端侧保底"
                            }
                            .foregroundColor(.red)
                        }
                    }
                    
                    if !testStatusText.isEmpty {
                        Text(testStatusText)
                            .font(.caption)
                            .foregroundColor(testStatusText.contains("成功") ? .green : (testStatusText.contains("失败") ? .red : .secondary))
                    }
                }
                
                // 2. 摄影与画质偏好
                Section(header: Text("摄影与构图偏好")) {
                    Toggle("60Hz 动态微动水平校准仪", isOn: .constant(true))
                    Toggle("AR 黄金电影取景框与角标", isOn: .constant(true))
                    Toggle("120Hz ProMotion 高刷取景生态", isOn: .constant(true))
                    Toggle("4K 60FPS 电影视频直录直出", isOn: .constant(true))
                }
                
                // 3. 隐私与数据安全
                Section(header: Text("隐私与安全")) {
                    Text("本应用严格遵守 Apple 隐私准则与 PIPL。取景抽帧仅在内存推理周期内驻留，服务端承诺绝不落盘、绝不存储、绝不做生物面部特征识别。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                // 4. 版本与彩蛋调试
                Section(footer: 
                    VStack(spacing: 8) {
                        Text("AestheticLens · AestheticLens-AI")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Version 2.0.0 (Build 20261008)")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                            .padding(.vertical, 4)
                            .onTapGesture(count: 3) {
                                self.showDebugSheet = true
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
                ) {
                    EmptyView()
                }
            }
            .navigationTitle("系统设置")
            .navigationBarItems(trailing: Button("完成") {
                presentationMode.wrappedValue.dismiss()
            })
            .sheet(isPresented: $showDebugSheet) {
                DebugSourceSheet()
            }
            .onAppear {
                self.inputKey = apiClient.aliyunApiKey
            }
        }
    }
    
    private func handleTestConnection() {
        let trimmed = inputKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isTesting = true
        testStatusText = "正在连接阿里云灵积服务器..."
        
        apiClient.testAliyunConnection(keyToTest: trimmed) { success, msg in
            self.isTesting = false
            self.testStatusText = msg
            if success {
                self.apiClient.aliyunApiKey = trimmed
            }
        }
    }
}
