import SwiftUI

/// 设置与偏好页面 (包含连续三击版本号弹出隐藏调试中台的手势)
public struct SettingsView: View {
    @State private var showDebugSheet = false
    @Environment(\.presentationMode) var presentationMode
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("摄影与构图偏好")) {
                    Toggle("60Hz 动态水平校准仪", isOn: .constant(true))
                    Toggle("AR 黄金构图引导线", isOn: .constant(true))
                    Toggle("电影级 3D LUT 实时预览", isOn: .constant(true))
                }
                
                Section(header: Text("隐私与安全")) {
                    Text("本应用严格遵守 Apple 隐私准则与 PIPL。取景抽帧与成片仅在内存推理周期内驻留，服务端承诺绝不落盘、绝不存储、绝不做面部特征识别。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Section(footer: 
                    VStack(spacing: 8) {
                        Text("灵瞳智拍 AestheticLens-AI")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // 统一触发口径：版本号文本连续三击弹出调试中台
                        Text("Version 2.0.0 (Build 20261005)")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                            .padding(.vertical, 4)
                            .onTapGesture(count: 3) {
                                // 连续三击版本号
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
        }
    }
}
