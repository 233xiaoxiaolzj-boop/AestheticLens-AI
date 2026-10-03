import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 取景器全屏主视图 (集成硬件直通与 Metal 滤镜双保险、相册导入、60Hz 水平仪与 AI 构图诊断)
public struct CameraView: View {
    @ObservedObject var cameraManager = CameraManager.shared
    @ObservedObject var motionManager = MotionManager.shared
    @ObservedObject var apiClient = APIClient.shared
    
    // 构图与滤镜状态
    @State private var currentGuidance: CompositionGuidance? = nil
    @State private var currentFilterRec: FilterRecommendation? = nil
    @State private var showSettings: Bool = false
    @State private var showRetouch: Bool = false
    @State private var showVideoRetouch: Bool = false
    @State private var isFlashing: Bool = false
    @State private var captureMode: Int = 0 // 0: 照片构图, 1: 视频调色
    @State private var activeLutName: String = "自然原画"
    @State private var showFilterSelector: Bool = false
    
    // 相册挑选状态 (支持历史照片与视频直接导入进行 AI 润色)
    @State private var selectedPhotoPickerItem: PhotosPickerItem? = nil
    @State private var selectedVideoPickerItem: PhotosPickerItem? = nil
    @State private var importedPhoto: UIImage? = nil
    @State private var importedVideoURL: URL? = nil
    
    // 滤镜预设清单
    private let availableLuts: [String] = ["自然原画", "落日暖调", "纯净清透", "赛博青橙", "德味黑白"]
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 1. 底层取景画幅：系统级硬件直通视频预览 + Metal 3D LUT 胶片滤镜渲染 (绝对不黑屏双保险)
            if cameraManager.isAuthorized {
                ZStack {
                    // 硬件直通原生预览底座 (100% 保证相机画面秒出)
                    CameraPreviewView()
                        .ignoresSafeArea()
                    
                    // Metal 3D LUT 胶片滤镜层 (当开启特色胶片时渲染)
                    if activeLutName != "自然原画" {
                        MetalView(activePreset: activeLutName)
                            .ignoresSafeArea()
                    }
                }
                .onAppear {
                    cameraManager.startSession()
                }
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
            
            // 2. 中层：60Hz 微光绿色动态水平仪 HUD
            LevelGaugeView()
            
            // 3. 顶层：AR 构图框与空间机位 4 向导航箭头
            NavigationOverlayView(guidance: currentGuidance)
            
            // 4. 界面交互与控制层
            VStack(spacing: 0) {
                // 顶部状态栏
                topStatusBar
                
                Spacer()
                
                // 浮动式胶片滤镜选择器 (可展开收起)
                if showFilterSelector {
                    filterSelectorCarousel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 12)
                }
                
                // 模式切换条 (照片拍摄 / 视频调色)
                modeSelectorBar
                    .padding(.bottom, 16)
                
                // 底部核心快门操作栏
                bottomControlBar
                    .padding(.bottom, 36)
            }
            
            // 5. 快门曝光机械闪白
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
            triggerAnalysis()
        }
    }
    
    // MARK: - 顶部状态栏
    private var topStatusBar: some View {
        HStack {
            // 云端/离线微标
            HStack(spacing: 6) {
                Circle()
                    .fill(apiClient.currentMode == .mock ? Color.green : Color(red: 0.2, green: 0.8, blue: 1.0))
                    .frame(width: 8, height: 8)
                Text(apiClient.currentMode == .mock ? "离线 Mock" : "Qwen-VL 在线")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
            
            Spacer()
            
            // 当前滤镜提示胶囊 (点击展开滤镜盘)
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    showFilterSelector.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                        .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                    Text(activeLutName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Image(systemName: showFilterSelector ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
            }
            
            Spacer()
            
            // 设置按钮
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    // MARK: - 滤镜快速横向滚轮
    private var filterSelectorCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableLuts, id: \.self) { lut in
                    Button(action: {
                        activeLutName = lut
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
                        Text(lut)
                            .font(.system(size: 12, weight: activeLutName == lut ? .bold : .medium))
                            .foregroundColor(activeLutName == lut ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(activeLutName == lut ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color.black.opacity(0.55))
                            .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 模式切换条
    private var modeSelectorBar: some View {
        HStack(spacing: 32) {
            Button(action: { captureMode = 0 }) {
                Text("照片拍摄")
                    .font(.system(size: 14, weight: captureMode == 0 ? .bold : .medium))
                    .foregroundColor(captureMode == 0 ? Color(red: 1.0, green: 0.85, blue: 0.4) : .white.opacity(0.6))
            }
            
            Button(action: { captureMode = 1 }) {
                Text("视频调色")
                    .font(.system(size: 14, weight: captureMode == 1 ? .bold : .medium))
                    .foregroundColor(captureMode == 1 ? Color(red: 0.3, green: 0.8, blue: 1.0) : .white.opacity(0.6))
            }
        }
    }
    
    // MARK: - 底部核心控制栏
    private var bottomControlBar: some View {
        HStack(spacing: 0) {
            // 左侧：相册导入按钮 (支持选取历史照片或视频进行 AI 润色)
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
                }
                Text("相册润色")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            
            // 中间：核心快门按钮 (机械感同心圆环)
            Button(action: handleCaptureAction) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    
                    if captureMode == 0 {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 62, height: 62)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // 右侧：镜头前后翻转切换
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
                Text("翻转镜头")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 触发拍摄或录像动作
    private func handleCaptureAction() {
        if captureMode == 0 {
            capturePhotoAction()
        } else {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            self.importedVideoURL = nil
            self.showVideoRetouch = true
        }
    }
    
    // MARK: - 触发快门拍摄与拍后调色跳转
    private func capturePhotoAction() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        withAnimation(.easeIn(duration: 0.08)) {
            isFlashing = true
        }
        
        // 捕获真实画面照片
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
                    if self.activeLutName == "自然原画" {
                        self.activeLutName = data.filterRecommendation.presetNameZh
                    }
                }
            case .failure(let error):
                print("[CameraView] 构图分析触发兜底或失败: \(error)")
            }
        }
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
