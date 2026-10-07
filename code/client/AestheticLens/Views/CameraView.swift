import SwiftUI
import AVFoundation

/// 工业级专业全栈电影相机 UI
/// 1. 变焦轮重构：位于快门正上方，常驻胶囊焦段 (.5, 1×, 2, 3)，滑动唤出上半圆弧形刻度盘 (Upper Arc Dial)
/// 2. AI 探景核心集成：一键触发阿里云 Qwen-VL 与端侧 Vision 双引擎，圈定黄金局部裁切框
/// 3. 全系统横屏拍摄：图标与文本根据重力感应原地顺畅旋转 90°/270°，底层照片与 60fps 视频锁定对应方向
/// 4. 严谨 4:3 / 16:9 几何保真，杜绝纵向拉伸变形
/// 5. 底部四联专业导航：【相机】、【视频】、【媒体】、【设置】
public struct CameraView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var motionManager = MotionManager.shared
    @StateObject private var compositionEngine = RealtimeCompositionEngine.shared
    private let apiClient = APIClient.shared
    
    // MARK: - 模式与滤镜状态 (0: 拍照, 1: 60fps 视频)
    @State private var captureMode: Int = 0
    @State private var activeLutName: String = "01-暖金电影"
    @State private var isFilmstripExpanded: Bool = true
    @State private var isLutFilterEnabled: Bool = true
    
    // UI 交互与弹窗
    @State private var isFlashing: Bool = false
    @State private var showSettings: Bool = false
    @State private var showMediaGallery: Bool = false
    @State private var toastMessage: String? = nil
    
    // 上半圆弧变焦盘交互状态
    @State private var isArcDialExpanded: Bool = false
    @State private var dragAccumulator: CGFloat = 0.0
    @State private var dialAutoCollapseWorkItem: DispatchWorkItem? = nil
    
    // 原生轻量触觉反馈
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // 触控对焦状态
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusRing: Bool = false
    @State private var focusRingScale: CGFloat = 1.0
    @State private var focusDismissTask: DispatchWorkItem? = nil
    
    public init() {}
    
    // 计算当前 UI 元素的旋转角度 (实现横屏拍摄自适应)
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
                
                // 2. 取景器中枢 (4:3 标准保真几何视口，严防上下拉伸变形)
                ZStack(alignment: .trailing) {
                    viewfinderContainer
                    
                    // 右侧悬浮 35mm 电影胶卷滑轨
                    filmstripLutOverlayRail
                        .padding(.trailing, 10)
                }
                .frame(maxWidth: .infinity)
                .frame(height: UIScreen.main.bounds.width * (4.0 / 3.0))
                .clipped()
                
                Spacer(minLength: 4)
                
                // 3. 变焦轮区域 (位于快门正上方：上半圆弧形刻度盘 / 焦段胶囊行)
                upperArcZoomControlView
                    .zIndex(20)
                
                // 4. 底部专业控制台 (大快门 + 四联导航)
                bottomProfessionalDashboard
                    .zIndex(10)
            }
            
            // 拍照瞬间曝光闪光特效
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
            MediaGallerySheet()
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
                
                Text("P3 WIDE")
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
            
            // ✨ AI 探景按钮 (核心触发：阿里云多模态大模型分析场景并圈出黄金机位)
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
                    
                    Text(isAnalyzing ? "AI 探景中..." : (isEngineActive ? "构图指引中" : "AI 探景"))
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
    
    // AI 探景点击响应
    private func handleAITrigger() {
        impactFeedback.impactOccurred()
        if compositionEngine.state != .inactive {
            compositionEngine.stopRealtimeGuidance()
        } else {
            compositionEngine.startRealtimeGuidance(cameraManager: cameraManager)
        }
    }
    
    // MARK: - 取景器视口 (4:3 比例保真，带 Metal 上色预览与 AR 构图浮层)
    private var viewfinderContainer: some View {
        GeometryReader { proxy in
            ZStack {
                // 1. Metal 实时高刷取景 (支持 3D LUT 即时着色)
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
    
    // MARK: - 右侧悬浮 35mm 胶卷选择器
    private var filmstripLutOverlayRail: some View {
        VStack(spacing: 8) {
            // 胶卷折叠/展开按钮
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
                let presets = ["01-暖金电影", "02-富士冷萃", "03-赛博青橙", "04-电影质感", "06-徕卡黑白"]
                ForEach(presets, id: \.self) { preset in
                    let isSelected = (preset == activeLutName && isLutFilterEnabled)
                    Button(action: {
                        selectionFeedback.selectionChanged()
                        activeLutName = preset
                        isLutFilterEnabled = true
                        MetalRenderer.shared.applyPreset(preset)
                    }) {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSelected ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.white.opacity(0.35))
                                .frame(width: 24, height: 3)
                            
                            Text(preset.prefix(2))
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
    
    // MARK: - 快门正上方：上半圆弧形变焦轮 (Upper Arc Dial)
    private var upperArcZoomControlView: some View {
        VStack(spacing: 6) {
            if isArcDialExpanded {
                // 1. 展开模式：优雅的上半圆弧度连续拨盘 (像苹果原生相机一样丝滑)
                arcDialExpandedView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                // 2. 常驻收起模式：精巧焦段胶囊行 (.5, 1×, 2, 3)
                compactZoomCapsulesRow
                    .transition(.opacity)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
    }
    
    // 常驻紧凑焦段胶囊 (.5, 1×, 2, 3)
    private var compactZoomCapsulesRow: some View {
        HStack(spacing: 12) {
            let presets: [(label: String, val: CGFloat)] = [
                (".5", 0.5),
                ("1×", 1.0),
                ("2", 2.0),
                ("3", 3.0)
            ]
            
            ForEach(presets, id: \.val) { item in
                let isCurrent = abs(cameraManager.currentZoom - item.val) < 0.2
                Button(action: {
                    selectionFeedback.selectionChanged()
                    cameraManager.setZoom(factor: item.val)
                }) {
                    Text(item.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isCurrent ? Color(red: 1.0, green: 0.88, blue: 0.35) : .white)
                        .frame(width: 36, height: 36)
                        .background(isCurrent ? Color.black.opacity(0.8) : Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isCurrent ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.white.opacity(0.2), lineWidth: isCurrent ? 1.5 : 0.8)
                        )
                }
                .rotationEffect(.degrees(uiRotationAngle))
                .animation(.spring(response: 0.3), value: uiRotationAngle)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
        // 水平滑动或按住即可展开上半圆弧度变焦轮
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { _ in
                    selectionFeedback.selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isArcDialExpanded = true
                    }
                    resetDialCollapseTimer()
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isArcDialExpanded.toggle()
            }
        }
    }
    
    // 展开的上半圆弧刻度盘视图
    private var arcDialExpandedView: some View {
        ZStack {
            // 背景圆弧滑槽 (向上拱起)
            ArcDialShape()
                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                .frame(width: 260, height: 42)
            
            // 弧线上分布的微刻度线与当前数字指示
            HStack(spacing: 16) {
                Text(String(format: "%.1f×", cameraManager.currentZoom))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(red: 1.0, green: 0.88, blue: 0.35), lineWidth: 1))
            }
            .offset(y: -4)
        }
        .frame(width: 280, height: 48)
        .contentShape(Rectangle())
        // 左右拖拽实现连续无级变焦
        .gesture(
            DragGesture()
                .onChanged { value in
                    let delta = -value.translation.width / 140.0
                    let target = max(0.5, min(10.0, cameraManager.currentZoom + delta * 0.15))
                    let roundedTarget = (target * 10).rounded() / 10
                    if roundedTarget != cameraManager.currentZoom {
                        selectionFeedback.selectionChanged()
                        cameraManager.setZoom(factor: roundedTarget)
                    }
                    resetDialCollapseTimer()
                }
                .onEnded { _ in
                    resetDialCollapseTimer()
                }
        )
    }
    
    // 延迟 2.5 秒自动收起变焦弧盘
    private func resetDialCollapseTimer() {
        dialAutoCollapseWorkItem?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) {
                self.isArcDialExpanded = false
            }
        }
        dialAutoCollapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }
    
    // MARK: - 底部专业控制台 (大快门 + 四联控制栏：相机、视频、媒体、设置)
    private var bottomProfessionalDashboard: some View {
        VStack(spacing: 14) {
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
                
                // 右侧：媒体相册快速预览
                Button(action: {
                    selectionFeedback.selectionChanged()
                    showMediaGallery = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 18))
                            .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
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
            .padding(.bottom, 8)
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
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                showToast("✓ 照片已保存至系统相册")
            }
        } else {
            // 视频流程: 60fps 电影滤镜视频录制直出
            impactFeedback.impactOccurred()
            if cameraManager.isRecordingVideo {
                cameraManager.stopRecordingVideo()
                showToast("✓ 60fps 电影视频已保存至相册")
            } else {
                cameraManager.startRecordingVideo { recordedURL in
                    if recordedURL != nil {
                        showToast("✓ 60fps 电影视频已保存至相册")
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

/// 上半圆拱形轨道 Shape (用于变焦盘)
struct ArcDialShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startAngle = Angle(degrees: 195)
        let endAngle = Angle(degrees: 345)
        let center = CGPoint(x: rect.midX, y: rect.height * 2.2)
        let radius = rect.height * 2.0
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

/// 媒体相册弹窗
struct MediaGallerySheet: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 48))
                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    .padding(.top, 40)
                
                Text("成片直存系统相册")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("所有拍摄的照片与 60fps 视频均已由零拷贝管线无损存入您的 iOS 系统相册中。可在相册 App 中随时检视与分享。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("媒体库")
            .navigationBarItems(trailing: Button("完成") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
