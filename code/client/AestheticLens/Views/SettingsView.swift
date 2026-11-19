import SwiftUI

/// 系统设置与偏好视图
/// 包含真实生效的取景辅助开关、阿里云灵积 DashScope 视觉大模型配置与隐藏调试面板
public struct SettingsView: View {
    @ObservedObject private var apiClient = APIClient.shared
    @AppStorage("showLevelGauge") private var showLevelGauge: Bool = true
    @AppStorage("showAspectGrid") private var showAspectGrid: Bool = false
    @AppStorage("preserveOriginalHDR") private var preserveOriginalHDR: Bool = true
    
    @State private var inputKey: String = ""
    @State private var testStatusText: String = ""
    @State private var isTesting: Bool = false
    @State private var showDebugSheet = false
    @Environment(\.presentationMode) var presentationMode
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                // 1. 摄影与取景辅助 (全部真实持久化生效)
                Section(header: Text("取景与画质偏好"), footer: Text("开启“原画无损直存”时，使用 00-原画 拍摄且不裁剪画幅将直接保留手机原生 HEIF/Smart HDR 与全部 EXIF 数据。")) {
                    Toggle("实时陀螺仪水平仪", isOn: $showLevelGauge)
                    Toggle("取景器三分线辅助网格", isOn: $showAspectGrid)
                    Toggle("00-原画无损直存 (保留原生 HDR/EXIF)", isOn: $preserveOriginalHDR)
                }
                
                // 2. 阿里云视觉大模型配置
                Section(header: Text("阿里云灵积 (DashScope) 视觉大模型"), footer: Text("用于驱动 Qwen-VL-Plus 多模态视觉大模型进行实时分析。若未配置或处于离线/弱网环境，系统将自动切换至端侧 Apple Vision。")) {
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
                                testStatusText = "已清空 API Key，将使用端侧本地分析"
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
                
                // 3. 隐私与数据安全
                Section(header: Text("隐私与安全")) {
                    Text("本应用严格遵守 Apple 隐私准则与 PIPL。取景抽帧仅在内存推理周期内驻留，不做本地落盘或生物面部特征留存。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                // 4. 版本与调试面板入口
                Section(footer:
                    VStack(spacing: 8) {
                        Text("AestheticLens · 灵瞳相机")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Version 2.1.0 (连击三次打开联调中台)")
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