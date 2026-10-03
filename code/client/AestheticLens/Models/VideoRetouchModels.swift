import Foundation

// MARK: - 视频元数据
public struct VideoMeta: Codable, Equatable {
    public let durationSec: Double
    public let width: Int
    public let height: Int
    public let fps: Double
    public let format: String
    
    public init(durationSec: Double, width: Int, height: Int, fps: Double = 60.0, format: String = "mp4") {
        self.durationSec = durationSec
        self.width = width
        self.height = height
        self.fps = fps
        self.format = format
    }
    
    enum CodingKeys: String, CodingKey {
        case durationSec = "duration_sec"
        case width, height, fps, format
    }
}

// MARK: - 视频抽帧关键帧实体
public struct KeyframeItem: Codable, Equatable {
    public let timestampSec: Double
    public let frameIndex: Int
    public let imageBase64: String
    
    public init(timestampSec: Double, frameIndex: Int, imageBase64: String) {
        self.timestampSec = timestampSec
        self.frameIndex = frameIndex
        self.imageBase64 = imageBase64
    }
    
    enum CodingKeys: String, CodingKey {
        case timestampSec = "timestamp_sec"
        case frameIndex = "frame_index"
        case imageBase64 = "image_base64"
    }
}

// MARK: - 视频美学与运镜诊断
public struct VideoAestheticDiagnosis: Codable, Equatable {
    public let overallCritique: String
    public let targetStyle: String
    public let styleNameZh: String
    public let cameraMovementCritique: String?
    
    enum CodingKeys: String, CodingKey {
        case overallCritique = "overall_critique"
        case targetStyle = "target_style"
        case styleNameZh = "style_name_zh"
        case cameraMovementCritique = "camera_movement_critique"
    }
}

// MARK: - 视频画面连贯性指标
public struct SceneContinuity: Codable, Equatable {
    public let consistencyScore: Double
    public let detectedFlickers: Bool
    
    enum CodingKeys: String, CodingKey {
        case consistencyScore = "consistency_score"
        case detectedFlickers = "detected_flickers"
    }
}

// MARK: - 视频调色完整响应实体 (Master Recipe)
public struct VideoRetouchData: Codable, Equatable {
    public let aestheticDiagnosis: VideoAestheticDiagnosis
    public let recommendedRecipe: RecommendedRecipe
    public let sceneContinuity: SceneContinuity?
    
    enum CodingKeys: String, CodingKey {
        case aestheticDiagnosis = "aesthetic_diagnosis"
        case recommendedRecipe = "recommended_recipe"
        case sceneContinuity = "scene_continuity"
    }
}
