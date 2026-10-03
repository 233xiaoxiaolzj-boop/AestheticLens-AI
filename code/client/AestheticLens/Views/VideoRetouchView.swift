import SwiftUI

/// 成品视频 AI 辅助调色与滤镜实时调试工作台 (REQ-13)
public struct VideoRetouchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var apiClient = APIClient.shared
    @ObservedObject var videoService = VideoPlayerService.shared
    
    // 调色参数与诊断数据
    @State private var recipe: RecipeParameters = RecipeParameters(
        exposure: 0.10,
        contrast: 0.18,
        highlights: -0.20,
        shadows: 0.15,
        temperature: -8.0,
        tint: 2.0,
        vibrance: 0.16,
        saturation: 0.05,
        vignette: -0.12,
        grain: 0.04
    )
    
    @State private var critiqueText: String = "正在分析视频全片运镜与色彩连续性..."
    @State private var cameraMovementText: String = "运镜平稳，帧间过渡自然"
    @State private var styleNameZh: String = "赛博青橙电影感"
    @State private var activeLutId: String = "lut_cyber_teal_orange_03"
    @State private var isComparingOriginal: Bool = false
    @State private var selectedTab: Int = 0 // 0: 基础光影, 1: 色彩科学, 2: 质感风格
    @State private var isLoadingRecipe: Bool = true
    @State private var showExportAlert: Bool = false
    public var videoURL: URL? = nil
    
    public init(videoURL: URL? = nil) {
        self.videoURL = videoURL
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 顶部操作栏
                topNavigationBar
                
                // 2. 视频播放视窗 (支持长按原片无缝比对)
                videoPreviewSection
                
                // 3. 视频播放进度与控制栏
                videoPlaybackControlBar
                
                // 4. AI 视频运镜与色彩诊断卡片
                aiVideoCritiqueCard
                
                // 5. 底部 10 项专业参数滑块工作台
                slidersWorkspace
            }
            
            // 6. 导出进度遮罩
            if videoService.isExporting {
                exportProgressOverlay
            }
        }
        .onAppear {
            if let url = videoURL {
                videoService.loadVideo(url: url)
            }
            loadVideoRecipeData()
        }
        .alert(isPresented: $showExportAlert) {
            Alert(
                title: Text("视频导出成功"),
                message: Text("已将应用了【\(styleNameZh)】的调色成品视频保存至系统相册。"),
                dismissButton: .default(Text("好的")) {
                    dismiss()
                }
            )
        }
    }
    
    // MARK: - 加载视频调色配方数据
    private func loadVideoRecipeData() {
        isLoadingRecipe = true
        apiClient.fetchVideoRetouchRecipe { result in
            isLoadingRecipe = false
            switch result {
            case .success(let data):
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.recipe = data.recommendedRecipe.parameters
                    self.activeLutId = data.recommendedRecipe.lutId
                    self.critiqueText = data.aestheticDiagnosis.overallCritique
                    self.styleNameZh = data.aestheticDiagnosis.styleNameZh
                    if let cm = data.aestheticDiagnosis.cameraMovementCritique {
                        self.cameraMovementText = cm
                    }
                }
            case .failure(let error):
                self.critiqueText = "云端诊断已平滑降级，启用电影级青橙基准调色：\(error.localizedDescription)"
                self.styleNameZh = "赛博青橙电影感"
            }
        }
    }
    
    // MARK: - 顶部导航栏
    private var topNavigationBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(styleNameZh)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 1.0))
                Text("AI 视频电影级调色")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: triggerExportVideo) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("导出视频")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 0.3, green: 0.8, blue: 1.0))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    // MARK: - 视频播放与原片对比手势视窗
    private var videoPreviewSection: some View {
        ZStack(alignment: .bottomTrailing) {
            // 模拟 16:9 动态视频色彩视窗
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: isComparingOriginal
                            ? [Color(red: 0.2, green: 0.25, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.15)]
                            : [Color(red: 0.1, green: 0.45, blue: 0.6), Color(red: 0.85, green: 0.4, blue: 0.15), Color(red: 0.05, green: 0.1, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    VStack {
                        if isLoadingRecipe {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.3)
                        }
                        
                        // 播放中水波纹/动态模拟指示
                        if videoService.isPlaying {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text("60FPS 实时色彩映射")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(10)
                            .padding(.top, 12)
                        }
                        
                        Spacer()
                        
                        if isComparingOriginal {
                            Text("【长按中：正在对比原片视频】")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .padding(.bottom, 16)
                        }
                    }
                )
                .frame(height: 240)
                .padding(.horizontal, 16)
            
            // 对比提示微标
            Text("长按比对原片")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55))
                .cornerRadius(10)
                .padding(24)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isComparingOriginal = true }
                .onEnded { _ in isComparingOriginal = false }
        )
    }
    
    // MARK: - 视频进度控制条
    private var videoPlaybackControlBar: some View {
        HStack(spacing: 12) {
            // 播放/暂停键
            Button(action: { videoService.togglePlayPause() }) {
                Image(systemName: videoService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            
            // 当前时间戳
            Text(formatTime(videoService.currentTime))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
            
            // 进度拖拽滑块
            Slider(value: $videoService.currentTime, in: 0.0...videoService.duration, onEditingChanged: { isEditing in
                if !isEditing {
                    videoService.seek(to: videoService.currentTime)
                }
            })
            .accentColor(Color(red: 0.3, green: 0.8, blue: 1.0))
            
            // 总时长
            Text(formatTime(videoService.duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    // MARK: - AI 视频美学诊断卡片
    private var aiVideoCritiqueCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 20))
                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 1.0))
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("AI 电影调色大师诊断")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.3, green: 0.8, blue: 1.0))
                    Spacer()
                    Text("连贯度 92%")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
                Text(critiqueText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                Text("🎬 \(cameraMovementText)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
    
    // MARK: - 10 项专业参数滑块工作台
    private var slidersWorkspace: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                TabButton(title: "基础光影", index: 0, currentTab: $selectedTab)
                TabButton(title: "色彩科学", index: 1, currentTab: $selectedTab)
                TabButton(title: "质感风格", index: 2, currentTab: $selectedTab)
            }
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if selectedTab == 0 {
                        SliderRow(name: "曝光补偿", value: $recipe.exposure, range: -1.0...1.0, step: 0.02)
                        SliderRow(name: "动态对比", value: $recipe.contrast, range: -1.0...1.0, step: 0.02)
                        SliderRow(name: "高光压制", value: $recipe.highlights, range: -1.0...1.0, step: 0.02)
                        SliderRow(name: "暗部细节", value: $recipe.shadows, range: -1.0...1.0, step: 0.02)
                    } else if selectedTab == 1 {
                        SliderRow(name: "色彩色温", value: $recipe.temperature, range: -30.0...30.0, step: 1.0)
                        SliderRow(name: "色调平衡", value: $recipe.tint, range: -20.0...20.0, step: 1.0)
                        SliderRow(name: "自然饱和", value: $recipe.vibrance, range: -1.0...1.0, step: 0.02)
                        SliderRow(name: "纯饱和度", value: $recipe.saturation, range: -1.0...1.0, step: 0.02)
                    } else {
                        SliderRow(name: "电影暗角", value: $recipe.vignette, range: -1.0...0.0, step: 0.02)
                        SliderRow(name: "胶片颗粒", value: $recipe.grain, range: 0.0...0.5, step: 0.01)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .frame(height: 160)
        }
        .background(Color(white: 0.08))
    }
    
    // MARK: - 导出进度指示遮罩
    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.3, green: 0.8, blue: 1.0)))
                    .scaleEffect(1.6)
                Text("正在进行 Metal 硬件加速视频渲染...")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("\(Int(videoService.exportProgress * 100))%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 1.0))
            }
            .padding(30)
            .background(Color(white: 0.15))
            .cornerRadius(16)
        }
    }
    
    // MARK: - 触发视频导出
    private func triggerExportVideo() {
        videoService.exportGradedVideo(recipe: recipe, lutId: activeLutId) { result in
            switch result {
            case .success:
                self.showExportAlert = true
            case .failure:
                break
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let sec = Int(seconds) % 60
        let min = Int(seconds) / 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// MARK: - 标签与滑块子组件复用
private struct SliderRow: View {
    let name: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    
    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 80, alignment: .leading)
            Slider(value: $value, in: range, step: step)
                .accentColor(Color(red: 0.3, green: 0.8, blue: 1.0))
            Text(String(format: "%+.2f", value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 1.0))
                .frame(width: 55, alignment: .trailing)
        }
    }
}

private struct TabButton: View {
    let title: String
    let index: Int
    @Binding var currentTab: Int
    
    var body: some View {
        Button(action: { currentTab = index }) {
            Text(title)
                .font(.system(size: 13, weight: currentTab == index ? .bold : .regular))
                .foregroundColor(currentTab == index ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(currentTab == index ? Color(red: 0.3, green: 0.8, blue: 1.0) : Color.clear)
                .cornerRadius(8)
        }
    }
}
