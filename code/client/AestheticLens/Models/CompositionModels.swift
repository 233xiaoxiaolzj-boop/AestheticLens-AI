import Foundation

// MARK: - 归一化构图裁剪框 (0.0 ~ 1.0)
public struct CropBox: Codable, Equatable {
    public let ymin: Double
    public let xmin: Double
    public let ymax: Double
    public let xmax: Double
    
    public init(ymin: Double, xmin: Double, ymax: Double, xmax: Double) {
        self.ymin = ymin
        self.xmin = xmin
        self.ymax = ymax
        self.xmax = xmax
    }
}

// MARK: - 空间机位物理移动向量
public struct NavigationVector: Codable, Equatable {
    public let forwardSteps: Int?
    public let horizontalTranslationM: Double?
    public let verticalTranslationCm: Double?
    
    enum CodingKeys: String, CodingKey {
        case forwardSteps = "forward_steps"
        case horizontalTranslationM = "horizontal_translation_m"
        case verticalTranslationCm = "vertical_translation_cm"
    }
}

// MARK: - 场景分析结果
public struct SceneAnalysis: Codable, Equatable {
    public let sceneType: String
    public let sceneLabelZh: String
    public let confidence: Double
    public let detectedIssues: [String]
    
    enum CodingKeys: String, CodingKey {
        case sceneType = "scene_type"
        case sceneLabelZh = "scene_label_zh"
        case confidence
        case detectedIssues = "detected_issues"
    }
}

// MARK: - 构图引导决策
public struct CompositionGuidance: Codable, Equatable {
    public let coachTip: String
    public let actionType: String
    public let recommendedGrid: String
    public let suggestedCropBox: CropBox
    public let targetPitchAdjustmentDeg: Double?
    public let navigationVector: NavigationVector?
    
    enum CodingKeys: String, CodingKey {
        case coachTip = "coach_tip"
        case actionType = "action_type"
        case recommendedGrid = "recommended_grid"
        case suggestedCropBox = "suggested_crop_box"
        case targetPitchAdjustmentDeg = "target_pitch_adjustment_deg"
        case navigationVector = "navigation_vector"
    }
}

// MARK: - 滤镜推荐参数
public struct FilterRecommendation: Codable, Equatable {
    public let recommendedLutId: String
    public let presetNameZh: String
    public let recommendedIntensity: Double
    
    enum CodingKeys: String, CodingKey {
        case recommendedLutId = "recommended_lut_id"
        case presetNameZh = "preset_name_zh"
        case recommendedIntensity = "recommended_intensity"
    }
}

// MARK: - 取景抽帧云端完整响应实体
public struct AnalyzeCompositionData: Codable, Equatable {
    public let sceneAnalysis: SceneAnalysis
    public let compositionGuidance: CompositionGuidance
    public let filterRecommendation: FilterRecommendation
    
    enum CodingKeys: String, CodingKey {
        case sceneAnalysis = "scene_analysis"
        case compositionGuidance = "composition_guidance"
        case filterRecommendation = "filter_recommendation"
    }
}

// MARK: - 通用响应外层信封
public struct Envelope<T: Codable>: Codable {
    public let code: Int
    public let message: String
    public let requestId: String?
    public let data: T?
    
    enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestId = "request_id"
        case data
    }
}
