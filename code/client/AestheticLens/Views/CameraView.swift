import SwiftUI
import AVFoundation

/// 工业级专业全栈电影相机 UI
/// 1. 默认原镜头：启动时保持 100% 纯净原相机，滤镜列表包含 [00-原画]，按需开启
/// 2. 变焦轮重构：彻底解决卡住划不动，采用高灵敏增量位移滑动引擎，0.1x 丝滑微调
/// 3. AI 实时场景分析：真实感知镜头场景与焦点，呈现人物最佳机位与阳光拍摄语言
/// 4. 全系统横屏拍摄自适应与 4:3 几何保真
public struct CameraView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var motionManager = MotionManager.shared
    @StateObject private var compositionEngine = RealtimeCompositionEngine.shared
    private let apiClient = APIClient.shared
    
    // MARK: - 模式与滤镜状态 (默认打开为原生原镜头，不叠加任何滤镜)
    @State private var captureMode: Int = 0
    @State private var activeLutName: String = "00-原画"
    @State private var isFilmstripExpanded: Bool = true
    @State private var isLutFilterEnabled: Bool = false
    
    // UI 交互与弹窗
    @State private var isFlashing: Bool = false
    @State private var showSettings: Bool = false
    @State private var showMediaGallery: Bool = false
    @State private var toastMessage: String? = nil
    
    // AI 深度场景分析卡片展开状态
    @State private var showSceneAnalysisCard: Bool = false

    // MARK: - 最新成片状态 (用于在 App 内部直接查看最新拍摄的带滤镜大图)
    @State private var lastCapturedPhoto: UIImage? = nil
    @State private var lastCapturedFilterName: String = "00-原画"
    @State private var lastCapturedZoomFactor: CGFloat = 1.0
    @State private var lastCapturedDate: Date = Date()
    @State private var thumbnailScaleEffect: CGFloat = 1.0
    
    // 变焦连续手势状态 (基于即时增量位移，彻底杜绝死区卡顿)
    @State private var lastDragLocationX: CGFloat? = nil
    
    // 原生触觉反馈
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // 触控对焦状态
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusRing: Bool = false
    @State private var focusRingScale: CGFloat = 1.0
    @State private var focusDismissTask: DispatchWorkItem? = nil
    
    public init() {}
    
    // 横屏拍摄自适应旋转角度
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
        ZStack {
            // 专业沉浸纯黑底色
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 顶部专业 HUD
                topProfessionalHUD
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .zIndex(10)
                
                Spacer(minLength: 4)
                
                // 2. 取景器中枢 (4:3 标准保真几何视口，严防拉伸变形)
                ZStack(alignment: .trailing) {
                    viewfinderContainer
                    
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
                .frame(maxWidth: .infinity)
                .frame(height: UIScreen.main.bounds.width * (4.0 / 3.0))
                .clipped()
                
                Spacer(minLength: 4)
                
                // 3. 快门正上方：上半圆弧形连续变焦盘 (0.1x 丝滑增量滑动，绝不卡住)
                upperArcZoomDialView
                    .zIndex(20)
                
                // 4. 底部专业控制台 (大快门 + 四联导航)
                bottomProfessionalDashboard
                    .zIndex(10)
            }
            
            // 曝光快门闪光反馈
            if isFlashing {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            
            // 浮动 Toast 提示
            if let toast = toastMessage {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.35))
                        Text(toast)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.top, 48)
                    .rotationEffect(.degrees(uiRotationAngle))
                    .animation(.spring(response: 0.3), value: uiRotationAngle)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .zIndex(100)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showMediaGallery) {
            MediaGallerySheet(
                lastPhoto: lastCapturedPhoto,
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
    }
    
    // MARK: - 顶部专业 HUD
    private var topProfessionalHUD: some View {
        HStack {
            // 分辨率与高刷标头
            HStack(spacing: 6) {
                Text(captureMode == 1 ? "4K 60FPS" : "48MP RAW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(4)
                
                Text(isLutFilterEnabled ? activeLutName.prefix(2) : "RAW原画")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
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
                .background(Color.red.opacity(0.25))
                .cornerRadius(6)
                .rotationEffect(.degrees(uiRotationAngle))
                .animation(.spring(response: 0.3), value: uiRotationAngle)
            }
            
            Spacer()
            
            // ✨ AI 分析 / 探景按钮 (实时识别当前镜头场景，输出真实场景构图指导)
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
    
    // AI 分析点击响应：每次点击均抓取相机最新一帧，对新场景进行即时重新解构分析
    private func handleAITrigger() {
        impactFeedback.impactOccurred()
        compositionEngine.refreshSceneAnalysis(cameraManager: cameraManager)
        withAnimation(.spring(response: 0.35)) {
            showSceneAnalysisCard = true
        }
    }
    
    // MARK: - 取景器视口 (4:3 比例保真，带 Metal 上色预览与 AR 构图浮层)
    private var viewfinderContainer: some View {
        GeometryReader { proxy in
            ZStack {
                // 1. Metal 实时取景 (默认未开启滤镜时直接原镜头直通渲染)
                MetalView(activePreset: isLutFilterEnabled ? activeLutName : "00-自然原画")
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTapToFocus(at: location, in: proxy.size)
                    }
                
                // 2. 60Hz 空间水平仪
                LevelGaugeView()
                    .allowsHitTesting(false)
                
                // 3. 4D AR 黄金构图目标框与防抖引导准星
                NavigationOverlayView()
                    .allowsHitTesting(false)
                
                // 4. 触控对焦框
                if showFocusRing, let point = focusPoint {
                    focusIndicatorView
                        .position(point)
                        .transition(.opacity)
                }
            }
        }
    }
    
    // MARK: - AI 实时场景深度分析语言浮动卡片
    private var aiSceneAnalysisOverlayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 卡片头部与来源识别
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
                        Text("端侧视觉神经引擎 · 实时分析")
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
            
            // 1. 当前场景与主体深度分析
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
            
            // 2. 光线与拍摄技巧分析 (阳光/逆光拍法)
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
            
            // 3. 主体在哪个位置效果最佳 (最佳位置指导)
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
            
            // 底部操作栏：一键推镜与应用胶片
            HStack(spacing: 8) {
                Button(action: {
                    selectionFeedback.selectionChanged()
                    cameraManager.setZoom(factor: CGFloat(compositionEngine.recommendedZoom))
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

                // 🔄 重新识别当前场景按钮 (变换镜头后一键刷新)
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
    
    // MARK: - 右侧悬浮 35mm 胶卷选择器 (加入 00-原画，支持一键切换原镜头)
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
                            // 保持原镜头：关闭滤镜直通原生画质
                            isLutFilterEnabled = false
                            activeLutName = "00-原画"
                            MetalRenderer.shared.applyPreset("00-自然原画")
                            showToast("已切回原生原画镜头")
                        } else {
                            // 按需开启电影风格滤镜
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
                            
                            Text(preset == "00-原画" ? "RAW" : preset.prefix(2))
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
    
    // MARK: - 快门正上方：上半圆弧形连续变焦盘 (Upper Arc Zoom Dial)
    // 拆解轻量级子视图，避免 Swift 编译器类型推导超时
    private var zoomValueIndicator: some View {
        ZStack {
            ArcDialTrackShape()
                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                .frame(width: 260, height: 28)
            
            Text(String(format: "%.1f×", cameraManager.currentZoom))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color(red: 1.0, green: 0.88, blue: 0.35).opacity(0.7), lineWidth: 1)
                )
        }
        .frame(height: 30)
    }

    private var zoomPresetsCapsuleRow: some View {
        HStack(spacing: 12) {
            zoomPresetButton(label: ".5", val: 0.5)
            zoomPresetButton(label: "1×", val: 1.0)
            zoomPresetButton(label: "2", val: 2.0)
            zoomPresetButton(label: "3", val: 3.0)
            zoomPresetButton(label: "5", val: 5.0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    private func zoomPresetButton(label: String, val: CGFloat) -> some View {
        let isCurrent = abs(cameraManager.currentZoom - val) < 0.15
        return Text(label)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(isCurrent ? Color(red: 1.0, green: 0.88, blue: 0.35) : .white)
            .frame(width: 36, height: 36)
            .background(isCurrent ? Color.black.opacity(0.85) : Color.black.opacity(0.45))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isCurrent ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.white.opacity(0.2), lineWidth: isCurrent ? 1.5 : 0.8)
            )
            .onTapGesture {
                selectionFeedback.selectionChanged()
                cameraManager.setZoom(factor: val)
            }
            .rotationEffect(.degrees(uiRotationAngle))
            .animation(.spring(response: 0.3), value: uiRotationAngle)
    }

    private var zoomDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let currentX = value.location.x
                if let lastX = lastDragLocationX {
                    let diff = currentX - lastX
                    let step = -diff / 75.0
                    let target = max(cameraManager.minZoom, min(cameraManager.currentZoom + step, cameraManager.maxZoom))
                    let rounded = (target * 10.0).rounded() / 10.0
                    if rounded != cameraManager.currentZoom {
                        selectionFeedback.selectionChanged()
                        cameraManager.setZoom(factor: rounded)
                    }
                }
                lastDragLocationX = currentX
            }
            .onEnded { _ in
                lastDragLocationX = nil
            }
    }

    private var upperArcZoomDialView: some View {
        VStack(spacing: 4) {
            zoomValueIndicator
            zoomPresetsCapsuleRow
        }
        .frame(height: 74)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .highPriorityGesture(zoomDragGesture)
    }

    // MARK: - 底部专业控制台 (大快门 + 四联控制栏：相机、视频、媒体、设置)
    private var bottomProfessionalDashboard: some View {
        VStack(spacing: 12) {
            // 1. 中央核心快门控制行
            HStack {
                // 左侧：前后摄像头翻转
                Button(action: {
                    guard !cameraManager.isSwitchingCamera else { return }
                    impactFeedback.impactOccurred()
                    cameraManager.switchCamera()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(cameraManager.isSwitchingCamera ? 180 : 0))
                            .animation(.easeInOut(duration: 0.3), value: cameraManager.isSwitchingCamera)
                    }
                }
                .disabled(cameraManager.isSwitchingCamera)
                .frame(maxWidth: .infinity)
                .rotationEffect(.degrees(uiRotationAngle))
                .animation(.spring(response: 0.3), value: uiRotationAngle)
                
                // 中央核心大快门 (拍照 48MP / 视频 60fps)
                Button(action: handleMainShutterAction) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3.5)
                            .frame(width: 74, height: 74)
                        
                        if captureMode == 0 {
                            // 相机拍照模式 (白圈)
                            Circle()
                                .fill(cameraManager.isCapturingPhoto ? Color.gray : Color.white)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Group {
                                        if cameraManager.isCapturingPhoto {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        }
                                    }
                                )
                        } else {
                            // 视频录制模式 (红点 / 录制中方块)
                            if cameraManager.isRecordingVideo {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red)
                                    .frame(width: 28, height: 28)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 58, height: 58)
                            }
                        }
                    }
                }
                .contentShape(Circle())
                .disabled(cameraManager.isCapturingPhoto)
                .frame(maxWidth: .infinity)
                .rotationEffect(.degrees(uiRotationAngle))
                .animation(.spring(response: 0.3), value: uiRotationAngle)
                
                // 右侧：媒体相册快速预览 / 最新拍摄成片大图查看入口
                Button(action: {
                    selectionFeedback.selectionChanged()
                    showMediaGallery = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
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
            
            // 2. 底部四联专业导航栏：【相机】、【视频】、【媒体】、【设置】
            HStack(spacing: 0) {
                // 【相机】(拍照)
                bottomNavTabButton(
                    title: "相机",
                    systemIcon: "camera.fill",
                    isSelected: captureMode == 0
                ) {
                    selectionFeedback.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.15)) { captureMode = 0 }
                }
                
                // 【视频】(60fps 电影级视频录制)
                bottomNavTabButton(
                    title: "视频",
                    systemIcon: "video.fill",
                    isSelected: captureMode == 1
                ) {
                    selectionFeedback.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.15)) { captureMode = 1 }
                }
                
                // 【媒体】(相册与回放)
                bottomNavTabButton(
                    title: "媒体",
                    systemIcon: "square.grid.2x2.fill",
                    isSelected: false
                ) {
                    selectionFeedback.selectionChanged()
                    showMediaGallery = true
                }
                
                // 【设置】(系统与大模型 API 参数)
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
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .cornerRadius(16)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }
    
    // 底部导航单个按钮
    private func bottomNavTabButton(title: String, systemIcon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemIcon)
                    .font(.system(size: 18, weight: isSelected ? .bold : .medium))
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
    
    // MARK: - 快门触发核心逻辑
    private func handleMainShutterAction() {
        if captureMode == 0 {
            // 拍照流程: 48MP 高清捕捉 + 闪光动效 + 直存相册
            impactFeedback.impactOccurred()
            withAnimation(.easeInOut(duration: 0.08)) { isFlashing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.15)) { isFlashing = false }
            }
            
            cameraManager.capturePhoto { photo in
                guard let image = photo else { return }
                
                // 核心：若勾选启用了胶片 LUT 滤镜，则调用 Metal 渲染引擎将 3D LUT 片元着色烘焙至大图
                let finalImageToSave: UIImage
                if self.isLutFilterEnabled && self.activeLutName != "00-原画" {
                    finalImageToSave = MetalRenderer.shared.applyFilterToImage(image)
                } else {
                    finalImageToSave = image
                }
                
                // 1. 保存到系统相册
                UIImageWriteToSavedPhotosAlbum(finalImageToSave, nil, nil, nil)
                
                // 2. 存入当前 App 状态供在 App 内部立即查看成片
                self.lastCapturedPhoto = finalImageToSave
                self.lastCapturedFilterName = self.isLutFilterEnabled ? self.activeLutName : "00-原画 (RAW)"
                self.lastCapturedZoomFactor = self.cameraManager.currentZoomFactor
                self.lastCapturedDate = Date()
                
                // 3. 缩略图脉冲反馈
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    self.thumbnailScaleEffect = 1.25
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.thumbnailScaleEffect = 1.0
                    }
                }
                
                let toastTitle = self.isLutFilterEnabled ? "✓ 胶片成片已生成并存入相册" : "✓ 原画照片已保存至系统相册"
                self.showToast(toastTitle)
            }
        } else {
            // 视频流程: 60fps 视频录制直出 (若开启了滤镜则带滤镜，若未开启则原生原画直出)
            impactFeedback.impactOccurred()
            if cameraManager.isRecordingVideo {
                cameraManager.stopRecordingVideo()
                showToast("✓ 60fps 视频已保存至相册")
            } else {
                cameraManager.startRecordingVideo { recordedURL in
                    if recordedURL != nil {
                        showToast("✓ 60fps 视频已保存至相册")
                    }
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
    
    // MARK: - 触控对焦
    private func handleTapToFocus(at location: CGPoint, in size: CGSize) {
        focusDismissTask?.cancel()
        focusPoint = location
        focusRingScale = 1.35
        showFocusRing = true
        
        let focusX = location.x / size.width
        let focusY = location.y / size.height
        cameraManager.focus(at: CGPoint(x: focusX, y: focusY))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: task)
    }
    
    private var focusIndicatorView: some View {
        ZStack {
            Rectangle()
                .stroke(Color(red: 1.0, green: 0.85, blue: 0.2), lineWidth: 1.5)
                .frame(width: 64, height: 64)
                .scaleEffect(focusRingScale)
        }
    }
}

/// 上半圆拱形轨道导引 Shape
struct ArcDialTrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startAngle = Angle(degrees: 200)
        let endAngle = Angle(degrees: 340)
        let center = CGPoint(x: rect.midX, y: rect.height * 2.5)
        let radius = rect.height * 2.2
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

/// 媒体相册与最近成片专业检视弹窗 (支持在 App 内全屏检视带滤镜成片、手势缩放与系统分享)
struct MediaGallerySheet: View {
    @Environment(\.presentationMode) var presentationMode
    let lastPhoto: UIImage?
    let lutName: String
    let zoomFactor: CGFloat
    let captureDate: Date
    
    @State private var showShareSheet: Bool = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let photo = lastPhoto {
                    VStack(spacing: 0) {
                        Spacer()
                        
                        // 高清大图检视 (双击缩放与捏合缩放)
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
                        
                        // 底部专业黑金参数条 (胶卷、焦段、分辨率、拍摄时间)
                        VStack(spacing: 8) {
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
                                Text("✓ 已应用 3D LUT 胶片上色并存入相册")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.45))
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
                        .padding(.bottom, 20)
                    }
                } else {
                    // 无近期拍摄成片时的优雅占位
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 54))
                            .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                        
                        Text("暂无近期拍摄成片")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("轻触大快门即可拍摄，成片将自动烘焙电影胶卷色彩并在此高清检视。")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
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
                    if let photo = lastPhoto {
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
