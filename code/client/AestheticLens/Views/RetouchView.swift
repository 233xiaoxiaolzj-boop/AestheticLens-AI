import SwiftUI

/// 拍后智能美学诊断与专业调色工作台 (REQ-12)
public struct RetouchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var apiClient = APIClient.shared
    
    public var capturedPhotoBase64: String = "dGVzdF9waG90b19iYXNlNjQ="
    
    // 调色参数与诊断数据
    @State private var recipe: RecipeParameters = RecipeParameters()
    @State private var critiqueText: String = "正在连线 AI 摄影美学大师诊断画面..."
    @State private var styleNameZh: String = "正在分析风格..."
    @State private var isComparingOriginal: Bool = false
    @State private var selectedTab: Int = 0 // 0: 光影, 1: 色彩, 2: 质感
    @State private var isLoadingRecipe: Bool = true
    
    public init(capturedPhotoBase64: String = "dGVzdF9waG90b19iYXNlNjQ=") {
        self.capturedPhotoBase64 = capturedPhotoBase64
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 顶部操作栏
                topNavigationBar
                
                // 2. 图像预览区 (支持长按原图无缝对比)
                imagePreviewSection
                
                // 3. AI 美学大师诊断点评卡片
                aiCritiqueCard
                
                // 4. 底部 10 专业滑块微调面板
                slidersWorkspace
            }
        }
        .onAppear {
            loadRecipeData()
        }
    }
    
    // MARK: - 加载拍后调色配方数据
    private func loadRecipeData() {
        isLoadingRecipe = true
        apiClient.fetchRetouchRecipe(photoBase64: capturedPhotoBase64) { result in
            isLoadingRecipe = false
            switch result {
            case .success(let data):
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.recipe = data.recommendedRecipe.parameters
                    self.critiqueText = data.aestheticDiagnosis.overallCritique
                    self.styleNameZh = data.aestheticDiagnosis.styleNameZh
                }
            case .failure(let error):
                self.critiqueText = "云端诊断超时，已启用默认美学胶片配方：\(error.localizedDescription)"
                self.styleNameZh = "暖阳胶片"
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
                // 导出成片并退出
                dismiss()
            }) {
                Text("保存成片")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
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
                .font(.system(size: 12, weight: .monospaced))
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
