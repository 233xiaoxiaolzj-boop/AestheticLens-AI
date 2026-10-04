import SwiftUI
import PhotosUI
import UIKit

/// 工业级专业全栈 AI 相机主界面
/// 对标苹果原生相机与影视飓风相机 (StormCam)：
/// 1. 原生 4:3 黄金传感器视口：人脸自拍绝无畸变拉伸，前置镜像完美对齐原相机
/// 2. 120fps 极速 Canvas 单层刻度盘：镜头倍率连续手势滑动如丝般顺滑，精度 0.1x
/// 3. 全局线程并发互斥与防抖：连点快门/翻转镜头绝不卡死，点选任何选项均毫秒级响应
/// 4. 实时视频流无感抽帧：AI 构图透视 0 秒取帧，彻底移除物理快门拍照阻塞
public struct CameraView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var motionManager = MotionManager.shared
    @StateObject private var compositionEngine = RealtimeCompositionEngine.shared
    private let apiClient = APIClient.shared
    
    // UI 控制状态
    @State private var activeLutName: String = "自然原画"
    @State private var currentGuidance: CompositionGuidance?
    @State private var currentFilterRec: FilterRecommendation?
    @State private var isAnalyzingAI: Bool = false
    @State private var aiCoachMessage: String?
    
    // 拍摄模式：0 为拍照，1 为录像
    @State private var captureMode: Int = 0
    @State private var isFlashing: Bool = false
    @State private var showSettings: Bool = false
    
    // 拍后/导入编辑跳转
    @State private var importedPhoto: UIImage?
    @State private var showRetouch: Bool = false
    @State private var importedVideoURL: URL?
    @State private var showVideoRetouch: Bool = false
    
    // 相册选择器
    @State private var selectedPhotoPickerItem: PhotosPickerItem?
    @State private var selectedVideoPickerItem: PhotosPickerItem?
    
    // 变焦手势与刻度盘状态
    @State private var isZoomDialActive: Bool = false
    @State private var dragStartZoom: CGFloat = 1.0
    @State private var autoDismissTask: DispatchWorkItem?
    @State private var baseZoomFactor: CGFloat = 1.0
    @State private var showZoomIndicator: Bool = false
    
    // 预热震动反馈器 (避免高频分配内存引起卡顿)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // 胶片预设
    private let availableLuts: [(name: String, tag: String, color: Color)] = [
        ("自然原画", "RAW", Color.gray),
        ("经典胶片", "KODAK", Color(red: 1.0, green: 0.6, blue: 0.2)),
        ("清透日系", "FUJI", Color(red: 0.4, green: 0.85, blue: 0.7)),
        ("赛博朋克", "TEAL", Color(red: 0.2, green: 0.8, blue: 1.0)),
        ("黑白高反差", "BW", Color.white)
    ]
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                topProfessionalHUD
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                
                viewfinderContainer
                    .padding(.horizontal, 8)
                
                controlsContainer
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
        .onChange(of: selectedPhotoPickerItem) { _, newItem in
            handlePhotoPickerSelection(newItem)
        }
        .onChange(of: selectedVideoPickerItem) { _, newItem in
            handleVideoPickerSelection(newItem)
        }
        .onAppear {
            selectionFeedback.prepare()
            impactFeedback.prepare()
            cameraManager.startSession()
        }
    }
    
    // MARK: - 4:3 视口容器
    private var viewfinderContainer: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let targetHeight = availableWidth * (4.0 / 3.0)
            
            ZStack {
                if cameraManager.isAuthorized {
                    CameraPreviewView()
                        .frame(width: availableWidth, height: targetHeight)
                        .clipped()
                        .contentShape(Rectangle())
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
                        .frame(width: availableWidth, height: targetHeight)
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("请允许相机访问权限")
                                    .foregroundColor(.white)
                                    .font(.subheadline)
                            }
                        )
                }
                
                LevelGaugeView()
                    .allowsHitTesting(false)
                
                NavigationOverlayView(guidance: currentGuidance)
                    .allowsHitTesting(false)
                
                if showZoomIndicator {
                    Text(String(format: "%.1f×", cameraManager.currentZoom))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                
                if isFlashing {
                    Color.white
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: availableWidth, height: min(targetHeight, geo.size.height), alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
    
    // MARK: - 下方操控台容器
    private var controlsContainer: some View {
        VStack(spacing: 0) {
            smoothCanvasZoomDial
                .padding(.top, 8)
                .padding(.bottom, 6)
            
            aiCompositionTriggerButton
                .padding(.bottom, 8)
            
            permanentLutSelectorRail
                .padding(.bottom, 10)
            
            modeSelectorBar
                .padding(.bottom, 12)
            
            bottomControlBar
                .padding(.bottom, 18)
        }
    }
    
    // MARK: - 顶部专业 HUD
    private var topProfessionalHUD: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.5))
                    .frame(width: 7, height: 7)
                Text((compositionEngine.state != .inactive) ? "60Hz 实时引导中" : "AI 构图就绪")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
            
            Spacer()
            
            Text("48MP · RAW HDR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
            
            if cameraManager.isRecordingVideo {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text(formatSeconds(cameraManager.recordingSeconds))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.4))
                .clipShape(Capsule())
            }
            
            Spacer()
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - 苹果原生相机同款：半圆弧形旋转变焦转盘 (0.5x ~ 10.0x 无级丝滑滑动，精度 0.1x)
    private var smoothCanvasZoomDial: some View {
        VStack(spacing: 2) {
            if isZoomDialActive {
                // 展开态：苹果原生半圆弧形转盘 (放射状刻度沿着圆弧自转，0 掉帧满帧渲染)
                VStack(spacing: 2) {
                    // 当前倍率大字居中读数
                    Text(String(format: "%.1f×", cameraManager.currentZoom))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                        .shadow(color: Color.black.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    ZStack(alignment: .top) {
                        // 1. 半圆形物理放射刻度盘 (Canvas 单层极速 GPU 渲染)
                        Canvas { context, size in
                            let midX = size.width / 2.0
                            let radius: CGFloat = 220.0
                            let centerY = size.height + radius - 30.0
                            let centerAngle = -Double.pi / 2.0 // 正上方 12 点钟
                            let deltaAngle = 1.35 * Double.pi / 180.0 // 每 0.1x 旋转 1.35度
                            let current = Double(cameraManager.currentZoom)
                            
                            for step in 5...100 { // 0.5x 到 10.0x
                                let diff = (Double(step) * 0.1 - current) / 0.1
                                let angle = centerAngle + diff * deltaAngle
                                let deg = angle * 180.0 / Double.pi
                                
                                // 限制在可见半圆扇形范围内 (-90° ± 40°)
                                guard deg >= -130.0 && deg <= -50.0 else { continue }
                                
                                let isMajor = (step == 5) || (step == 10) || (step == 20) || (step == 30) || (step == 50) || (step == 100)
                                let isHalf = (step % 5 == 0) && !isMajor
                                
                                let lineLength: CGFloat = isMajor ? 13.0 : (isHalf ? 8.0 : 4.5)
                                let opacity: Double = isMajor ? 0.95 : (isHalf ? 0.65 : 0.3)
                                
                                let cosA = CGFloat(cos(angle))
                                let sinA = CGFloat(sin(angle))
                                
                                let pOut = CGPoint(x: midX + radius * cosA, y: centerY + radius * sinA)
                                let pIn = CGPoint(x: midX + (radius - lineLength) * cosA, y: centerY + (radius - lineLength) * sinA)
                                
                                var path = Path()
                                path.move(to: pOut)
                                path.addLine(to: pIn)
                                context.stroke(path, with: .color(Color.white.opacity(opacity)), lineWidth: isMajor ? 1.4 : 1.0)
                                
                                // 主刻度标注倍率数字 (.5, 1, 2, 3, 5, 10)
                                if isMajor {
                                    let val = Double(step) * 0.1
                                    let textStr = (step == 5) ? ".5" : String(format: "%.0f", val)
                                    let pText = CGPoint(x: midX + (radius - lineLength - 9) * cosA, y: centerY + (radius - lineLength - 9) * sinA)
                                    let text = Text(textStr)
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundColor(Color.white.opacity(0.85))
                                    context.draw(text, at: pText)
                                }
                            }
                        }
                        .frame(height: 48)
                        .padding(.horizontal, 16)
                        // 左右边缘自然渐隐遮罩
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.18),
                                    .init(color: .black, location: 0.82),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        
                        // 2. 屏幕中央苹果专属明黄游标指示小三角
                        VStack(spacing: 0) {
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 7))
                                .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.35))
                            Rectangle()
                                .fill(Color(red: 1.0, green: 0.88, blue: 0.35))
                                .frame(width: 1.5, height: 9)
                        }
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                    }
                    .frame(height: 50)
                    .background(Color.black.opacity(0.45))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    // 连续手势拖拽
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                autoDismissTask?.cancel()
                                if dragStartZoom == 0 {
                                    dragStartZoom = cameraManager.currentZoom
                                }
                                handleWheelDrag(translationX: value.translation.width)
                            }
                            .onEnded { _ in
                                dragStartZoom = cameraManager.currentZoom
                                scheduleAutoDismiss()
                            }
                    )
                }
            } else {
                // 收起态：苹果原生快速焦段切换胶囊 (.5, 1, 2, 3, 5, 10)
                HStack(spacing: 7) {
                    ForEach([0.5, 1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { factor in
                        let isSelected = abs(cameraManager.currentZoom - CGFloat(factor)) < 0.15
                        Button(action: {
                            selectionFeedback.selectionChanged()
                            withAnimation(.easeInOut(duration: 0.15)) {
                                cameraManager.setZoom(factor: CGFloat(factor))
                            }
                        }) {
                            Text(factor == 0.5 ? ".5" : String(format: "%.0f", factor))
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundColor(isSelected ? Color(red: 1.0, green: 0.88, blue: 0.35) : .white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(isSelected ? 0.22 : 0.1))
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color(red: 1.0, green: 0.88, blue: 0.35) : Color.clear, lineWidth: 1.2)
                                )
                        }
                        .contentShape(Circle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            autoDismissTask?.cancel()
                            if !isZoomDialActive {
                                dragStartZoom = cameraManager.currentZoom
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                    isZoomDialActive = true
                                }
                            }
                            handleWheelDrag(translationX: value.translation.width)
                        }
                        .onEnded { _ in
                            scheduleAutoDismiss()
                        }
                )
            }
        }
    }
    
    // 拖动手势：将手指水平移动映射为转盘角度旋转，实现 0.5x ~ 10.0x 范围平滑滑动
    private func handleWheelDrag(translationX: CGFloat) {
        let stepSensitivity: CGFloat = 5.5 // 每 5.5pt 步进 0.1x
        let deltaSteps = -translationX / stepSensitivity
        let target = dragStartZoom + CGFloat(deltaSteps) * 0.1
        // 严格锁定在 0.5x 到 10.0x 范围
        let clamped = max(0.5, min(10.0, (target * 10.0).rounded() / 10.0))
        
        if clamped != cameraManager.currentZoom {
            selectionFeedback.selectionChanged()
            cameraManager.setZoom(factor: clamped)
        }
    }
    
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isZoomDialActive = false
            }
        }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: task)
    }
    
    // MARK: - 【核心专属按键】：✨ AI 实时构图指挥大师
    private var aiCompositionTriggerButton: some View {
        Button(action: {
            impactFeedback.impactOccurred()
            if compositionEngine.state != .inactive {
                compositionEngine.stopRealtimeGuidance()
            } else {
                compositionEngine.startRealtimeGuidance(cameraManager: cameraManager)
                triggerAICompositionAnalysis()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: (compositionEngine.state != .inactive) ? "sparkles.rectangle.stack.fill" : "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor((compositionEngine.state != .inactive) ? Color(red: 0.0, green: 1.0, blue: 0.5) : Color(red: 1.0, green: 0.88, blue: 0.35))
                
                Text((compositionEngine.state != .inactive) ? "60Hz 实时构图对齐中 · 点击退出" : "开启 AI 实时构图指挥")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill((compositionEngine.state != .inactive) ? Color(red: 0.0, green: 0.3, blue: 0.15).opacity(0.85) : Color.white.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke((compositionEngine.state != .inactive) ? Color(red: 0.0, green: 1.0, blue: 0.5) : Color(red: 1.0, green: 0.88, blue: 0.35).opacity(0.5), lineWidth: 1.2)
            )
        }
        .contentShape(Capsule())
    }
    
    // MARK: - 常驻胶片 3D LUT 色彩滑轨
    private var permanentLutSelectorRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableLuts, id: \.name) { item in
                    let isSelected = (activeLutName == item.name)
                    Button(action: {
                        selectionFeedback.selectionChanged()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeLutName = item.name
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 6, height: 6)
                            Text(item.name)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.white : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .contentShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - 模式选择器
    private var modeSelectorBar: some View {
        HStack(spacing: 24) {
            Button(action: {
                selectionFeedback.selectionChanged()
                withAnimation(.easeInOut(duration: 0.15)) { captureMode = 0 }
            }) {
                Text("照片")
                    .font(.system(size: 13, weight: captureMode == 0 ? .bold : .medium))
                    .foregroundColor(captureMode == 0 ? Color(red: 1.0, green: 0.88, blue: 0.35) : .gray)
            }
            .contentShape(Rectangle())
            
            Button(action: {
                selectionFeedback.selectionChanged()
                withAnimation(.easeInOut(duration: 0.15)) { captureMode = 1 }
            }) {
                Text("视频")
                    .font(.system(size: 13, weight: captureMode == 1 ? .bold : .medium))
                    .foregroundColor(captureMode == 1 ? Color(red: 1.0, green: 0.88, blue: 0.35) : .gray)
            }
            .contentShape(Rectangle())
        }
    }
    
    // MARK: - 底部控制栏
    private var bottomControlBar: some View {
        HStack {
            VStack(spacing: 3) {
                if captureMode == 0 {
                    PhotosPicker(selection: $selectedPhotoPickerItem, matching: .images) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }
                    .contentShape(Circle())
                } else {
                    PhotosPicker(selection: $selectedVideoPickerItem, matching: .videos) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "film.stack")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }
                    .contentShape(Circle())
                }
                Text("相册素材")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            
            Button(action: handleMainShutterAction) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 3.5)
                        .frame(width: 72, height: 72)
                    
                    if captureMode == 0 {
                        Circle()
                            .fill(cameraManager.isCapturingPhoto ? Color.gray : Color.white)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Group {
                                    if cameraManager.isCapturingPhoto {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
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
                                .frame(width: 58, height: 58)
                        }
                    }
                }
            }
            .contentShape(Circle())
            .disabled(cameraManager.isCapturingPhoto)
            .frame(maxWidth: .infinity)
            
            VStack(spacing: 3) {
                Button(action: {
                    guard !cameraManager.isSwitchingCamera else { return }
                    impactFeedback.impactOccurred()
                    cameraManager.switchCamera()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(cameraManager.isSwitchingCamera ? 180 : 0))
                            .animation(.easeInOut(duration: 0.3), value: cameraManager.isSwitchingCamera)
                    }
                }
                .contentShape(Circle())
                .disabled(cameraManager.isSwitchingCamera)
                
                Text("翻转镜头")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 主快门逻辑
    private func handleMainShutterAction() {
        if captureMode == 0 {
            capturePhotoAction()
        } else {
            impactFeedback.impactOccurred()
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
    
    private func capturePhotoAction() {
        guard !cameraManager.isCapturingPhoto else { return }
        impactFeedback.impactOccurred()
        
        withAnimation(.easeIn(duration: 0.08)) {
            isFlashing = true
        }
        
        cameraManager.takePhoto { captured in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isFlashing = false
                }
                if let photo = captured {
                    self.importedPhoto = photo
                    self.showRetouch = true
                }
            }
        }
    }
    
    // MARK: - 触发 AI 场景感知 (零等待轻量预览帧抽样，绝不调用物理拍照快门)
    private func triggerAICompositionAnalysis() {
        guard let frame = cameraManager.captureLatestPreviewFrame() else { return }
        
        var payloadBase64 = "dGVzdF9iYXNlNjQ="
        let maxSide: CGFloat = 480.0
        let scale = min(maxSide / max(frame.size.width, frame.size.height), 1.0)
        let targetSize = CGSize(width: max(frame.size.width * scale, 100), height: max(frame.size.height * scale, 100))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            frame.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        if let data = resized.jpegData(compressionQuality: 0.5) {
            payloadBase64 = data.base64EncodedString()
        }
        
        apiClient.fetchCompositionGuidance(
            pitch: motionManager.pitchDegrees,
            roll: motionManager.rollDegrees,
            imageBase64: payloadBase64
        ) { result in
            DispatchQueue.main.async {
                if case .success(let data) = result {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.currentGuidance = data.compositionGuidance
                        self.currentFilterRec = data.filterRecommendation
                        self.aiCoachMessage = "✨ " + data.compositionGuidance.coachTip
                        if self.activeLutName == "自然原画" {
                            self.activeLutName = data.filterRecommendation.presetNameZh
                        }
                    }
                }
            }
        }
    }
    
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
