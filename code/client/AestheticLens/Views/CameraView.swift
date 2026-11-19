import SwiftUI
import AVFoundation
import Photos

/// 支持的取景与成片画幅比例
public enum CameraAspectRatio: String, CaseIterable {
    case ratio4x3 = "4:3"
    case ratio16x9 = "16:9"
    case ratio1x1 = "1:1"
    
    public var widthOverHeight: CGFloat {
        switch self {
        case .ratio4x3: return 3.0 / 4.0
        case .ratio16x9: return 9.0 / 16.0
        case .ratio1x1: return 1.0
        }
    }
    
    public var heightOverWidth: CGFloat {
        return 1.0 / widthOverHeight
    }
    
    public func next() -> CameraAspectRatio {
        switch self {
        case .ratio4x3: return .ratio16x9
        case .ratio16x9: return .ratio1x1
        case .ratio1x1: return .ratio4x3
        }
    }
}

/// 专业全栈电影相机主界面
public struct CameraView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var compositionEngine = RealtimeCompositionEngine.shared
    @Environment(\.scenePhase) private var scenePhase
    
    // 与 SettingsView 持久化联动
    @AppStorage("showLevelGauge") private var showLevelGauge: Bool = true
    @AppStorage("showAspectGrid") private var showAspectGrid: Bool = false
    @AppStorage("preserveOriginalHDR") private var preserveOriginalHDR: Bool = true
    
    // MARK: - 模式、画幅与滤镜状态 (默认打开为原生 4:3 原画镜头)
    @State private var captureMode: Int = 0
    @State private var photoAspectRatio: CameraAspectRatio = .ratio4x3
    @State private var activeLutName: String = "00-原画"
    @State private var isFilmstripExpanded: Bool = true
    @State private var isLutFilterEnabled: Bool = false
    
    // UI 交互与弹窗
    @State private var isFlashing: Bool = false
    @State private var showSettings: Bool = false
    @State private var showMediaGallery: Bool = false
    @State private var toastMessage: String? = nil
    @State private var showSceneAnalysisCard: Bool = false
    
    // MARK: - 最新成片轻量缓存 (最大 1440px，低内存占用)
    @State private var lastCapturedPhoto: UIImage? = nil
    @State private var lastCapturedFilterName: String = "00-原画 (RAW)"
    @State private var lastCapturedZoomFactor: CGFloat = 1.0
    @State private var lastCapturedDate: Date = Date()
    @State private var thumbnailScaleEffect: CGFloat = 1.0
    
    // 原生触觉反馈
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // 触控对焦状态
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusRing: Bool = false
    @State private var focusRingScale: CGFloat = 1.0
    @State private var focusDismissTask: DispatchWorkItem? = nil
    
    public init() {}
    
    private var activeAspectRatio: CameraAspectRatio {
        captureMode == 1 ? .ratio16x9 : photoAspectRatio
    }
    
    // 横屏拍摄自适应旋转角度 (驱动按钮、Icon 原地旋转)
    private var uiRotationAngle: Double {
        switch cameraManager.deviceOrientation {
        case .landscapeLeft:
            return 90.0
        case .landscapeRight:
            return -90.0
        case .portraitUpsideDown:
            return 180.0
        default:
            return 0.0
        }
    }
    
    public var body: some View {
        GeometryReader { rootGeo in
            let rootW = rootGeo.size.width
            let rootH = rootGeo.size.height
            let isOverlayLayout = (activeAspectRatio == .ratio16x9)
            
            // 按当前屏幕可用宽高精确等比计算取景器尺寸，避免小屏挤压或拉伸
            let maxStandardH = max(240, rootH - 270)
            let vfSize: CGSize = {
                if isOverlayLayout {
                    let targetW = min(rootW, rootH * activeAspectRatio.widthOverHeight)
                    return CGSize(width: targetW, height: targetW * activeAspectRatio.heightOverWidth)
                } else {
                    let idealH = rootW * activeAspectRatio.heightOverWidth
                    let finalH = min(idealH, maxStandardH)
                    let finalW = finalH * activeAspectRatio.widthOverHeight
                    return CGSize(width: finalW, height: finalH)
                }
            }()
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isOverlayLayout {
                    // 16:9 宽屏 / 视频沉浸模式：取景器居中满画幅展示，上下控制区悬浮于边缘
                    ZStack {
                        viewfinderWithOverlays(size: vfSize)
                            .frame(width: vfSize.width, height: vfSize.height)
                            .clipped()
                            .animation(.easeInOut(duration: 0.22), value: activeAspectRatio)
                        
                        VStack(spacing: 0) {
                            topProfessionalHUD
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                .padding(.bottom, 10)
                                .background(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.65), Color.black.opacity(0.0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            Spacer()
                            
                            VStack(spacing: 6) {
                                ZoomDialView(cameraManager: cameraManager, uiRotationAngle: uiRotationAngle)
                                bottomProfessionalDashboard
                            }
                            .padding(.top, 12)
                            .background(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.78)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                } else {
                    // 4:3 / 1:1 专业黑边取景布局：取景框绝不被控件遮挡或压缩
                    VStack(spacing: 0) {
                        topProfessionalHUD
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .zIndex(10)
                        
                        Spacer(minLength: 4)
                        
                        viewfinderWithOverlays(size: vfSize)
                            .frame(width: vfSize.width, height: vfSize.height)
                            .clipped()
                            .animation(.easeInOut(duration: 0.22), value: activeAspectRatio)
                        
                        Spacer(minLength: 4)
                        
                        ZoomDialView(cameraManager: cameraManager, uiRotationAngle: uiRotationAngle)
                            .zIndex(20)
                        
                        bottomProfessionalDashboard
                            .zIndex(10)
                    }
                }
                
                // 曝光快门闪光反馈
                if isFlashing {
                    Color.white
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                
                // 浮动 Toast 提示
                if let toast = toastMessage {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: toast.contains("失败") || toast.contains("权限") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(toast.contains("失败") || toast.contains("权限") ? .orange : Color(red: 1.0, green: 0.85, blue: 0.35))
                            Text(toast)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .padding(.top, 52)
                        .rotationEffect(.degrees(uiRotationAngle))
                        .animation(.spring(response: 0.3), value: uiRotationAngle)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        
                        Spacer()
                    }
                    .zIndex(100)
                    .allowsHitTesting(false)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showMediaGallery) {
            MediaGallerySheet(
                lastPhoto: lastCapturedPhoto,
                lastVideoURL: cameraManager.lastRecordedURL,
                lutName: lastCapturedFilterName,
                zoomFactor: lastCapturedZoomFactor,
                captureDate: lastCapturedDate
            )
        }
        .onAppear {
            cameraManager.checkPermissions()
            cameraManager.startSession()
            selectionFeedback.prepare()
            impactFeedback.prepare()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                cameraManager.checkPermissions()
                cameraManager.startSession()
            case .background:
                cameraManager.stopSession()
            default:
                break
            }
        }
    }
    
    // MARK: - 取景器容器 + 胶卷条 + 权限引导 + AI 卡片
    @ViewBuilder
    private func viewfinderWithOverlays(size: CGSize) -> some View {
        ZStack(alignment: .trailing) {
            viewfinderContainer(size: size)
            
            // 无相机权限引导视图
            if cameraManager.permissionDenied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill.badge.ellipsis")
                        .font(.system(size: 42))
                        .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    Text("需要相机权限以开启取景器")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Button(action: {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }) {
                        Text("前往系统设置开启")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(red: 1.0, green: 0.88, blue: 0.35))
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.85))
            }
            
            // 右侧悬浮 35mm 电影胶卷滑轨
            filmstripLutOverlayRail
                .padding(.trailing, 10)
            
            // AI 深度场景分析语言浮动卡片
            if showSceneAnalysisCard && compositionEngine.state != .inactive {
                aiSceneAnalysisOverlayCard
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - 顶部专业 HUD
    private var topProfessionalHUD: some View {
        HStack {
            // 模式、画幅切换与胶卷指示
            HStack(spacing: 6) {
                Button(action: {
                    guard captureMode == 0 else { return }
                    selectionFeedback.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        photoAspectRatio = photoAspectRatio.next()
                    }
                    showToast("画幅已切换为 \(photoAspectRatio.rawValue)")
                }) {
                    HStack(spacing: 4) {
                        Text(captureMode == 1 ? "16:9 · 60FPS" : "\(activeAspectRatio.rawValue) · 高清")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.14))
                    .cornerRadius(5)
                }
                .disabled(captureMode == 1)
                
                Text(isLutFilterEnabled ? String(activeLutName.prefix(2)) : "RAW原画")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.82))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.09))
                    .cornerRadius(5)
            }
            .rotationEffect(.degrees(uiRotationAngle))
            .animation(.spring(response: 0.3), value: uiRotationAngle)
            
            Spacer()
            
            // 录像时长指示器
            if cameraManager.isRecordingVideo {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(String(format: "%02d:%02d", cameraManager.recordingSeconds / 60, cameraManager.recordingSeconds % 60))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.32))
                .cornerRadius(6)
                .rotationEffect(.degrees(uiRotationAngle))
                .animation(.spring(response: 0.3), value: uiRotationAngle)
            }
            
            Spacer()
            // AI 分析按钮
            Button(action: handleAITrigger) {
                let isEngineActive = (compositionEngine.state != .inactive)
                let isAnalyzing = (compositionEngine.state == .analyzing)
                
                HStack(spacing: 5) {
                    if isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: isEngineActive ? "sparkles.rectangle.stack.fill" : "sparkles")
                            .font(.system(size: 12))
                    }
                    
                    Text(isAnalyzing ? "AI 识别中..." : (isEngineActive ? "AI 场景分析" : "✨ AI 分析"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(isEngineActive ? .black : .white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isEngineActive ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.white.opacity(0.14))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .rotationEffect(.degrees(uiRotationAngle))
            .animation(.spring(response: 0.3), value: uiRotationAngle)
        }
    }
    
    private func handleAITrigger() {
        impactFeedback.impactOccurred()
        compositionEngine.refreshSceneAnalysis(cameraManager: cameraManager)
        withAnimation(.spring(response: 0.35)) {
            showSceneAnalysisCard = true
        }
    }
    
    // MARK: - 取景器视口 (Metal 帧同步预览 + 三分线网格 + 水平仪 + 触控对焦)
    private func viewfinderContainer(size: CGSize) -> some View {
        ZStack {
            // 1. Metal 实时取景 (默认未开启滤镜时直通原生画质，严格 Aspect Fill 不变形)
            MetalView(activePreset: isLutFilterEnabled ? activeLutName : "00-自然原画")
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    handleTapToFocus(at: location, in: size)
                }
            
            // 2. 可选三分线网格
            if showAspectGrid {
                RuleOfThirdsGridOverlay()
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }
            
            // 3. 60Hz 空间水平仪 (受设置控制)
            if showLevelGauge {
                LevelGaugeView()
                    .allowsHitTesting(false)
            }
            
            // 4. 4D AR 黄金构图目标框
            NavigationOverlayView()
                .allowsHitTesting(false)
            
            // 5. 触控对焦框
            if showFocusRing, let point = focusPoint {
                focusIndicatorView
                    .position(point)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }
    
    // MARK: - AI 实时场景深度分析语言浮动卡片
    private var aiSceneAnalysisOverlayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                        .font(.system(size: 13, weight: .bold))
                    Text(compositionEngine.sceneTitle.isEmpty ? compositionEngine.sceneTypeZh : compositionEngine.sceneTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    
                    if compositionEngine.isCloudAI {
                        Text("阿里云 Qwen-VL")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(3)
                    } else {
                        Text("端侧视觉神经引擎")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(white: 0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSceneAnalysisCard = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Divider().background(Color.white.opacity(0.15))
            
            if !compositionEngine.sceneAnalysis.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🏞️ 场景解构:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    Text(compositionEngine.sceneAnalysis)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(2)
                }
            }
            
            if !compositionEngine.lightingAndElement.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("☀️ 光影技巧:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    Text(compositionEngine.lightingAndElement)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(2)
                }
            }
            
            if !compositionEngine.placementGuide.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🎯 最佳机位:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.45))
                    Text(compositionEngine.placementGuide)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(2)
                }
            }
            
            HStack(spacing: 8) {
                Button(action: {
                    selectionFeedback.selectionChanged()
                    cameraManager.rampZoom(to: CGFloat(compositionEngine.recommendedZoom))
                    showToast(String(format: "已推镜至推荐 %.1f×", compositionEngine.recommendedZoom))
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "camera.metering.matrix")
                        Text(String(format: "推镜 %.1f×", compositionEngine.recommendedZoom))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(red: 1.0, green: 0.88, blue: 0.35))
                    .cornerRadius(6)
                }

                Button(action: {
                    selectionFeedback.selectionChanged()
                    activeLutName = compositionEngine.recommendedFilterPreset
                    isLutFilterEnabled = true
                    MetalRenderer.shared.applyPreset(activeLutName)
                    showToast("已应用推荐风格: \(activeLutName)")
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "film")
                        Text("应用 \(compositionEngine.recommendedFilterPreset.prefix(2))")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(6)
                }

                Button(action: {
                    impactFeedback.impactOccurred()
                    compositionEngine.refreshSceneAnalysis(cameraManager: cameraManager)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("重新分析")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color(red: 1.0, green: 0.88, blue: 0.35).opacity(0.18))
                    .cornerRadius(6)
                }

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 1.0, green: 0.88, blue: 0.35).opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 10)
    }
    
    // MARK: - 右侧悬浮 35mm 胶卷选择器
    private var filmstripLutOverlayRail: some View {
        VStack(spacing: 8) {
            Button(action: {
                selectionFeedback.selectionChanged()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isFilmstripExpanded.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: 34, height: 34)
                    Image(systemName: isFilmstripExpanded ? "chevron.right" : "film")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                }
            }
            .rotationEffect(.degrees(uiRotationAngle))
            .animation(.spring(response: 0.3), value: uiRotationAngle)
            
            if isFilmstripExpanded {
                let presets = ["00-原画", "01-暖金", "02-冷萃", "03-青橙", "04-电影", "06-黑白"]
                ForEach(presets, id: \.self) { preset in
                    let isSelected = (preset == "00-原画" && !isLutFilterEnabled) ||
                                     (isLutFilterEnabled && activeLutName.contains(preset.prefix(2)))
                    
                    Button(action: {
                        selectionFeedback.selectionChanged()
                        if preset == "00-原画" {
                            isLutFilterEnabled = false
                            activeLutName = "00-原画"
                            MetalRenderer.shared.applyPreset("00-自然原画")
                            showToast("已切回原生原画镜头")
                        } else {
                            isLutFilterEnabled = true
                            let fullName: String
                            switch preset {
                            case "01-暖金": fullName = "01-暖金电影"
                            case "02-冷萃": fullName = "02-富士冷萃"
                            case "03-青橙": fullName = "03-赛博青橙"
                            case "04-电影": fullName = "04-电影质感"
                            case "06-黑白": fullName = "06-徕卡黑白"
                            default: fullName = "01-暖金电影"
                            }
                            activeLutName = fullName
                            MetalRenderer.shared.applyPreset(fullName)
                            showToast("已应用风格: \(fullName)")
                        }
                    }) {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSelected ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.white.opacity(0.35))
                                .frame(width: 24, height: 3)
                            
                            Text(preset == "00-原画" ? "RAW" : String(preset.prefix(2)))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(isSelected ? .black : .white)
                                .frame(width: 32, height: 26)
                                .background(isSelected ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.black.opacity(0.65))
                                .cornerRadius(5)
                        }
                    }
                    .rotationEffect(.degrees(uiRotationAngle))
                    .animation(.spring(response: 0.3), value: uiRotationAngle)
                }
            }
        }
    }
    
    // MARK: - 底部专业控制台 (大快门 + 四联控制栏：相机、视频、媒体、设置)
    private var bottomProfessionalDashboard: some View {
        VStack(spacing: 10) {
            HStack {
                // 左侧：前后摄像头翻转
                Button(action: {
                    guard !cameraManager.isSwitchingCamera, !cameraManager.isRecordingVideo else { return }
                    impactFeedback.impactOccurred()
                    cameraManager.switchCamera()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(cameraManager.isSwitchingCamera ? 180 : 0))
                            .animation(.easeInOut(duration: 0.3), value: cameraManager.isSwitchingCamera)
                    }
                }
                .disabled(cameraManager.isSwitchingCamera || cameraManager.isRecordingVideo)
                .opacity(cameraManager.isRecordingVideo ? 0.35 : 1.0)
                .frame(maxWidth: .infinity)
                .rotationEffect(.degrees(uiRotationAngle))
                .animation(.spring(response: 0.3), value: uiRotationAngle)
                
                // 中央核心大快门
                Button(action: handleMainShutterAction) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3.5)
                            .frame(width: 72, height: 72)
                        
                        if captureMode == 0 {
                            Circle()
                                .fill(cameraManager.isCapturingPhoto ? Color.gray : Color.white)
                                .frame(width: 58, height: 58)
                                .overlay(
                                    Group {
                                        if cameraManager.isCapturingPhoto {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        }
                                    }
                                )
                        } else {
                            if cameraManager.isRecordingVideo {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red)
                                    .frame(width: 28, height: 28)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 56, height: 56)
                            }
                        }
                    }
                }
                .contentShape(Circle())
                .disabled(cameraManager.isCapturingPhoto)
                .frame(maxWidth: .infinity)
                .rotationEffect(.degrees(uiRotationAngle))
                .animation(.spring(response: 0.3), value: uiRotationAngle)
                
                // 右侧：媒体预览入口
                Button(action: {
                    selectionFeedback.selectionChanged()
                    showMediaGallery = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 48, height: 48)
                        
                        if let photo = lastCapturedPhoto {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(Color(red: 1.0, green: 0.88, blue: 0.35), lineWidth: 1.5)
                                )
                                .scaleEffect(thumbnailScaleEffect)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 18))
                                .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .rotationEffect(.degrees(uiRotationAngle))
                .animation(.spring(response: 0.3), value: uiRotationAngle)
            }
            .padding(.horizontal, 20)
            
            // 底部四联导航栏：【相机】、【视频】、【媒体】、【设置】
            HStack(spacing: 0) {
                bottomNavTabButton(
                    title: "相机",
                    systemIcon: "camera.fill",
                    isSelected: captureMode == 0
                ) {
                    guard !cameraManager.isRecordingVideo else { return }
                    selectionFeedback.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.18)) { captureMode = 0 }
                    cameraManager.setCaptureMode(0)
                }
                
                bottomNavTabButton(
                    title: "视频",
                    systemIcon: "video.fill",
                    isSelected: captureMode == 1
                ) {
                    selectionFeedback.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.18)) { captureMode = 1 }
                    cameraManager.setCaptureMode(1)
                }
                
                bottomNavTabButton(
                    title: "媒体",
                    systemIcon: "square.grid.2x2.fill",
                    isSelected: false
                ) {
                    selectionFeedback.selectionChanged()
                    showMediaGallery = true
                }
                
                bottomNavTabButton(
                    title: "设置",
                    systemIcon: "gearshape.fill",
                    isSelected: false
                ) {
                    selectionFeedback.selectionChanged()
                    showSettings = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .cornerRadius(16)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }
    
    private func bottomNavTabButton(title: String, systemIcon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemIcon)
                    .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color(white: 0.65))
                
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color(white: 0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .rotationEffect(.degrees(uiRotationAngle))
            .animation(.spring(response: 0.3), value: uiRotationAngle)
        }
    }
    
    // MARK: - 快门触发核心逻辑 (全异步零卡顿、保留原生 HDR / EXIF 写入相册)
    private func handleMainShutterAction() {
        if captureMode == 0 {
            impactFeedback.impactOccurred()
            withAnimation(.easeInOut(duration: 0.06)) { isFlashing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.14)) { isFlashing = false }
            }
            
            let shouldApplyFilter = self.isLutFilterEnabled && self.activeLutName != "00-原画"
            let currentLutLabel = shouldApplyFilter ? self.activeLutName : "00-原画 (RAW)"
            let zoomAtCapture = self.cameraManager.currentZoom
            
            // 仅当用户选择非 4:3 画幅或关闭无损直存时才裁切，默认 4:3 原画 100% 透传原生文件流
            let targetRatio: CGFloat? = (self.photoAspectRatio == .ratio4x3 && self.preserveOriginalHDR && !shouldApplyFilter)
                ? nil
                : self.photoAspectRatio.widthOverHeight
            
            cameraManager.captureRawPhotoData { rawData, _ in
                guard let rawData = rawData else {
                    self.showToast("拍照失败，请检查相机状态")
                    return
                }
                
                MetalRenderer.shared.processCapturedPhotoData(
                    rawData,
                    applyFilter: shouldApplyFilter,
                    displayAspectRatio: targetRatio
                ) { finalData, previewImage in
                    if let preview = previewImage {
                        self.lastCapturedPhoto = preview
                        self.lastCapturedFilterName = currentLutLabel
                        self.lastCapturedZoomFactor = zoomAtCapture
                        self.lastCapturedDate = Date()
                        
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                            self.thumbnailScaleEffect = 1.25
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                self.thumbnailScaleEffect = 1.0
                            }
                        }
                    }
                    
                    guard let photoDataToSave = finalData else {
                        self.showToast("成片处理失败")
                        return
                    }
                    
                    self.savePhotoDataToAlbum(photoDataToSave) { success, errMsg in
                        if success {
                            let toastTitle = shouldApplyFilter
                                ? "✓ 胶片成片已保留 EXIF 存入相册"
                                : "✓ 原生高清照片已无损存入相册"
                            self.showToast(toastTitle)
                        } else {
                            self.showToast(errMsg ?? "相册保存失败，请检查权限")
                        }
                    }
                }
            }
        } else {
            impactFeedback.impactOccurred()
            if cameraManager.isRecordingVideo {
                cameraManager.stopRecordingVideo()
                showToast("正在封装保存 60fps 视频...")
            } else {
                cameraManager.startRecordingVideo { recordedURL, errMsg in
                    if let errMsg = errMsg {
                        self.showToast(errMsg)
                    } else if recordedURL != nil {
                        self.showToast("✓ 60fps 视频已保存至相册")
                    }
                }
            }
        }
    }
    
    private func savePhotoDataToAlbum(_ data: Data, completion: @escaping (Bool, String?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(false, "无相册写入权限，请在系统设置中开启")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success, error?.localizedDescription)
                }
            }
        }
    }
    
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            self.toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                if self.toastMessage == text {
                    self.toastMessage = nil
                }
            }
        }
    }
    
    // MARK: - 精确触控对焦 (坐标限定在取景器内部，结合 Aspect Fill 反算传感器焦点)
    private func handleTapToFocus(at location: CGPoint, in size: CGSize) {
        focusDismissTask?.cancel()
        let safeX = max(28, min(location.x, size.width - 28))
        let safeY = max(28, min(location.y, size.height - 28))
        focusPoint = CGPoint(x: safeX, y: safeY)
        focusRingScale = 1.32
        showFocusRing = true
        
        let focusX = location.x / max(size.width, 1)
        let focusY = location.y / max(size.height, 1)
        cameraManager.focus(atNormalizedViewPoint: CGPoint(x: focusX, y: focusY))
        selectionFeedback.selectionChanged()
        
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
            focusRingScale = 1.0
        }
        
        let task = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.28)) {
                self.showFocusRing = false
                self.focusPoint = nil
            }
        }
        focusDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: task)
    }
    
    private var focusIndicatorView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(red: 1.0, green: 0.85, blue: 0.2), lineWidth: 1.6)
                .frame(width: 66, height: 66)
            
            Circle()
                .fill(Color(red: 1.0, green: 0.85, blue: 0.2))
                .frame(width: 4, height: 4)
        }
        .scaleEffect(focusRingScale)
    }
}

// MARK: - 独立丝滑对数阻尼变焦刻度轮 (拖动过程中不触发 CameraView 全树重绘)
struct ZoomDialView: View {
    @ObservedObject var cameraManager: CameraManager
    let uiRotationAngle: Double
    
    @State private var isDialExpanded: Bool = false
    @State private var draggingZoom: CGFloat? = nil
    @State private var dragStartZoom: CGFloat = 1.0
    @State private var lastHapticStep: Int = -1
    @State private var collapseWorkItem: DispatchWorkItem? = nil
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    // 当前界面显示倍率 (拖动中使用本地状态实现 120Hz 零延迟，非拖动同步 cameraManager)
    private var displayZoom: CGFloat {
        draggingZoom ?? cameraManager.currentZoom
    }
    
    var body: some View {
        VStack(spacing: 4) {
            if isDialExpanded {
                logarithmicRulerView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                compactPresetBar
                    .transition(.opacity)
            }
        }
        .frame(height: 68)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .gesture(zoomDragGesture)
    }
    
    // 常态：紧凑硬件焦段微胶囊组
    private var compactPresetBar: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f×", displayZoom))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
            
            HStack(spacing: 10) {
                ForEach(cameraManager.availableZoomPresets, id: \.self) { val in
                    zoomPresetButton(val: val)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.42))
            .clipShape(Capsule())
        }
    }
    
    private func zoomPresetButton(val: CGFloat) -> some View {
        let presets = cameraManager.availableZoomPresets
        let nearest = presets.min(by: { abs($0 - displayZoom) < abs($1 - displayZoom) }) ?? 1.0
        let isActive = abs(val - nearest) < 0.01
        
        let title: String = {
            if isActive && abs(displayZoom - val) >= 0.15 {
                return String(format: "%.1f×", displayZoom)
            }
            if val == 0.5 { return ".5" }
            if val == 1.0 { return "1×" }
            return String(format: "%.0f", val)
        }()
        
        return Text(title)
            .font(.system(size: isActive ? 12 : 11, weight: .bold, design: .rounded))
            .foregroundColor(isActive ? Color(red: 1.0, green: 0.88, blue: 0.35) : .white)
            .frame(width: 34, height: 34)
            .background(isActive ? Color.black.opacity(0.85) : Color.black.opacity(0.45))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isActive ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.white.opacity(0.22), lineWidth: isActive ? 1.5 : 0.8)
            )
            .scaleEffect(isActive ? 1.06 : 1.0)
            .onTapGesture {
                selectionFeedback.selectionChanged()
                withAnimation(.spring(response: 0.25)) {
                    cameraManager.rampZoom(to: val)
                }
            }
            .rotationEffect(.degrees(uiRotationAngle))
            .animation(.spring(response: 0.25), value: uiRotationAngle)
    }
    
    // 滑动展开态：对数刻度尺 (居中金色指示针 + 平滑移动刻度线)
    private var logarithmicRulerView: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f×", displayZoom))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.8))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(red: 1.0, green: 0.88, blue: 0.35).opacity(0.7), lineWidth: 1))
            
            GeometryReader { geo in
                let centerX = geo.size.width / 2.0
                let pixelsPerLogUnit: CGFloat = 135.0
                let currentLog = log(max(0.5, displayZoom))
                
                // 生成 0.5x ~ maxZoom 的对数分布刻度
                let tickValues: [CGFloat] = {
                    var list: [CGFloat] = []
                    var v: CGFloat = 0.5
                    while v <= cameraManager.maxZoom + 0.01 {
                        list.append((v * 10.0).rounded() / 10.0)
                        if v < 1.0 {
                            v += 0.1
                        } else if v < 3.0 {
                            v += 0.2
                        } else if v < 6.0 {
                            v += 0.5
                        } else {
                            v += 1.0
                        }
                    }
                    return list
                }()
                
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.55))
                    
                    ForEach(tickValues, id: \.self) { val in
                        let tickLog = log(max(0.5, val))
                        let offsetX = (tickLog - currentLog) * pixelsPerLogUnit
                        let posX = centerX + offsetX
                        
                        if posX >= 6 && posX <= geo.size.width - 6 {
                            let isMajor = cameraManager.availableZoomPresets.contains(where: { abs($0 - val) < 0.05 }) || abs(val - val.rounded()) < 0.01
                            VStack(spacing: 2) {
                                Rectangle()
                                    .fill(isMajor ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                                    .frame(width: isMajor ? 1.5 : 1.0, height: isMajor ? 14 : 8)
                            }
                            .position(x: posX, y: geo.size.height / 2.0)
                        }
                    }
                    
                    // 中央固定金色游标指针
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.88, blue: 0.35))
                        .frame(width: 2.5, height: 22)
                        .position(x: centerX, y: geo.size.height / 2.0)
                }
            }
            .frame(height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // 对数阻尼手势：划动等距实现倍率等比翻倍/减半，支持关键点轻震动吸附
    private var zoomDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                collapseWorkItem?.cancel()
                if draggingZoom == nil {
                    dragStartZoom = cameraManager.currentZoom
                    draggingZoom = dragStartZoom
                    selectionFeedback.prepare()
                    withAnimation(.easeOut(duration: 0.15)) {
                        isDialExpanded = true
                    }
                }
                
                // 对数灵敏度：左划放大，右划缩小 (每 92pt 倍率翻倍)
                let sensitivity: CGFloat = 0.0075
                let rawTarget = dragStartZoom * exp(-value.translation.width * sensitivity)
                var clamped = max(cameraManager.minZoom, min(rawTarget, cameraManager.maxZoom))
                
                // 靠近关键焦段时轻微磁吸
                for preset in cameraManager.availableZoomPresets {
                    if abs(clamped - preset) < 0.035 {
                        clamped = preset
                        break
                    }
                }
                
                let rounded = (clamped * 10.0).rounded() / 10.0
                if rounded != draggingZoom {
                    draggingZoom = rounded
                    cameraManager.setZoom(factor: rounded, publishToUI: false)
                    
                    // 仅在跨过 0.5x 整数步进刻度时轻震反馈，绝不每 0.1x 狂震卡顿
                    let stepBucket = Int((rounded * 2.0).rounded())
                    if stepBucket != lastHapticStep {
                        lastHapticStep = stepBucket
                        selectionFeedback.selectionChanged()
                    }
                }
            }
            .onEnded { _ in
                if let finalZoom = draggingZoom {
                    cameraManager.setZoom(factor: finalZoom, publishToUI: true)
                }
                draggingZoom = nil
                lastHapticStep = -1
                
                let workItem = DispatchWorkItem {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isDialExpanded = false
                    }
                }
                collapseWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
            }
    }
}

// MARK: - 三分线辅助网格
struct RuleOfThirdsGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.move(to: CGPoint(x: w / 3.0, y: 0))
                path.addLine(to: CGPoint(x: w / 3.0, y: h))
                path.move(to: CGPoint(x: w * 2.0 / 3.0, y: 0))
                path.addLine(to: CGPoint(x: w * 2.0 / 3.0, y: h))
                
                path.move(to: CGPoint(x: 0, y: h / 3.0))
                path.addLine(to: CGPoint(x: w, y: h / 3.0))
                path.move(to: CGPoint(x: 0, y: h * 2.0 / 3.0))
                path.addLine(to: CGPoint(x: w, y: h * 2.0 / 3.0))
            }
            .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
        }
    }
}

/// 媒体相册与最近成片专业检视弹窗 (已接通 RetouchView 照片精修与 VideoRetouchView 视频精修入口)
struct MediaGallerySheet: View {
    @Environment(\.presentationMode) var presentationMode
    let lastPhoto: UIImage?
    let lastVideoURL: URL?
    let lutName: String
    let zoomFactor: CGFloat
    let captureDate: Date
    
    @State private var showShareSheet: Bool = false
    @State private var showPhotoRetouch: Bool = false
    @State private var showVideoRetouch: Bool = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let photo = lastPhoto {
                    VStack(spacing: 0) {
                        Spacer()
                        
                        Image(uiImage: photo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(zoomScale)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoomScale = lastZoomScale * value
                                    }
                                    .onEnded { _ in
                                        if zoomScale < 1.0 {
                                            withAnimation(.spring()) { zoomScale = 1.0 }
                                        } else if zoomScale > 3.5 {
                                            withAnimation(.spring()) { zoomScale = 3.5 }
                                        }
                                        lastZoomScale = zoomScale
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    if zoomScale > 1.2 {
                                        zoomScale = 1.0
                                        lastZoomScale = 1.0
                                    } else {
                                        zoomScale = 2.0
                                        lastZoomScale = 2.0
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        Spacer()
                        
                        // 底部操作与参数卡片
                        VStack(spacing: 10) {
                            HStack {
                                Label(lutName, systemImage: "film.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                                
                                Spacer()
                                
                                Text(String(format: "%.1f× 焦段", zoomFactor))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                
                                Text("•")
                                    .foregroundColor(.white.opacity(0.4))
                                
                                Text(photoResolutionString(photo))
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            
                            HStack {
                                Text(formattedDateString(captureDate))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Button(action: {
                                    showPhotoRetouch = true
                                }) {
                                    Label("后期精修调色", systemImage: "slider.horizontal.3")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(red: 1.0, green: 0.88, blue: 0.35))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 54))
                            .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                        
                        Text("暂无近期拍摄成片")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("轻触快门即可拍摄，成片将自动保留原始画质并支持在此预览与后期精修。")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                        
                        if lastVideoURL != nil {
                            Button(action: {
                                showVideoRetouch = true
                            }) {
                                Label("进入最近视频精修工作台", systemImage: "video.badge.waveform")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(Color(red: 1.0, green: 0.88, blue: 0.35))
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("成片检视")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .semibold))
                },
                trailing: HStack(spacing: 16) {
                    if lastVideoURL != nil && lastPhoto != nil {
                        Button(action: {
                            showVideoRetouch = true
                        }) {
                            Image(systemName: "film.stack")
                                .foregroundColor(.white)
                                .font(.system(size: 15))
                        }
                    }
                    if lastPhoto != nil {
                        Button(action: {
                            showShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                                .font(.system(size: 16))
                        }
                    }
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                }
            )
            .sheet(isPresented: $showShareSheet) {
                if let photo = lastPhoto {
                    ActivityViewController(activityItems: [photo])
                }
            }
            .sheet(isPresented: $showPhotoRetouch) {
                if let photo = lastPhoto {
                    RetouchView(inputImage: photo)
                }
            }
            .sheet(isPresented: $showVideoRetouch) {
                if let videoURL = lastVideoURL {
                    VideoRetouchView(videoURL: videoURL)
                }
            }
        }
    }
    
    private func photoResolutionString(_ image: UIImage) -> String {
        if let cg = image.cgImage {
            return "\(cg.width) × \(cg.height)"
        }
        return "\(Int(image.size.width)) × \(Int(image.size.height))"
    }
    
    private func formattedDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 系统分享组件 (支持 AirDrop、微信、相册等导出)
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
