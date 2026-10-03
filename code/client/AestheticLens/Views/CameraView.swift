import SwiftUI

/// 取景器全屏主视图 (集成 Metal 渲染、60Hz 水平仪、AR 构图导航与拍后调色工作台联动)
public struct CameraView: View {
    @ObservedObject var cameraManager = CameraManager.shared
    @ObservedObject var motionManager = MotionManager.shared
    @ObservedObject var apiClient = APIClient.shared
    
    @State private var currentGuidance: CompositionGuidance? = nil
    @State private var currentFilterRec: FilterRecommendation? = nil
    @State private var showSettings: Bool = false
    @State private var showRetouch: Bool = false
    @State private var showVideoRetouch: Bool = false
    @State private var isFlashing: Bool = false
    @State private var captureMode: Int = 0 // 0: 照片模式, 1: 录像调色模式
    @State private var activeLutName: String = "自然原画"
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 1. 底层：Metal 零拷贝原生取景渲染器 (锁定 60fps)
            if cameraManager.isAuthorized {
                MetalView()
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        cameraManager.startSession()
                    }
                    .onDisappear {
                        cameraManager.stopSession()
                    }
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("请授予相机访问权限以开启实时构图辅助")
                        .foregroundColor(.white)
                        .font(.subheadline)
                    Button("前往系统设置开启") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                }
            }
            
            // 2. 中层：60Hz 微光绿色动态水平仪 HUD
            LevelGaugeView()
            
            // 3. 顶层：AR 构图框与空间机位 4 向导航箭头
            NavigationOverlayView(guidance: currentGuidance)
            
            // 4. 界面控件层 (顶部状态栏、底部快门与滤镜)
            VStack {
                // 顶部状态栏
                HStack {
                    // 数据源微标 (实时提醒当前是在线还是本地 Mock)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(apiClient.currentMode == .mock ? Color.green : Color.blue)
                            .frame(width: 6, height: 6)
                        Text(apiClient.currentMode == .mock ? "离线 Mock 模式" : "在线 Cloud 模式")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    // 推荐滤镜标签
                    if let filter = currentFilterRec {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.caption2)
                                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                            Text(filter.presetNameZh)
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                    
                    // 进入设置页面按钮
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                Spacer()
                
                // 模式切换选择滚轮 (照片 / 视频)
                HStack(spacing: 24) {
                    Button(action: { captureMode = 0 }) {
                        Text("照片")
                            .font(.system(size: 14, weight: captureMode == 0 ? .bold : .medium))
                            .foregroundColor(captureMode == 0 ? Color(red: 1.0, green: 0.85, blue: 0.4) : .white.opacity(0.6))
                    }
                    Button(action: { captureMode = 1 }) {
                        Text("视频调色")
                            .font(.system(size: 14, weight: captureMode == 1 ? .bold : .medium))
                            .foregroundColor(captureMode == 1 ? Color(red: 0.3, green: 0.8, blue: 1.0) : .white.opacity(0.6))
                    }
                }
                .padding(.bottom, 12)
                
                // 底部快门操作栏
                HStack(spacing: 36) {
                    // 模拟触发 AI 构图分析按键
                    Button(action: triggerAnalysis) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(.yellow)
                            .frame(width: 48, height: 48)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    
                    // 快门按键 (照片模式为白圆圈，视频模式为红圆点)
                    Button(action: handleCaptureAction) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            if captureMode == 0 {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 60, height: 60)
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                    
                    // 视频调色工作台快捷入口
                    Button(action: { showVideoRetouch = true }) {
                        VStack(spacing: 2) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 18))
                                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 1.0))
                            Text("视频调色")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(width: 48, height: 48)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                    }
                }
                .padding(.bottom, 30)
            }
            
            // 5. 快门闪白遮罩 (模拟真实物理机械快门曝光)
            if isFlashing {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showRetouch) {
            RetouchView()
        }
        .fullScreenCover(isPresented: $showVideoRetouch) {
            VideoRetouchView()
        }
        .onAppear {
            // 首次加载自动触发一次初始场景感知
            triggerAnalysis()
        }
    }
    
    // MARK: - 触发拍摄或录像动作
    private func handleCaptureAction() {
        if captureMode == 0 {
            capturePhotoAction()
        } else {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            showVideoRetouch = true
        }
    }
    
    // MARK: - 触发快门拍摄与拍后调色跳转
    private func capturePhotoAction() {
        // 1. 物理触感反馈
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // 2. 模拟物理快门曝光闪白
        withAnimation(.easeIn(duration: 0.08)) {
            isFlashing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.15)) {
                self.isFlashing = false
            }
            // 3. 打开拍后智能调色工作台
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.showRetouch = true
            }
        }
    }
    
    // MARK: - 触发 AI 构图分析
    private func triggerAnalysis() {
        apiClient.fetchCompositionGuidance(
            pitch: motionManager.pitchDegrees,
            roll: motionManager.rollDegrees
        ) { result in
            switch result {
            case .success(let data):
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.currentGuidance = data.compositionGuidance
                    self.currentFilterRec = data.filterRecommendation
                    self.activeLutName = data.filterRecommendation.presetNameZh
                }
            case .failure(let error):
                print("[CameraView] 构图分析触发兜底或失败: \(error)")
            }
        }
    }
    
    // MARK: - 滤镜预设轮播切换
    private func toggleLutPreset() {
        let presets = ["自然原画", "落日暖调", "赛博青橙", "德味黑白"]
        if let idx = presets.firstIndex(of: activeLutName) {
            let nextIdx = (idx + 1) % presets.count
            activeLutName = presets[nextIdx]
        } else {
            activeLutName = "落日暖调"
        }
    }
}
