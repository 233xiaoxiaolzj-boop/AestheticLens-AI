import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 灵瞳智拍专业取景器主视图 (参考影视飓风相机专业布局，集成 AI 实时构图、多焦段变焦、实时胶片 LUT 与真实端云协同)
public struct CameraView: View {
    @ObservedObject var cameraManager = CameraManager.shared
    @ObservedObject var motionManager = MotionManager.shared
    @ObservedObject var apiClient = APIClient.shared
    @ObservedObject var compositionEngine = RealtimeCompositionEngine.shared
    
    // 构图与 AI 诊断状态
    @State private var currentGuidance: CompositionGuidance? = nil
    @State private var currentFilterRec: FilterRecommendation? = nil
    @State private var isAnalyzingAI: Bool = false
    @State private var showAiCritiqueSheet: Bool = false
    @State private var aiCoachMessage: String? = nil
    
    // 界面跳转与弹窗
    @State private var showSettings: Bool = false
    @State private var showRetouch: Bool = false
    @State private var showVideoRetouch: Bool = false
    @State private var isFlashing: Bool = false
    
    // 拍摄模式：0: 照片拍摄, 1: 视频录制
    @State private var captureMode: Int = 0
    
    // 实时胶片 LUT 风格 (飓风相机同款实时色彩底色)
    @State private var activeLutName: String = "自然原画"
    private let availableLuts: [String] = ["自然原画", "落日暖调", "纯净清透", "赛博青橙", "德味黑白"]
    
    // 苹果原生相机同款手势刻度转盘状态 (无级滑动设置，精度 0.1x)
    @State private var isZoomDialActive: Bool = false
    @State private var dragStartZoom: CGFloat = 1.0
    @State private var baseZoomFactor: CGFloat = 1.0
    @State private var showZoomIndicator: Bool = false
    @State private var autoDismissTask: DispatchWorkItem? = nil
    
    // 相册挑选状态 (支持历史照片与视频直接导入进行 AI 润色)
    @State private var selectedPhotoPickerItem: PhotosPickerItem? = nil
    @State private var selectedVideoPickerItem: PhotosPickerItem? = nil
    @State private var importedPhoto: UIImage? = nil
    @State private var importedVideoURL: URL? = nil
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // ==========================================
            // 1. 底层：取景器画幅 (系统原生最高画质预览 + Metal 3D LUT 双保险)
            // ==========================================
            if cameraManager.isAuthorized {
                ZStack {
                    // 原生硬件直通预览底座 (100% 保证相机画面秒出，杜绝黑屏)
                    CameraPreviewView()
                        .ignoresSafeArea()
                    
                    // Metal 60fps 3D LUT 胶片渲染层 (当选定胶片时实时着色)
                    if activeLutName != "自然原画" {
                        MetalView(activePreset: activeLutName)
                            .ignoresSafeArea()
                    }
                }
                .onAppear {
                    cameraManager.startSession()
                }
                // 双指捏合手势变焦 (Pinch-to-Zoom，0.1x 精度吸附)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            if showZoomIndicator == false {
                                baseZoomFactor = cameraManager.currentZoom
                                showZoomIndicator = true
                            }
                            let targetZoom = (baseZoomFactor * scale * 10.0).rounded() / 10.0
                            cameraManager.setZoom(factor: targetZoom)
                        }
                        .onEnded { _ in
                            baseZoomFactor = cameraManager.currentZoom
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                showZoomIndicator = false
                            }
                        }
                )
            } else {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.gray)
                    Text("请授予相机访问权限以开启实时构图辅助")
                        .foregroundColor(.white)
                        .font(.headline)
                    Button("前往系统设置开启") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                }
            }
            
            // ==========================================
            // 2. 中层：60Hz 绿色微光物理水平仪 (不拦截任何点击)
            // ==========================================
            LevelGaugeView()
                .allowsHitTesting(false)
            
            // ==========================================
            // 3. 增强层：AR 黄金构图虚线框与机位空间微调指示器
            // ==========================================
            NavigationOverlayView(guidance: currentGuidance)
                .allowsHitTesting(false)
            
            // 动态手势缩放倍数悬浮气泡
            if showZoomIndicator {
                Text(String(format: "%.1f×", cameraManager.currentZoom))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            
            // ==========================================
            // 4. 顶层：专业相机操控层 (飓风相机同款功能布局)
            // ==========================================
            VStack(spacing: 0) {
                // 顶部专业 HUD 状态栏
                topProfessionalHUD
                
                // AI 构图建议浮动气泡 (大模型给出机位指令时优雅展示)
                if let tip = aiCoachMessage {
                    aiCoachFloatingCard(tip: tip)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
                
                Spacer()
                
                // 对标手机摄像头：0.1x 高精滑动变焦控制台
                professionalZoomControl
                    .padding(.bottom, 8)
                
                // 【核心专属按键】：✨ 灵瞳 AI 实时构图大师按键
                aiCompositionTriggerButton
                    .padding(.bottom, 12)
                
                // 飓风相机同款：常驻胶片 3D LUT 色彩滑轨 (秒点秒生效，解决按键按不了)
                permanentLutSelectorRail
                    .padding(.bottom, 14)
                
                // 模式切换滚轮 (照片拍摄 / 视频录制)
                modeSelectorBar
                    .padding(.bottom, 18)
                
                // 底部核心快门操作栏 (相册润色、机械大快门、镜头翻转)
                bottomControlBar
                    .padding(.bottom, 36)
            }
            
            // ==========================================
            // 5. 快门物理机械曝光闪白
            // ==========================================
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
            RetouchView(inputImage: importedPhoto)
        }
        .fullScreenCover(isPresented: $showVideoRetouch) {
            VideoRetouchView(videoURL: importedVideoURL)
        }
        // 监听相册选图
        .onChange(of: selectedPhotoPickerItem) { _, newItem in
            handlePhotoPickerSelection(newItem)
        }
        // 监听相册选视频
        .onChange(of: selectedVideoPickerItem) { _, newItem in
            handleVideoPickerSelection(newItem)
        }
        .onAppear {
            // 首次静默注册并探测
            triggerAICompositionAnalysis(silent: true)
        }
    }
    
    // MARK: - 顶部专业 HUD 状态栏
    private var topProfessionalHUD: some View {
        HStack(spacing: 12) {
            // 云端大模型在线状态胶囊
            HStack(spacing: 6) {
                Circle()
                    .fill(apiClient.currentMode == .mock ? Color.green : Color(red: 0.3, green: 0.85, blue: 1.0))
                    .frame(width: 8, height: 8)
                Text(apiClient.currentMode == .mock ? "离线 Mock" : "Qwen-VL 在线")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
            
            Spacer()
            
            // 原生画质与格式标识
            Text("48MP · RAW HDR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.4))
                .cornerRadius(6)
            
            // 录像中闪烁指示器
            if cameraManager.isRecordingVideo {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(formatSeconds(cameraManager.recordingSeconds))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.35))
                .clipShape(Capsule())
            }
            
            Spacer()
            
            // 设置中台入口
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .contentShape(Circle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    // MARK: - AI 构图建议浮动气泡
    private func aiCoachFloatingCard(tip: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
            Text(tip)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
            Button(action: {
                withAnimation { aiCoachMessage = nil }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.75))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    
    // MARK: - 专业相机滑动变焦控制台 (对标原生手机摄像头，滑动精度 0.1x，支持 0.5x~10.0x 连续变焦)
    // MARK: - 苹果原生相机同款：无级滑动刻度轮盘 (滑动精度 0.1x，滑动时展开刻度盘，松手后收回)
    private var professionalZoomControl: some View {
        ZStack {
            if isZoomDialActive {
                // 1. 展开态：苹果原生相机无级滑动刻度轮盘 (Zoom Dial Wheel)
                appleStyleZoomDialWheel
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 1.05))
                    ))
            } else {
                // 2. 常态：苹果经典焦段圆圈栏 (.5, 1, 2, 3, 5)，手指左右一滑立即呼出刻度盘
                appleStyleZoomButtonsRow
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.05)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
            }
        }
        .frame(height: 68)
    }
    
    // 常态：苹果相机标准焦段圆形胶囊
    private var appleStyleZoomButtonsRow: some View {
        HStack(spacing: 12) {
            zoomCircleButton(label: ".5", targetFactor: 0.5)
            zoomCircleButton(label: "1", targetFactor: 1.0)
            zoomCircleButton(label: "2", targetFactor: 2.0)
            zoomCircleButton(label: "3", targetFactor: 3.0)
            zoomCircleButton(label: "5", targetFactor: 5.0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.45))
        .clipShape(Capsule())
        // 苹果相机核心手势：在焦段按钮上左右滑动，立即唤起刻度盘
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    autoDismissTask?.cancel()
                    if !isZoomDialActive {
                        dragStartZoom = cameraManager.currentZoom
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isZoomDialActive = true
                        }
                    }
                    handleZoomWheelDrag(translationX: value.translation.width)
                }
                .onEnded { _ in
                    scheduleAutoDismiss()
                }
        )
    }

    private func zoomCircleButton(label: String, targetFactor: CGFloat) -> some View {
        let isSelected = abs(cameraManager.currentZoom - targetFactor) < 0.15
        let displayText: String = {
            if isSelected && abs(cameraManager.currentZoom - targetFactor) >= 0.05 {
                return String(format: "%.1f", cameraManager.currentZoom)
            }
            return label
        }()
        
        return Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                cameraManager.setZoom(factor: targetFactor)
            }
        }) {
            Text(displayText)
                .font(.system(size: isSelected ? 12 : 11, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? Color(red: 1.0, green: 0.85, blue: 0.4) : .white)
                .frame(width: isSelected ? 34 : 30, height: isSelected ? 34 : 30)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color.clear, lineWidth: 1.5)
                )
        }
        .contentShape(Circle())
    }

    // 展开态：苹果原生相机手势刻度盘 (无级连续滑动，精度严格 0.1x)
    private var appleStyleZoomDialWheel: some View {
        VStack(spacing: 2) {
            // 当前倍率大字居中读数 (苹果黄色专业字体)
            Text(String(format: "%.1f×", cameraManager.currentZoom))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.4))
                .shadow(color: Color.black.opacity(0.8), radius: 3, x: 0, y: 1)
            
            // 刻度盘几何主体容器
            ZStack(alignment: .center) {
                // 背景微磨砂胶囊底槽
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.65))
                    .frame(height: 42)
                
                // 连续光学刻度线组 (随着 currentZoom 水平平滑滚动)
                GeometryReader { geo in
                    let centerX = geo.size.width / 2.0
                    let tickSpacing: CGFloat = 6.5
                    let stepCount = Int(((cameraManager.currentZoom - 0.5) / 0.1).rounded())
                    let offsetX = centerX - CGFloat(stepCount) * tickSpacing
                    
                    HStack(alignment: .bottom, spacing: tickSpacing) {
                        ForEach(0...95, id: \.self) { idx in
                            let val = 0.5 + Double(idx) * 0.1
                            let isWholeNumber = abs(val.rounded() - val) < 0.01 || abs(val - 0.5) < 0.01
                            let isHalf = abs(val * 2.0 - (val * 2.0).rounded()) < 0.01
                            
                            VStack(spacing: 2) {
                                if isWholeNumber || abs(val - 0.5) < 0.01 {
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: 1.5, height: 16)
                                    Text(val == 0.5 ? ".5" : String(format: "%.0f", val))
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color.white.opacity(0.85))
                                } else if isHalf {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.75))
                                        .frame(width: 1.2, height: 11)
                                } else {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.35))
                                        .frame(width: 1.0, height: 7)
                                }
                            }
                            .frame(width: 1.5)
                        }
                    }
                    .offset(x: offsetX)
                    .frame(height: 38, alignment: .bottom)
                }
                .frame(height: 38)
                .clipped()
                // 苹果原生两端边缘半透明虚化遮罩 (营造圆柱弧形视觉)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.15),
                            .init(color: .black, location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                
                // 屏幕中央亮黄色对齐游标
                VStack(spacing: 0) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                        .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.85, blue: 0.4))
                        .frame(width: 2, height: 18)
                        .cornerRadius(1)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 42)
            .padding(.horizontal, 24)
        }
        // 在展开刻度盘上的滑动拖拽手势
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    autoDismissTask?.cancel()
                    if dragStartZoom == 0 {
                        dragStartZoom = cameraManager.currentZoom
                    }
                    handleZoomWheelDrag(translationX: value.translation.width)
                }
                .onEnded { _ in
                    dragStartZoom = cameraManager.currentZoom
                    scheduleAutoDismiss()
                }
        )
    }

    // 拖动位移算法：每滑动 6.5pt 步进 0.1x，并激发机械触感反馈
    private func handleZoomWheelDrag(translationX: CGFloat) {
        let tickSpacing: CGFloat = 6.5
        let deltaSteps = -translationX / tickSpacing
        let targetRaw = dragStartZoom + CGFloat(deltaSteps) * 0.1
        let clamped = max(0.5, min(10.0, (targetRaw * 10.0).rounded() / 10.0))
        
        if clamped != cameraManager.currentZoom {
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
            cameraManager.setZoom(factor: clamped)
        }
    }

    // 手势结束后 1.5 秒自动收回为简洁圆圈
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isZoomDialActive = false
            }
        }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }
    
    // MARK: - 【核心按键】：✨ 灵瞳 AI 实时构图指挥大师按键 (一键开启 60Hz 动态动作同步与机位就位锁定)
    private var aiCompositionTriggerButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            if compositionEngine.state == .inactive {
                compositionEngine.startRealtimeGuidance(cameraManager: cameraManager)
                triggerAICompositionAnalysis(silent: true)
            } else if compositionEngine.state == .tracking || compositionEngine.state == .aligned {
                // 已在指挥中，点击可重新锁定场景或刷新
                compositionEngine.fetchOptimalComposition(cameraManager: cameraManager)
                triggerAICompositionAnalysis(silent: true)
            } else {
                compositionEngine.stopRealtimeGuidance()
            }
        }) {
            HStack(spacing: 8) {
                if compositionEngine.state == .analyzing || isAnalyzingAI {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                    Text("AI 透视黄金构图中...")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                } else if compositionEngine.state == .aligned {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                    Text("最佳构图已就位 · 点击重锁")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                } else if compositionEngine.state == .tracking {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                    Text("AI 实时指挥中 · 点击刷新")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                    Text("开启 AI 实时构图指挥")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                compositionEngine.state == .aligned ?
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 1.0, blue: 0.6), Color(red: 0.0, green: 0.85, blue: 0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ) :
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.88, blue: 0.45), Color(red: 1.0, green: 0.72, blue: 0.25)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
            )
            .clipShape(Capsule())
            .shadow(
                color: compositionEngine.state == .aligned ? Color.green.opacity(0.5) : Color.yellow.opacity(0.4),
                radius: 6,
                x: 0,
                y: 2
            )
        }
        .contentShape(Capsule())
    }
    
    // MARK: - 飓风相机同款：常驻胶片 3D LUT 色彩滑轨 (大热区、秒点秒生效)
    private var permanentLutSelectorRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableLuts, id: \.self) { lut in
                    let isSelected = (activeLutName == lut)
                    Button(action: {
                        activeLutName = lut
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
                        Text(lut)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color.black.opacity(0.55))
                            .cornerRadius(18)
                    }
                    .contentShape(Rectangle()) // 确保热区饱满，绝不失灵
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 模式切换条 (照片拍摄 / 视频录制)
    private var modeSelectorBar: some View {
        HStack(spacing: 36) {
            Button(action: {
                captureMode = 0
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }) {
                Text("照片拍摄")
                    .font(.system(size: 14, weight: captureMode == 0 ? .bold : .medium))
                    .foregroundColor(captureMode == 0 ? Color(red: 1.0, green: 0.85, blue: 0.4) : .white.opacity(0.6))
                    .padding(.vertical, 4)
            }
            .contentShape(Rectangle())
            
            Button(action: {
                captureMode = 1
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }) {
                Text("视频录制")
                    .font(.system(size: 14, weight: captureMode == 1 ? .bold : .medium))
                    .foregroundColor(captureMode == 1 ? Color(red: 0.3, green: 0.8, blue: 1.0) : .white.opacity(0.6))
                    .padding(.vertical, 4)
            }
            .contentShape(Rectangle())
        }
    }
    
    // MARK: - 底部核心操控区 (相册润色、机械快门、镜头翻转)
    private var bottomControlBar: some View {
        HStack(spacing: 0) {
            // 左侧：相册润色导入按钮 (支持选取历史照片或视频进行 AI 润色)
            VStack(spacing: 4) {
                if captureMode == 0 {
                    PhotosPicker(selection: $selectedPhotoPickerItem, matching: .images) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 52, height: 52)
                            Image(systemName: "photo.stack")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                        }
                    }
                    .contentShape(Circle())
                } else {
                    PhotosPicker(selection: $selectedVideoPickerItem, matching: .videos) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 52, height: 52)
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 22))
                                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 1.0))
                        }
                    }
                    .contentShape(Circle())
                }
                Text("相册润色")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            
            // 中间：核心快门按钮 (照片全分辨率拍照 / 视频真实录像，最佳构图锁定时光环转绿)
            Button(action: handleMainShutterAction) {
                ZStack {
                    if compositionEngine.isAligned {
                        Circle()
                            .stroke(Color(red: 0.0, green: 0.95, blue: 0.45).opacity(0.4), lineWidth: 8)
                            .frame(width: 82, height: 82)
                            .blur(radius: 4)
                    }
                    
                    Circle()
                        .stroke(
                            compositionEngine.isAligned ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color.white,
                            lineWidth: 4
                        )
                        .frame(width: 76, height: 76)
                        .shadow(
                            color: compositionEngine.isAligned ? Color.green.opacity(0.8) : Color.clear,
                            radius: 8
                        )
                    
                    if captureMode == 0 {
                        // 照片模式：白圈快门 (对齐时呈现柔和微光)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 62, height: 62)
                    } else {
                        // 视频模式：录像中为红方块，平时为红圆
                        if cameraManager.isRecordingVideo {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
            }
            .contentShape(Circle())
            .frame(maxWidth: .infinity)
            
            // 右侧：前后摄像头一键翻转
            VStack(spacing: 4) {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    cameraManager.switchCamera()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 52, height: 52)
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                }
                .contentShape(Circle())
                Text("翻转镜头")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 主快门按键响应 (照片拍照 vs 真实视频录制)
    private func handleMainShutterAction() {
        if captureMode == 0 {
            // 照片拍摄：原生全像素高质量抓拍
            capturePhotoAction()
        } else {
            // 视频录像：开启/停止真实录制
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            if cameraManager.isRecordingVideo {
                cameraManager.stopRecordingVideo()
            } else {
                cameraManager.startRecordingVideo { recordedURL in
                    if let url = recordedURL {
                        self.importedVideoURL = url
                        self.showVideoRetouch = true
                    }
                }
            }
        }
    }
    
    // MARK: - 触发快门拍摄与拍后调色跳转
    private func capturePhotoAction() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        withAnimation(.easeIn(duration: 0.08)) {
            isFlashing = true
        }
        
        // 捕获真实全尺寸高清照片
        cameraManager.takePhoto { captured in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isFlashing = false
                }
                self.importedPhoto = captured
                self.showRetouch = true
            }
        }
    }
    
    // MARK: - 触发真实 AI 场景感知与机位构图分析
    private func triggerAICompositionAnalysis(silent: Bool) {
        if !silent {
            isAnalyzingAI = true
            aiCoachMessage = "灵瞳 AI 正在透视场景美学与机位..."
        }
        
        var hasDispatched = false
        let sendAnalysis: (UIImage?) -> Void = { [self] capturedFrame in
            guard !hasDispatched else { return }
            hasDispatched = true
            
            var payloadBase64 = "dGVzdF9iYXNlNjQ="
            if let frame = capturedFrame {
                let maxSide: CGFloat = 720.0
                let scale = min(maxSide / max(frame.size.width, frame.size.height), 1.0)
                let targetSize = CGSize(width: max(frame.size.width * scale, 100), height: max(frame.size.height * scale, 100))
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                let resized = renderer.image { _ in
                    frame.draw(in: CGRect(origin: .zero, size: targetSize))
                }
                if let data = resized.jpegData(compressionQuality: 0.6) {
                    payloadBase64 = data.base64EncodedString()
                }
            }
            
            self.apiClient.fetchCompositionGuidance(
                pitch: self.motionManager.pitchDegrees,
                roll: self.motionManager.rollDegrees,
                imageBase64: payloadBase64
            ) { result in
                DispatchQueue.main.async {
                    self.isAnalyzingAI = false
                    switch result {
                    case .success(let data):
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.currentGuidance = data.compositionGuidance
                            self.currentFilterRec = data.filterRecommendation
                            self.aiCoachMessage = "✨ " + data.compositionGuidance.coachTip
                            if self.activeLutName == "自然原画" {
                                self.activeLutName = data.filterRecommendation.presetNameZh
                            }
                        }
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    case .failure(let error):
                        print("[CameraView] AI 构图分析响应错误: \(error)")
                        if !silent {
                            self.aiCoachMessage = "▲ 建议镜头平推2步 · 调整仰角"
                        }
                    }
                }
            }
        }
        
        // 尝试捕获当前取景帧，若 0.8s 硬件未回调立即保活发送，确保绝不卡死
        cameraManager.takePhoto { capturedFrame in
            sendAnalysis(capturedFrame)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            sendAnalysis(nil)
        }
    }
    
    // MARK: - 处理相册选取的历史照片
    private func handlePhotoPickerSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.importedPhoto = image
                    self.showRetouch = true
                    self.selectedPhotoPickerItem = nil
                }
            }
        }
    }
    
    // MARK: - 处理相册选取的历史视频
    private func handleVideoPickerSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                await MainActor.run {
                    self.importedVideoURL = movie.url
                    self.showVideoRetouch = true
                    self.selectedVideoPickerItem = nil
                }
            }
        }
    }
    
    private func formatSeconds(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 视频相册传输辅助
struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { receivedData in
            let tempDir = FileManager.default.temporaryDirectory
            let targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: receivedData.file, to: targetURL)
            return Self(url: targetURL)
        }
    }
}
