import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// 拍后智能美学诊断与专业调色工作台 (REQ-12)
public struct RetouchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var apiClient = APIClient.shared
    
    public var inputImage: UIImage? = nil
    public var capturedPhotoBase64: String = "dGVzdF9waG90b19iYXNlNjQ="
    
    // 调色参数与诊断数据
    @State private var recipe: RecipeParameters = RecipeParameters()
    @State private var critiqueText: String = "正在连线 AI 摄影美学大师诊断画面..."
    @State private var styleNameZh: String = "正在分析风格..."
    @State private var isComparingOriginal: Bool = false
    @State private var selectedTab: Int = 0 // 0: 光影, 1: 色彩, 2: 质感
    @State private var isLoadingRecipe: Bool = true
    @State private var gradedImage: UIImage? = nil
    @State private var showSavedAlert: Bool = false
    
    private let ciContext = CIContext()
    
    public init(inputImage: UIImage? = nil, capturedPhotoBase64: String = "dGVzdF9waG90b19iYXNlNjQ=") {
        self.inputImage = inputImage
        self.capturedPhotoBase64 = capturedPhotoBase64
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 顶部操作栏
                topNavigationBar
                
                // 2. 图像预览区 (支持真实照片渲染与长按原图无缝对比)
                imagePreviewSection
                
                // 3. AI 美学大师诊断点评卡片
                aiCritiqueCard
                
                // 4. 底部 10 专业滑块微调面板
                slidersWorkspace
            }
        }
        .onAppear {
            if let img = inputImage {
                self.gradedImage = img
            }
            loadRecipeData()
        }
        .onChange(of: recipe) { _, _ in
            applyColorGrading()
        }
        .alert(isPresented: $showSavedAlert) {
            Alert(
                title: Text("已保存到相册"),
                message: Text("包含【\(styleNameZh)】AI 胶片美学配方的调色成片已成功保存至您的 iPhone 相册。"),
                dismissButton: .default(Text("完成")) {
                    dismiss()
                }
            )
        }
    }
    
    // MARK: - 真实照片压缩转 Base64
    private func getPayloadBase64() -> String {
        guard let img = inputImage else { return capturedPhotoBase64 }
        let maxSide: CGFloat = 720.0
        let scale = min(maxSide / max(img.size.width, img.size.height), 1.0)
        let targetSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        if let data = resized.jpegData(compressionQuality: 0.7) {
            return data.base64EncodedString()
        }
        return capturedPhotoBase64
    }
    
    // MARK: - 加载拍后调色配方数据
    private func loadRecipeData() {
        isLoadingRecipe = true
        let base64 = getPayloadBase64()
        apiClient.fetchRetouchRecipe(photoBase64: base64) { result in
            isLoadingRecipe = false
            switch result {
            case .success(let data):
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.recipe = data.recommendedRecipe.parameters
                    self.critiqueText = data.aestheticDiagnosis.overallCritique
                    self.styleNameZh = data.aestheticDiagnosis.styleNameZh
                }
                self.applyColorGrading()
            case .failure(let error):
                self.critiqueText = "云端诊断已平滑降级，启用默认温暖胶片配方：\(error.localizedDescription)"
                self.styleNameZh = "暖阳胶片"
                self.applyColorGrading()
            }
        }
    }
    
    // MARK: - CoreImage 毫秒级无损调色渲染
    private func applyColorGrading() {
        guard let source = inputImage, let ciImage = CIImage(image: source) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var output = ciImage
            
            // 1. 曝光与对比度及饱和度 (CIColorControls)
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(output, forKey: kCIInputImageKey)
                filter.setValue(self.recipe.exposure * 0.3, forKey: kCIInputBrightnessKey)
                filter.setValue(max(0.0, 1.0 + self.recipe.contrast * 0.5), forKey: kCIInputContrastKey)
                filter.setValue(max(0.0, 1.0 + self.recipe.saturation * 0.6 + self.recipe.vibrance * 0.4), forKey: kCIInputSaturationKey)
                if let res = filter.outputImage {
                    output = res
                }
            }
            
            // 2. 色温调整 (CITemperatureAndTint)
            if let tempFilter = CIFilter(name: "CITemperatureAndTint") {
                tempFilter.setValue(output, forKey: kCIInputImageKey)
                let neutral = CIVector(x: 6500, y: 0)
                let target = CIVector(x: 6500 + CGFloat(self.recipe.temperature) * 25.0, y: CGFloat(self.recipe.tint) * 10.0)
                tempFilter.setValue(neutral, forKey: "inputNeutral")
                tempFilter.setValue(target, forKey: "inputTargetNeutral")
                if let res = tempFilter.outputImage {
                    output = res
                }
            }
            
            if let cgImage = self.ciContext.createCGImage(output, from: output.extent) {
                let rendered = UIImage(cgImage: cgImage, scale: source.scale, orientation: source.imageOrientation)
                DispatchQueue.main.async {
                    self.gradedImage = rendered
                }
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
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                Text("AI 胶片美学配方")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: {
                // 保存照片至相册
                if let target = gradedImage ?? inputImage {
                    UIImageWriteToSavedPhotosAlbum(target, nil, nil, nil)
                    showSavedAlert = true
                } else {
                    dismiss()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .bold))
                    Text("保存成片")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 1.0, green: 0.85, blue: 0.4))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
    
    // MARK: - 成片预览与长按对比手势
    private var imagePreviewSection: some View {
        ZStack(alignment: .bottomTrailing) {
            let displayImg = isComparingOriginal ? inputImage : (gradedImage ?? inputImage)
            if let img = displayImg {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(16)
                    .overlay(
                        VStack {
                            if isLoadingRecipe {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.3)
                                    .padding(12)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(10)
                            }
                            Spacer()
                            if isComparingOriginal {
                                Text("【正在对比原图】")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.75))
                                    .cornerRadius(8)
                                    .padding(.bottom, 20)
                            }
                        }
                    )
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                // 成片模拟图 (调色效果 / 原图切换)
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: isComparingOriginal
                                ? [Color(red: 0.4, green: 0.3, blue: 0.25), Color(red: 0.1, green: 0.05, blue: 0.05)]
                                : [Color(red: 1.0, green: 0.55, blue: 0.2), Color(red: 0.85, green: 0.3, blue: 0.15), Color(red: 0.15, green: 0.1, blue: 0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        VStack {
                            if isLoadingRecipe {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.3)
                            }
                            Spacer()
                            if isComparingOriginal {
                                Text("【正在对比原图】")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(8)
                                    .padding(.bottom, 20)
                            }
                        }
                    )
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            
            // 对比原图提示徽章
            Text("长按画面对比原片")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(12)
                .padding(28)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isComparingOriginal = true }
                .onEnded { _ in isComparingOriginal = false }
        )
    }
    
    // MARK: - AI 诊断点评卡片
    private var aiCritiqueCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 摄影大师诊断")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                Text(critiqueText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - 10 项专业参数滑块工作台
    private var slidersWorkspace: some View {
        VStack(spacing: 8) {
            // 分类 Segmented Control
            HStack(spacing: 0) {
                TabButton(title: "基础光影", index: 0, currentTab: $selectedTab)
                TabButton(title: "色彩科学", index: 1, currentTab: $selectedTab)
                TabButton(title: "质感风格", index: 2, currentTab: $selectedTab)
            }
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    if selectedTab == 0 {
                        // 基础光影 4 项
                        SliderRow(name: "曝光", value: $recipe.exposure, range: -1.0...1.0, step: 0.02)
                        SliderRow(name: "对比度", value: $recipe.contrast, range: -1.0...1.0, step: 0.02)
                        SliderRow(name: "高光压制", value: $recipe.highlights, range: -1.0...1.0, step: 0.02)
                        SliderRow(name: "阴影提亮", value: $recipe.shadows, range: -1.0...1.0, step: 0.02)
                    } else if selectedTab == 1 {
                        // 色彩科学 4 项
                        SliderRow(name: "色温", value: $recipe.temperature, range: -30.0...30.0, step: 1.0)
                        SliderRow(name: "色调", value: $recipe.tint, range: -20.0...20.0, step: 1.0)
                        SliderRow(name: "自然饱和度", value: $recipe.vibrance, range: -1.0...1.0, step: 0.02)
                        SliderRow(name: "饱和度", value: $recipe.saturation, range: -1.0...1.0, step: 0.02)
                    } else {
                        // 质感风格 2 项
                        SliderRow(name: "暗角", value: $recipe.vignette, range: -1.0...0.0, step: 0.02)
                        SliderRow(name: "胶片颗粒", value: $recipe.grain, range: 0.0...0.5, step: 0.01)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .frame(height: 180)
        }
        .background(Color(white: 0.08))
    }
}

// MARK: - 滑块行组件
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
                .accentColor(Color(red: 1.0, green: 0.85, blue: 0.4))
            
            Text(String(format: "%+.2f", value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                .frame(width: 55, alignment: .trailing)
        }
    }
}

// MARK: - 标签切换按钮
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
                .background(currentTab == index ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color.clear)
                .cornerRadius(8)
        }
    }
}
