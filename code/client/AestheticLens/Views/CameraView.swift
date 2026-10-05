import SwiftUI
import PhotosUI
import UIKit

/// 工业级专业全栈电影相机 UI
/// 完美融合参考图架构：
/// 1. 底部常驻四大核心导航：【相机】、【视频】、【媒体】、【设置】（移除无用聊天）
/// 2. 取景框右侧悬浮式 35mm 电影胶卷 3D LUT 选择器 (Filmstrip Reel) 与 [LUT] 快速开关
/// 3. 取景器全面直通 MetalView，所见即所得 120fps 高刷上色取景
/// 4. 视频录制直出 60fps 胶片滤镜视频，直接存入相册，零打扰流程
/// 5. 保持原有高品质沉浸黑金背景视觉风格、半圆弧变焦盘与原生触控对焦
public struct CameraView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var motionManager = MotionManager.shared
    @StateObject private var compositionEngine = RealtimeCompositionEngine.shared
    private let apiClient = APIClient.shared
    
    // MARK: - 模式与滤镜状态
    // 0: 相机 (拍照), 1: 视频 (60fps 电影级录像)
    @State private var captureMode: Int = 1
    @State private var activeLutName: String = "01-暖金电影"
    @State private var isFilmstripExpanded: Bool = true
    @State private var isLutFilterEnabled: Bool = true
    
    // AI 构图状态 (按需轻量触发)
    @State private var currentGuidance: CompositionGuidance?
    @State private var currentFilterRec: FilterRecommendation?
    @State private var isAnalyzingAI: Bool = false
    @State private var aiCoachMessage: String?
    
    // UI 交互与弹窗
    @State private var isFlashing: Bool = false
    @State private var showSettings: Bool = false
    @State private var showMediaPicker: Bool = false
    @State private var selectedMediaItem: PhotosPickerItem?
    @State private var toastMessage: String?
    
    // 半圆弧变焦轮状态 (0.5x ~ 10.0x)
    @State private var isZoomDialActive: Bool = false
    @State private var dragStartZoom: CGFloat = 1.0
    @State private var autoDismissTask: DispatchWorkItem?
    @State private var baseZoomFactor: CGFloat = 1.0
    @State private var showZoomIndicator: Bool = false
    
    // 原生触控对焦状态 (Tap-to-Focus)
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusRing: Bool = false
    @State private var focusRingScale: CGFloat = 1.35
    @State private var focusDismissTask: DispatchWorkItem?
    
    // 触觉反馈引擎
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    // MARK: - 专业电影胶卷 3D LUT 预设定义 (对标参考图)
    public struct FilmstripLutItem: Identifiable {
        public let id: String
        public let code: String
        public let name: String
        public let color: Color
        
        public var fullName: String {
            return "\(code)-\(name)"
        }
    }
    
    private let filmstripLuts: [FilmstripLutItem] = [
        FilmstripLutItem(id: "warm", code: "01", name: "暖金电影", color: Color(red: 1.0, green: 0.75, blue: 0.3)),
        FilmstripLutItem(id: "fuji", code: "02", name: "富士冷萃", color: Color(red: 0.35, green: 0.85, blue: 0.95)),
        FilmstripLutItem(id: "cyber", code: "03", name: "赛博青橙", color: Color(red: 1.0, green: 0.45, blue: 0.15)),
        FilmstripLutItem(id: "cinema", code: "04", name: "电影质感", color: Color(red: 0.88, green: 0.78, blue: 0.62)),
        FilmstripLutItem(id: "sunset", code: "05", name: "海边日落", color: Color(red: 0.95, green: 0.45, blue: 0.65)),
        FilmstripLutItem(id: "leica", code: "06", name: "徕卡黑白", color: Color(white: 0.85)),
        FilmstripLutItem(id: "raw", code: "00", name: "自然原画", color: Color(white: 0.55))
    ]
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 沉浸专业全黑背景 (保留原有高级背景 UI 风格)
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 顶部专业 HUD 面板
                topProfessionalHUD
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .zIndex(10)
                
                Spacer(minLength: 4)
                
                // 2. 取景器中枢 (120fps Metal 实时上色取景 + 悬浮胶卷滑轨 + 变焦轮)
                ZStack(alignment: .trailing) {
                    viewfinderContainer
                    
                    // 右侧悬浮电影胶卷 3D LUT 选择器 (参考图同款)
                    filmstripLutOverlayRail
                        .padding(.trailing, 10)
                }
                .frame(maxWidth: .infinity)
                .frame(height: UIScreen.main.bounds.width * (4.0 / 3.0))
                
                Spacer(minLength: 4)
                
                // 3. 底部专业控制台 (大快门 + 【相机】【视频】【媒体】【设置】四联控制栏)
                bottomProfessionalDashboard
                    .zIndex(10)
            }
            
            // 快门闪光反馈
            if isFlashing {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            
            // 顶部轻量 Toast 提示 (保存视频/照片直出提示)
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
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .zIndex(100)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .photosPicker(isPresented: $showMediaPicker, selection: $selectedMediaItem, matching: .any(of: [.images, .videos]))
        .onAppear {
            cameraManager.checkPermissions()
            cameraManager.startSession()
            motionManager.startUpdates()
            MetalRenderer.shared.applyPreset(isLutFilterEnabled ? activeLutName : "00-自然原画")
        }
    }
    
    // MARK: - 取景框容器 (Metal 实时上色 + 触控对焦 + AI 构图覆盖)
    private var viewfinderContainer: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            
            ZStack {
                if cameraManager.isAuthorized {
                    // 全面采用 MetalView 进行 120fps/60fps 实时着色渲染 (所见即所得)
                    MetalView(activePreset: isLutFilterEnabled ? activeLutName : "00-自然原画")
                        .frame(width: width, height: height)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleTapToFocus(at: location, in: CGSize(width: width, height: height))
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale in
                                    if !showZoomIndicator {
                                        baseZoomFactor = cameraManager.currentZoom
                                        showZoomIndicator = true
                                    }
                                    let target = (baseZoomFactor * scale * 10.0).rounded() / 10.0
                                    cameraManager.setZoom(factor: target)
                                }
                                .onEnded { _ in
                                    baseZoomFactor = cameraManager.currentZoom
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        showZoomIndicator = false
                                    }
                                }
                        )
                } else {
                    Color.black
                        .frame(width: width, height: height)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.gray)
                                Text("请授权相机权限以开启实时取景")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                            }
                        )
                }
                
                // 姿态水平仪 (0度金色吸附)
                LevelGaugeView(
                    roll: motionManager.roll,
                    pitch: motionManager.pitch,
                    isLevel: motionManager.isLevel
                )
                .allowsHitTesting(false)
                
                // AI 构图智能导引线层 (按需唤出)
                NavigationOverlayView(
                    guidance: currentGuidance,
                    filterRec: currentFilterRec,
                    isRealtimeActive: compositionEngine.isRealtimeActive
                )
                .allowsHitTesting(false)
                
                // 原生触控对焦金黄色呼吸框
                if showFocusRing, let pt = focusPoint {
                    focusIndicatorView
                        .position(pt)
                        .allowsHitTesting(false)
                }
                
                // 半圆弧刻度变焦盘 (0.5x ~ 10.0x)
                if isZoomDialActive {
                    arcZoomDial(width: width, height: height)
                }
            }
        }
    }
    
    // MARK: - 右侧悬浮电影胶卷 3D LUT 选择器 (Filmstrip Reel, 完美复刻参考图)
    private var filmstripLutOverlayRail: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // 1. 顶部滤镜总开关按钮 [开/关]
            Button(action: {
                selectionFeedback.selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLutFilterEnabled.toggle()
                }
                MetalRenderer.shared.applyPreset(isLutFilterEnabled ? activeLutName : "00-自然原画")
            }) {
                Text(isLutFilterEnabled ? "开" : "关")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isLutFilterEnabled ? .black : .white)
                    .frame(width: 32, height: 26)
                    .background(isLutFilterEnabled ? Color(red: 0.2, green: 0.6, blue: 1.0) : Color.white.opacity(0.2))
                    .cornerRadius(4)
            }
            
            // 2. 竖向 35mm 电影胶卷滑轨 (展开/收起)
            if isFilmstripExpanded {
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 5) {
                            ForEach(filmstripLuts) { item in
                                let isSelected = (activeLutName == item.fullName && isLutFilterEnabled)
                                
                                Button(action: {
                                    selectionFeedback.selectionChanged()
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        activeLutName = item.fullName
                                        isLutFilterEnabled = true
                                    }
                                    MetalRenderer.shared.applyPreset(item.fullName)
                                }) {
                                    HStack(spacing: 6) {
                                        // 胶片齿孔与编号名称
                                        Text(item.fullName)
                                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? .white : Color(white: 0.75))
                                            .lineLimit(1)
                                            .shadow(color: .black, radius: 2)
                                        
                                        // 胶卷色块缩略格 (对标参考图)
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(item.color.opacity(0.85))
                                                .frame(width: 22, height: 18)
                                            
                                            if isSelected {
                                                RoundedRectangle(cornerRadius: 3)
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [.red, .yellow, .green, .cyan, .blue, .purple],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 2
                                                    )
                                                    .frame(width: 26, height: 22)
                                            } else {
                                                RoundedRectangle(cornerRadius: 3)
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 4)
                                    .background(isSelected ? Color.white.opacity(0.18) : Color.clear)
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                    .frame(width: 110, height: 180)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            // 3. [LUT] 专业胶卷快捷徽标按钮 (参考图同款展开/折叠键)
            Button(action: {
                selectionFeedback.selectionChanged()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isFilmstripExpanded.toggle()
                }
            }) {
                HStack(spacing: 2) {
                    Text("LUT")
                        .font(.system(size: 10, weight: .black))
                    Circle()
                        .fill(isLutFilterEnabled ? Color(red: 0.2, green: 0.6, blue: 1.0) : Color.gray)
                        .frame(width: 4, height: 4)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(red: 0.15, green: 0.35, blue: 0.65).opacity(0.85))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            }
            
            // 4. 镜头倍率快捷徽标 (1x / 变焦切换)
            Button(action: {
                selectionFeedback.selectionChanged()
                withAnimation(.spring(response: 0.25)) {
                    isZoomDialActive.toggle()
                }
            }) {
                Text(String(format: "%.1fx", cameraManager.currentZoom))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                    .frame(width: 36, height: 26)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
        }
    }
    
    // MARK: - 顶部专业 HUD
    private var topProfessionalHUD: some View {
        HStack {
            // 分辨率与 60fps 标识 (所见即所得专业相机标头)
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
            
            Spacer()
            
            // 录像时长与呼吸灯指示
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
            }
            
            Spacer()
            
            // AI 实时构图指挥按钮 (按需开启，无人物智能风光建议)
            Button(action: {
                impactFeedback.impactOccurred()
                if compositionEngine.isRealtimeActive {
                    compositionEngine.stopRealtimeAnalysis()
                    currentGuidance = nil
                    currentFilterRec = nil
                } else {
                    compositionEngine.startRealtimeAnalysis { guidance, filterRec in
                        self.currentGuidance = guidance
                        self.currentFilterRec = filterRec
                    }
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: compositionEngine.isRealtimeActive ? "sparkles.rectangle.stack.fill" : "sparkles")
                        .font(.system(size: 12))
                    Text(compositionEngine.isRealtimeActive ? "AI 构图中" : "AI 构图")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(compositionEngine.isRealtimeActive ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(compositionEngine.isRealtimeActive ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - 底部专业控制台 (大快门 + 【相机】【视频】【媒体】【设置】四联控制栏，去除聊天)
    private var bottomProfessionalDashboard: some View {
        VStack(spacing: 12) {
            // 1. 中央大快门触发区与状态
            HStack {
                // 左侧辅助：快速翻转摄像头
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
                
                // 中央核心大快门 (相机拍照 / 60fps 电影视频录制)
                Button(action: handleMainShutterAction) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3.5)
                            .frame(width: 76, height: 76)
                        
                        if captureMode == 0 {
                            // 相机模式：白圈快门 (48MP 高清捕捉)
                            Circle()
                                .fill(cameraManager.isCapturingPhoto ? Color.gray : Color.white)
                                .frame(width: 62, height: 62)
                                .overlay(
                                    Group {
                                        if cameraManager.isCapturingPhoto {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        }
                                    }
                                )
                        } else {
                            // 视频模式：专业 60fps 电影红点录制按键
                            if cameraManager.isRecordingVideo {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red)
                                    .frame(width: 32, height: 32)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                            }
                        }
                    }
                }
                .contentShape(Circle())
                .disabled(cameraManager.isCapturingPhoto)
                .frame(maxWidth: .infinity)
                
                // 右侧辅助：AI 单帧分析与美学评分
                Button(action: triggerAICompositionCoaching) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 44, height: 44)
                        if isAnalyzingAI {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 18))
                                .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                        }
                    }
                }
                .disabled(isAnalyzingAI)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            
            // 2. 底部四大专业核心导航栏 (对标参考图：【相机】、【视频】、【媒体】、【设置】，去除聊天)
            HStack(spacing: 0) {
                // 1. 【相机】(拍照模式)
                bottomNavTabButton(
                    title: "相机",
                    systemIcon: "camera.fill",
                    isSelected: captureMode == 0
                ) {
                    selectionFeedback.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.15)) { captureMode = 0 }
                }
                
                // 2. 【视频】(60fps 录像模式)
                bottomNavTabButton(
                    title: "视频",
                    systemIcon: "video.fill",
                    isSelected: captureMode == 1
                ) {
                    selectionFeedback.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.15)) { captureMode = 1 }
                }
                
                // 3. 【媒体】(素材相册直达)
                bottomNavTabButton(
                    title: "媒体",
                    systemIcon: "film.stack",
                    isSelected: false
                ) {
                    selectionFeedback.selectionChanged()
                    showMediaPicker = true
                }
                
                // 4. 【设置】(系统与参数面板)
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
    
    // MARK: - 底部导航单个按钮组件
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
                showToast("✓ 48MP 照片已保存至相册")
            }
        } else {
            // 视频流程: 60fps 电影滤镜视频录制直出
            impactFeedback.impactOccurred()
            if cameraManager.isRecordingVideo {
                cameraManager.stopRecordingVideo()
                showToast("✓ 60fps 胶片视频已保存至相册")
            } else {
                cameraManager.startRecordingVideo { recordedURL in
                    if recordedURL != nil {
                        showToast("✓ 60fps 胶片视频已保存至相册")
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
    
    // MARK: - AI 构图美学单帧分析
    private func triggerAICompositionCoaching() {
        guard !isAnalyzingAI else { return }
        impactFeedback.impactOccurred()
        guard let currentImage = cameraManager.captureLatestPreviewFrame() else { return }
        
        isAnalyzingAI = true
        apiClient.analyzeFrameRealtime(image: currentImage) { result in
            DispatchQueue.main.async {
                self.isAnalyzingAI = false
                switch result {
                case .success(let data):
                    self.currentGuidance = data.compositionGuidance
                    self.currentFilterRec = data.filterRecommendation
                    if self.isLutFilterEnabled {
                        self.activeLutName = data.filterRecommendation.presetNameZh
                        MetalRenderer.shared.applyPreset(self.activeLutName)
                    }
                case .failure(let error):
                    print("[AI Coaching] 分析失败: \(error)")
                }
            }
        }
    }
    
    // MARK: - 原生触控对焦指示框 (Tap-to-Focus)
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
                .frame(width: 68, height: 68)
                .scaleEffect(focusRingScale)
            
            Group {
                Rectangle().fill(Color(red: 1.0, green: 0.85, blue: 0.2)).frame(width: 8, height: 1.5).offset(y: -34)
                Rectangle().fill(Color(red: 1.0, green: 0.85, blue: 0.2)).frame(width: 8, height: 1.5).offset(y: 34)
                Rectangle().fill(Color(red: 1.0, green: 0.85, blue: 0.2)).frame(width: 1.5, height: 8).offset(x: -34)
                Rectangle().fill(Color(red: 1.0, green: 0.85, blue: 0.2)).frame(width: 1.5, height: 8).offset(x: 34)
            }
        }
    }
    
    // MARK: - 半圆弧变焦盘 (Arc Zoom Dial)
    private func arcZoomDial(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { isZoomDialActive = false }
                }
            
            VStack {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 32)
                        .frame(width: width * 1.3, height: width * 1.3)
                        .offset(y: width * 0.45)
                    
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f×", cameraManager.currentZoom))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                        Text("滑动连续变焦")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .offset(y: -20)
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let delta = -value.translation.width / 120.0
                            let target = max(0.5, min(10.0, dragStartZoom + delta))
                            cameraManager.setZoom(factor: target)
                        }
                        .onEnded { _ in
                            dragStartZoom = cameraManager.currentZoom
                        }
                )
            }
        }
    }
}
