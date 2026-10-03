import Foundation

// MARK: - 拍后美学调色诊断
public struct AestheticDiagnosis: Codable, Equatable {
    public let overallCritique: String
    public let targetStyle: String
    public let styleNameZh: String
    
    enum CodingKeys: String, CodingKey {
        case overallCritique = "overall_critique"
        case targetStyle = "target_style"
        case styleNameZh = "style_name_zh"
    }
}

// MARK: - 调色滑块参数矩阵 (Recipe)
public struct RecipeParameters: Codable, Equatable {
    public var exposure: Double = 0.0
    public var contrast: Double = 0.0
    public var highlights: Double = 0.0
    public var shadows: Double = 0.0
    public var temperature: Double = 0.0
    public var tint: Double = 0.0
    public var vibrance: Double = 0.0
    public var saturation: Double = 0.0
    public var vignette: Double = 0.0
    public var grain: Double = 0.0
    
    public init(
        exposure: Double = 0.0,
        contrast: Double = 0.0,
        highlights: Double = 0.0,
        shadows: Double = 0.0,
        temperature: Double = 0.0,
        tint: Double = 0.0,
        vibrance: Double = 0.0,
        saturation: Double = 0.0,
        vignette: Double = 0.0,
        grain: Double = 0.0
    ) {
        self.exposure = exposure
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.temperature = temperature
        self.tint = tint
        self.vibrance = vibrance
        self.saturation = saturation
        self.vignette = vignette
        self.grain = grain
    }
}

// MARK: - 推荐调色配方
public struct RecommendedRecipe: Codable, Equatable {
    public let lutId: String
    public let lutIntensity: Double
    public let parameters: RecipeParameters
    
    enum CodingKeys: String, CodingKey {
        case lutId = "lut_id"
        case lutIntensity = "lut_intensity"
        case parameters
    }
}

// MARK: - 拍后调色完整响应实体
public struct AnalyzeAndGradeData: Codable, Equatable {
    public let aestheticDiagnosis: AestheticDiagnosis
    public let recommendedRecipe: RecommendedRecipe
    
    enum CodingKeys: String, CodingKey {
        case aestheticDiagnosis = "aesthetic_diagnosis"
        case recommendedRecipe = "recommended_recipe"
    }
}
