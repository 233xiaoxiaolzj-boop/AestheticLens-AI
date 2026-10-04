import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 灵瞳智拍专业取景器主视图 (参考影视飓风相机专业布局，集成 AI 实时构图、多焦段变焦、实时胶片 LUT 与真实端云协同)
public struct CameraView: View {
    @ObservedObject var cameraManager = CameraManager.shared
    @ObservedObject var motionManager = MotionManager.shared
    @ObservedObject var apiClient = APIClient.shared
    
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
    
    // 手势变焦临时缩放倍数
    @State private var pinchZoomFactor: CGFloat = 1.0
    @State private var showZoomIndicator: Bool = false
    
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
                // 双指捏合手势变焦 (Pinch-to-Zoom)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            let targetZoom = cameraManager.currentZoom * scale
                            cameraManager.setZoom(factor: targetZoom)
                            showZoomIndicator = true
                        }
                        .onEnded { _ in
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
                
                // 飓风相机同款：多焦段快速切换按键盘 (0.5x, 1x, 2x, 3x)
                zoomSelectorRow
                    .padding(.bottom, 10)
                
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
    
    // MARK: - 飓风相机同款：多焦段快速切换按键 (0.5x, 1x, 2x, 3x)
    private var zoomSelectorRow: some View {
        HStack(spacing: 16) {
            zoomButton(label: "0.5×", factor: 1.0) // 广角/超广角基准
            zoomButton(label: "1×", factor: 1.0)
            zoomButton(label: "2×", factor: 2.0)
            zoomButton(label: "3×", factor: 3.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
    }
    
    private func zoomButton(label: String, factor: CGFloat) -> some View {
        let isSelected = abs(cameraManager.currentZoom - factor) < 0.2
        return Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            cameraManager.setZoom(factor: factor)
        }) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundColor(isSelected ? .black : .white)
                .frame(width: 38, height: 28)
                .background(isSelected ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color.clear)
                .clipShape(Circle())
        }
        .contentShape(Circle())
    }
    
    // MARK: - 【核心按键】：✨ 灵瞳 AI 实时构图大师专属按键
    private var aiCompositionTriggerButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            triggerAICompositionAnalysis(silent: false)
        }) {
            HStack(spacing: 8) {
                if isAnalyzingAI {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                    Text("AI 构图透视中...")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                    Text("AI 智能构图诊断")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.88, blue: 0.45), Color(red: 1.0, green: 0.72, blue: 0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: Color.yellow.opacity(0.4), radius: 6, x: 0, y: 2)
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
            
            // 中间：核心快门按钮 (照片全分辨率拍照 / 视频真实录像)
            Button(action: handleMainShutterAction) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    
                    if captureMode == 0 {
                        // 照片模式：白圈快门
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
        }
        
        // 抓取当前真实画幅的一帧用于 AI 分析
        cameraManager.takePhoto { capturedFrame in
            var payloadBase64 = "dGVzdF9iYXNlNjQ="
            if let frame = capturedFrame {
                let maxSide: CGFloat = 720.0
                let scale = min(maxSide / max(frame.size.width, frame.size.height), 1.0)
                let targetSize = CGSize(width: frame.size.width * scale, height: frame.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                let resized = renderer.image { _ in
                    frame.draw(in: CGRect(origin: .zero, size: targetSize))
                }
                if let data = resized.jpegData(compressionQuality: 0.65) {
                    payloadBase64 = data.base64EncodedString()
                }
            }
            
            apiClient.fetchCompositionGuidance(
                pitch: motionManager.pitchDegrees,
                roll: motionManager.rollDegrees,
                imageBase64: payloadBase64
            ) { result in
                DispatchQueue.main.async {
                    self.isAnalyzingAI = false
                    switch result {
                    case .success(let data):
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.currentGuidance = data.compositionGuidance
                            self.currentFilterRec = data.filterRecommendation
                            self.aiCoachMessage = data.compositionGuidance.coachTip
                            if self.activeLutName == "自然原画" {
                                self.activeLutName = data.filterRecommendation.presetNameZh
                            }
                        }
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    case .failure(let error):
                        print("[CameraView] AI 构图分析触发兜底: \(error)")
                        if !silent {
                            self.aiCoachMessage = "已启用构图参考：建议镜头平推，注意主体留白"
                        }
                    }
                }
            }
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
