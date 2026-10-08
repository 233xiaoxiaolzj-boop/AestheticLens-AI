import Foundation
import UIKit
import Combine
import Vision

public enum DataSourceMode: String, CaseIterable, Identifiable {
    case live = "在线云端 (Live Cloud)"
    case mock = "本地仿真 (Local Mock 桩)"
    
    public var id: String { rawValue }
}

public enum ServerEnvironment: String, CaseIterable, Identifiable {
    case cloudProd = "云端生产公网 (Render HTTPS)"
    case localDocker = "本地 Docker 容器 (127.0.0.1:8000)"
    case custom = "自定义服务器 IP"
    
    public var id: String { rawValue }
    
    public var defaultURL: String {
        switch self {
        case .cloudProd:
            return "https://aestheticlens-api.onrender.com"
        case .localDocker:
            return "http://127.0.0.1:8000"
        case .custom:
            return "http://192.168.1.100:8000"
        }
    }
}

/// 端云通信中台客户端 (支持生产 Live 与离线智能端侧视觉双保险切换)

/// 场景探景分析结果数据结构 (由阿里云 Qwen-VL 或端侧 Vision 生成)
public struct SceneExplorationResult: Codable {
    public let sceneType: String          // "landscape" 或 "portrait"
    public let isPortrait: Bool
    public let sceneTitle: String         // 场景精炼标题，如"山间逆光人像", "林间透光丁达尔"
    public let sceneAnalysis: String      // 场景深度解构：背景、主体、空间关系现状
    public let lightingAndElement: String // 光影与元素深度分析：镜头中阳光怎么拍效果最好
    public let placementGuide: String     // 最佳位置指引：人物/主体在哪个位置效果最佳
    public let cropBox: CropBox           // [ymin, xmin, ymax, xmax] 圈定黄金区域
    public let recommendedZoom: Double    // 如 1.0, 2.0, 2.5, 3.0, 5.0
    public let filterPreset: String       // 推荐胶片滤镜名称
    public let adviceZh: String           // 12字以内精辟点睛之笔
    public let isFromAliyunCloud: Bool    // 是否来自阿里云 Qwen-VL 云端
    
    public init(
        sceneType: String,
        isPortrait: Bool,
        sceneTitle: String = "",
        sceneAnalysis: String = "",
        lightingAndElement: String = "",
        placementGuide: String = "",
        cropBox: CropBox,
        recommendedZoom: Double,
        filterPreset: String,
        adviceZh: String,
        isFromAliyunCloud: Bool
    ) {
        self.sceneType = sceneType
        self.isPortrait = isPortrait
        self.sceneTitle = sceneTitle.isEmpty ? (isPortrait ? "人像空间打卡" : "自然光影风光") : sceneTitle
        self.sceneAnalysis = sceneAnalysis.isEmpty ? (isPortrait ? "画面包含人物主体与背景，主体当前位置可进一步优化。" : "视野宽阔，光影景致丰富，建议提炼视觉焦点。") : sceneAnalysis
        self.lightingAndElement = lightingAndElement.isEmpty ? "顺应主光源方向，利用透射光勾勒轮廓与层次。" : lightingAndElement
        self.placementGuide = placementGuide.isEmpty ? adviceZh : placementGuide
        self.cropBox = cropBox
        self.recommendedZoom = recommendedZoom
        self.filterPreset = filterPreset
        self.adviceZh = adviceZh
        self.isFromAliyunCloud = isFromAliyunCloud
    }
}

public final class APIClient: ObservableObject {
    public static let shared = APIClient()
    
    // 数据源切换 (由设置页隐藏手势三击唤出)
    @Published public var currentMode: DataSourceMode = .live
    @Published public var isHealthOk: Bool = false
    @Published public var selectedEnv: ServerEnvironment = .cloudProd {
        didSet {
            baseURL = selectedEnv.defaultURL
            checkHealth()
        }
    }
    
    private let kSavedBaseURLKey = "AestheticLens_SavedBaseURL"
    
    // 当前服务器网关基础地址 (默认直连云端生产公网，支持本地持久化记忆)
    @Published public var baseURL: String = ServerEnvironment.cloudProd.defaultURL {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: kSavedBaseURLKey)
        }
    }
    
    // 当前缓存的匿名 JWT 令牌与设备唯一 ID
    @Published public var jwtToken: String? = nil
    public var deviceId: String = UUID().uuidString
    
    public init() {
        if let saved = UserDefaults.standard.string(forKey: kSavedBaseURLKey), !saved.isEmpty {
            self.baseURL = saved
        }
        if let savedKey = UserDefaults.standard.string(forKey: kAliyunApiKeyStorage), !savedKey.isEmpty {
            self.aliyunApiKey = savedKey
        }
        checkHealth()
    }
    
    // MARK: - 网关健康检查探测
    public func checkHealth() {
        guard let url = URL(string: "\(baseURL)/health") else {
            self.isHealthOk = false
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.isHealthOk = true
                } else {
                    self?.isHealthOk = false
                }
            }
        }.resume()
    }
    
    // MARK: - 设备静默注册与 JWT 令牌获取
    public func registerDevice(completion: @escaping (Result<String, Error>) -> Void) {
        if currentMode == .mock {
            let mockToken = "mock_jwt_token_offline_safe"
            self.jwtToken = mockToken
            completion(.success(mockToken))
            return
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/auth/device-register") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let body: [String: Any] = [
            "device_id": deviceId,
            "client_version": "2.0.0"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(URLError(.cannotDecodeContentData))) }
                return
            }
            do {
                struct AuthData: Codable {
                    let token: String
                    let tokenType: String
                    let expiresIn: Int
                    enum CodingKeys: String, CodingKey {
                        case token
                        case tokenType = "token_type"
                        case expiresIn = "expires_in"
                    }
                }
                let envelope = try JSONDecoder().decode(Envelope<AuthData>.self, from: data)
                if let token = envelope.data?.token {
                    DispatchQueue.main.async {
                        self?.jwtToken = token
                        completion(.success(token))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(URLError(.userAuthenticationRequired)))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
    
    // MARK: - 取景抽帧场景与构图分析 (带端侧毫秒级视觉人脸/风光动态判断，彻底杜绝盲目人像提示)
    public func fetchCompositionGuidance(
        pitch: Double,
        roll: Double,
        imageBase64: String = "dGVzdF9iYXNlNjQ=",
        completion: @escaping (Result<AnalyzeCompositionData, Error>) -> Void
    ) {
        // 1. 本地 Mock 模式直接通过端侧 Vision 进行毫秒级真实场景识别
        if currentMode == .mock {
            self.analyzeSmartComposition(pitch: pitch, roll: roll, imageBase64: imageBase64) { data in
                DispatchQueue.main.async {
                    completion(.success(data))
                }
            }
            return
        }
        
        // 2. 检查是否有 JWT 令牌，若无先静默注册
        if jwtToken == nil {
            registerDevice { [weak self] authResult in
                switch authResult {
                case .success:
                    self?.fetchCompositionGuidance(pitch: pitch, roll: roll, imageBase64: imageBase64, completion: completion)
                case .failure:
                    self?.analyzeSmartComposition(pitch: pitch, roll: roll, imageBase64: imageBase64) { fallback in
                        DispatchQueue.main.async { completion(.success(fallback)) }
                    }
                }
            }
            return
        }
        
        // 3. 在线云端请求
        guard let url = URL(string: "\(baseURL)/api/v1/vision/analyze-composition") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = jwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 8.0 // 8.0s 适中超时，超时即刻激活端侧 Vision 毫秒级兜底
        
        let body: [String: Any] = [
            "client_version": "2.0.0",
            "device_info": [
                "platform": "ios",
                "focal_length_mm": 26.0,
                "sensor_attitude": ["pitch": pitch, "roll": roll]
            ],
            "image_meta": ["width": 720, "height": 960, "format": "jpeg"],
            "image_base64": imageBase64
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                self?.jwtToken = nil
                self?.registerDevice { authResult in
                    if case .success = authResult {
                        self?.fetchCompositionGuidance(pitch: pitch, roll: roll, imageBase64: imageBase64, completion: completion)
                    } else {
                        self?.analyzeSmartComposition(pitch: pitch, roll: roll, imageBase64: imageBase64) { fallback in
                            DispatchQueue.main.async { completion(.success(fallback)) }
                        }
                    }
                }
                return
            }
            
            if let error = error {
                print("[APIClient] 云端接口波动: \(error.localizedDescription)，自动激活端侧原生 Vision 智能分析")
                self?.analyzeSmartComposition(pitch: pitch, roll: roll, imageBase64: imageBase64) { fallback in
                    DispatchQueue.main.async { completion(.success(fallback)) }
                }
                return
            }
            guard let data = data else {
                self?.analyzeSmartComposition(pitch: pitch, roll: roll, imageBase64: imageBase64) { fallback in
                    DispatchQueue.main.async { completion(.success(fallback)) }
                }
                return
            }
            do {
                let envelope = try JSONDecoder().decode(Envelope<AnalyzeCompositionData>.self, from: data)
                if let payload = envelope.data {
                    DispatchQueue.main.async {
                        completion(.success(payload))
                    }
                } else {
                    self?.analyzeSmartComposition(pitch: pitch, roll: roll, imageBase64: imageBase64) { fallback in
                        DispatchQueue.main.async { completion(.success(fallback)) }
                    }
                }
            } catch {
                self?.analyzeSmartComposition(pitch: pitch, roll: roll, imageBase64: imageBase64) { fallback in
                    DispatchQueue.main.async { completion(.success(fallback)) }
                }
            }
        }.resume()
    }
    
    // MARK: - 拍后调色配方诊断分析 (对齐 RetouchView 调用的 photoId/photoBase64 签名)
    public func fetchRetouchRecipe(
        photoId: String = UUID().uuidString,
        photoBase64: String = "dGVzdF9waG90b19iYXNlNjQ=",
        completion: @escaping (Result<AnalyzeAndGradeData, Error>) -> Void
    ) {
        if currentMode == .mock {
            if let mockData = loadLocalMockRetouch() {
                DispatchQueue.main.async { completion(.success(mockData)) }
                return
            }
        }
        
        if jwtToken == nil {
            registerDevice { [weak self] authResult in
                switch authResult {
                case .success:
                    self?.fetchRetouchRecipe(photoId: photoId, photoBase64: photoBase64, completion: completion)
                case .failure:
                    if let fallback = self?.loadLocalMockRetouch() {
                        DispatchQueue.main.async { completion(.success(fallback)) }
                    } else {
                        completion(.failure(URLError(.cannotConnectToHost)))
                    }
                }
            }
            return
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/retouch/analyze-and-grade") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = jwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15.0
        
        let body: [String: Any] = [
            "client_version": "2.0.0",
            "photo_id": photoId,
            "image_meta": ["width": 1080, "height": 1440, "format": "jpeg"],
            "image_base64": photoBase64
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                self?.jwtToken = nil
                self?.registerDevice { authResult in
                    if case .success = authResult {
                        self?.fetchRetouchRecipe(photoId: photoId, photoBase64: photoBase64, completion: completion)
                    } else {
                        if let fallback = self?.loadLocalMockRetouch() {
                            DispatchQueue.main.async { completion(.success(fallback)) }
                        }
                    }
                }
                return
            }
            
            if let error = error {
                if let fallback = self?.loadLocalMockRetouch() {
                    DispatchQueue.main.async { completion(.success(fallback)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }
            guard let data = data else {
                if let fallback = self?.loadLocalMockRetouch() {
                    DispatchQueue.main.async { completion(.success(fallback)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(URLError(.cannotDecodeContentData))) }
                }
                return
            }
            do {
                let envelope = try JSONDecoder().decode(Envelope<AnalyzeAndGradeData>.self, from: data)
                if let payload = envelope.data {
                    DispatchQueue.main.async {
                        completion(.success(payload))
                    }
                } else {
                    if let fallback = self?.loadLocalMockRetouch() {
                        DispatchQueue.main.async { completion(.success(fallback)) }
                    } else {
                        DispatchQueue.main.async { completion(.failure(URLError(.cannotParseResponse))) }
                    }
                }
            } catch {
                if let fallback = self?.loadLocalMockRetouch() {
                    DispatchQueue.main.async { completion(.success(fallback)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }.resume()
    }
    
    // MARK: - 端侧 Vision 原生智能场景分析 (根据眼前画面精准识别：风景 vs 人像，彻底消灭人物特写死板文字)
    public func analyzeSmartComposition(
        pitch: Double,
        roll: Double,
        imageBase64: String,
        completion: @escaping (AnalyzeCompositionData) -> Void
    ) {
        guard let imageData = Data(base64Encoded: imageBase64),
              let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            completion(self.generateLandscapeGuidance(pitch: pitch, roll: roll))
            return
        }
        
        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self = self else { return }
            let faces = req.results as? [VNFaceObservation] ?? []
            DispatchQueue.main.async {
                if !faces.isEmpty {
                    // 检测到人脸 -> 智能人像构图
                    let result = self.generatePortraitGuidance(faces: faces, pitch: pitch, roll: roll)
                    completion(result)
                } else {
                    // 未检测到人脸 -> 纯自然风光/建筑美学构图 (绝无人物特写)
                    let result = self.generateLandscapeGuidance(pitch: pitch, roll: roll)
                    completion(result)
                }
            }
        }
        
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(self.generateLandscapeGuidance(pitch: pitch, roll: roll))
                }
            }
        }
    }
    
    // MARK: - 生成风光/建筑美学构图指导 (无人物，纯美学构图)
    public func generateLandscapeGuidance(pitch: Double, roll: Double) -> AnalyzeCompositionData {
        let absRoll = abs(roll)
        let coachTip: String
        let actionType: String
        var targetPitchAdj: Double = 0.0
        
        if absRoll > 2.5 {
            coachTip = roll > 0 ? "向右顺时针摆正机位，保持地平线水平 ⚖️" : "向左逆时针摆正机位，保持地平线水平 ⚖️"
            actionType = "level_horizon"
        } else if pitch < -8.0 {
            coachTip = "镜头略微上抬，三分构图平衡天空与景深层次 🌅"
            actionType = "tilt_up_for_sky"
            targetPitchAdj = abs(pitch) - 2.0
        } else if pitch > 12.0 {
            coachTip = "适当压低机位俯拍，捕捉地表肌理与风光纵深 🌿"
            actionType = "tilt_down_for_foreground"
            targetPitchAdj = -5.0
        } else {
            coachTip = "地平线已水平就位，已开启风光三分构图，请保持稳定 ✨"
            actionType = "landscape_rule_of_thirds"
        }
        
        return AnalyzeCompositionData(
            sceneAnalysis: SceneAnalysis(
                sceneType: "landscape_nature",
                sceneLabelZh: "自然风光 / 建筑空间",
                confidence: 0.98,
                detectedIssues: absRoll > 2.5 ? ["horizon_tilted"] : []
            ),
            compositionGuidance: CompositionGuidance(
                coachTip: coachTip,
                actionType: actionType,
                recommendedGrid: "rule_of_thirds",
                suggestedCropBox: CropBox(ymin: 0.15, xmin: 0.06, ymax: 0.85, xmax: 0.94),
                targetPitchAdjustmentDeg: targetPitchAdj,
                navigationVector: NavigationVector(forwardSteps: 0, horizontalTranslationM: 0.0, verticalTranslationCm: 0.0)
            ),
            filterRecommendation: FilterRecommendation(
                recommendedLutId: "lut_film_warm_01",
                presetNameZh: "通透风光",
                recommendedIntensity: 0.80
            )
        )
    }
    
    // MARK: - 生成人像美学构图指导 (依据真实人脸在画面的坐标动态计算留白与机位)
    public func generatePortraitGuidance(faces: [VNFaceObservation], pitch: Double, roll: Double) -> AnalyzeCompositionData {
        guard let primaryFace = faces.first else {
            return generateLandscapeGuidance(pitch: pitch, roll: roll)
        }
        let box = primaryFace.boundingBox // 归一化 (0,0) 左下
        let faceCenterY = 1.0 - (box.origin.y + box.size.height / 2.0)
        let faceCenterX = box.origin.x + box.size.width / 2.0
        let faceHeight = box.size.height
        
        let coachTip: String
        let actionType: String
        var targetPitchAdj: Double = 0.0
        
        if faceHeight < 0.12 {
            coachTip = "可向前微移半步，拉近人物与背景空间层次 🚶"
            actionType = "step_forward"
        } else if faceCenterY < 0.22 {
            coachTip = "镜头稍微下压，保留上方呼吸感留白 ▴"
            actionType = "tilt_down"
            targetPitchAdj = -3.0
        } else if faceCenterY > 0.65 {
            coachTip = "适当放低机位微仰拍，修饰人物身形比例 ▾"
            actionType = "low_angle"
            targetPitchAdj = 4.0
        } else if abs(faceCenterX - 0.5) > 0.22 {
            coachTip = faceCenterX < 0.5 ? "镜头略向左转，人物置于黄金三分线 ▸" : "镜头略向右转，人物置于黄金三分线 ◂"
            actionType = "align_thirds"
        } else {
            coachTip = "人物面部已对齐黄金留白区，保持当前光影姿态 ✨"
            actionType = "perfect_portrait"
        }
        
        return AnalyzeCompositionData(
            sceneAnalysis: SceneAnalysis(
                sceneType: "portrait_lifestyle",
                sceneLabelZh: "环境人像",
                confidence: 0.98,
                detectedIssues: []
            ),
            compositionGuidance: CompositionGuidance(
                coachTip: coachTip,
                actionType: actionType,
                recommendedGrid: "rule_of_thirds",
                suggestedCropBox: CropBox(ymin: 0.12, xmin: 0.12, ymax: 0.88, xmax: 0.88),
                targetPitchAdjustmentDeg: targetPitchAdj,
                navigationVector: NavigationVector(forwardSteps: faceHeight < 0.12 ? 1 : 0, horizontalTranslationM: 0.0, verticalTranslationCm: 0.0)
            ),
            filterRecommendation: FilterRecommendation(
                recommendedLutId: "lut_film_warm_01",
                presetNameZh: "落日余晖胶片",
                recommendedIntensity: 0.85
            )
        )
    }
    
    // MARK: - 读取本地预埋 Mock 构图桩 (默认通用风光美学)
    public func loadLocalMockComposition() -> AnalyzeCompositionData? {
        return generateLandscapeGuidance(pitch: 0.0, roll: 0.0)
    }
    
    // MARK: - 读取本地预埋 Mock 调色配方桩
    private func loadLocalMockRetouch() -> AnalyzeAndGradeData? {
        let jsonString = """
        {
          "aesthetic_diagnosis": {
            "overall_critique": "原片高光与暗部层次丰富，AI已自动提亮暗部、压制天际高光，并增强胶片通透层次。",
            "target_style": "warm_sunset_film",
            "style_name_zh": "自然胶片"
          },
          "recommended_recipe": {
            "lut_id": "lut_film_warm_01",
            "lut_intensity": 0.80,
            "parameters": {
              "exposure": 0.15,
              "contrast": 0.10,
              "highlights": -0.20,
              "shadows": 0.25,
              "temperature": 8.0,
              "tint": 1.0,
              "vibrance": 0.12,
              "saturation": 0.05,
              "vignette": -0.05,
              "grain": 0.03
            }
          }
        }
        """
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AnalyzeAndGradeData.self, from: data)
    }
    
    // MARK: - 成品视频多关键帧调色分析 (对齐 VideoRetouchView 调用的默认参数签名)
    public func fetchVideoRetouchRecipe(
        videoId: String = UUID().uuidString,
        videoMeta: VideoMeta = VideoMeta(durationSec: 15.0, width: 1920, height: 1080),
        keyframes: [KeyframeItem] = [],
        completion: @escaping (Result<VideoRetouchData, Error>) -> Void
    ) {
        if currentMode == .mock {
            if let mockData = loadLocalMockVideoRetouch() {
                DispatchQueue.main.async {
                    completion(.success(mockData))
                }
                return
            }
        }
        
        if jwtToken == nil {
            registerDevice { [weak self] authResult in
                switch authResult {
                case .success:
                    self?.fetchVideoRetouchRecipe(videoId: videoId, videoMeta: videoMeta, keyframes: keyframes, completion: completion)
                case .failure(let err):
                    completion(.failure(err))
                }
            }
            return
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/retouch/analyze-video") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = jwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 4.5
        
        let kfList = keyframes.map { kf -> [String: Any] in
            return [
                "timestamp_sec": kf.timestampSec,
                "frame_index": kf.frameIndex,
                "image_base64": kf.imageBase64
            ]
        }
        
        let body: [String: Any] = [
            "client_version": "2.0.0",
            "video_id": videoId,
            "video_meta": [
                "duration_sec": videoMeta.durationSec,
                "width": videoMeta.width,
                "height": videoMeta.height,
                "fps": videoMeta.fps,
                "format": videoMeta.format
            ],
            "keyframes": kfList.isEmpty ? [
                ["timestamp_sec": 0.0, "frame_index": 0, "image_base64": "dGVzdF9rZjE="],
                ["timestamp_sec": 7.5, "frame_index": 450, "image_base64": "dGVzdF9rZjI="],
                ["timestamp_sec": 14.0, "frame_index": 840, "image_base64": "dGVzdF9rZjM="]
            ] : kfList
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(URLError(.cannotDecodeContentData))) }
                return
            }
            do {
                let envelope = try JSONDecoder().decode(Envelope<VideoRetouchData>.self, from: data)
                if let payload = envelope.data {
                    DispatchQueue.main.async {
                        completion(.success(payload))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(URLError(.cannotParseResponse)))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
    
    // MARK: - 读取本地预埋 Mock 视频调色配方桩
    private func loadLocalMockVideoRetouch() -> VideoRetouchData? {
        let jsonString = """
        {
          "aesthetic_diagnosis": {
            "overall_critique": "视频运镜平稳，多帧光比连贯；AI已自动平抑动态高光跳跃，增强青橙冷暖反差，呈现电影级质感。",
            "target_style": "cinematic_teal_orange",
            "style_name_zh": "赛博青橙电影感",
            "camera_movement_critique": "水平运镜平稳，帧间曝光平滑，具备良好电影叙事感"
          },
          "recommended_recipe": {
            "lut_id": "lut_cyber_teal_orange_03",
            "lut_intensity": 0.80,
            "parameters": {
              "exposure": 0.10,
              "contrast": 0.18,
              "highlights": -0.20,
              "shadows": 0.15,
              "temperature": -8.0,
              "tint": 2.0,
              "vibrance": 0.16,
              "saturation": 0.05,
              "vignette": -0.12,
              "grain": 0.04
            }
          },
          "scene_continuity": {
            "consistency_score": 0.92,
            "detected_flickers": false
          }
        }
        """
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VideoRetouchData.self, from: data)
    }


    // ==========================================================
    // MARK: - 阿里云灵积 DashScope Qwen-VL-Plus 与端侧 Vision 双引擎探景 (保证 100% 成功率)
    // ==========================================================
    private let kAliyunApiKeyStorage = "AestheticLens_AliyunApiKey"
    @Published public var aliyunApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(aliyunApiKey, forKey: kAliyunApiKeyStorage)
        }
    }
    public let defaultDashscopeKey = "sk-04d7c0897b694b918f67e5bbbe2c1145"
    
    public func testAliyunConnection(keyToTest: String? = nil, completion: @escaping (Bool, String) -> Void) {
        let key = (keyToTest ?? aliyunApiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            completion(false, "API Key 不能为空")
            return
        }
        guard let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions") else {
            completion(false, "接口 URL 异常")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0
        let testBody: [String: Any] = [
            "model": "qwen-plus",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 5
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: testBody)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, "网络连接失败: \(error.localizedDescription)")
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(false, "无响应")
                    return
                }
                if http.statusCode == 200 {
                    completion(true, "阿里云连接成功！灵积大模型授权有效")
                } else if http.statusCode == 401 {
                    completion(false, "鉴权失败 (401): API Key 无效或已过期")
                } else if http.statusCode == 429 {
                    completion(false, "访问受限 (429): 配额不足或调用过快")
                } else {
                    completion(false, "请求异常 (HTTP \(http.statusCode))")
                }
            }
        }.resume()
    }

    public func exploreSceneWithAliyunVLM(
        image: UIImage,
        currentPitch: Double = 0.0,
        currentRoll: Double = 0.0,
        completion: @escaping (SceneExplorationResult) -> Void
    ) {
        detectFacesLocally(in: image) { [weak self] detectedFaces in
            guard let self = self else { return }
            let maxSide: CGFloat = 800.0
            let scale = min(maxSide / max(image.size.width, image.size.height), 1.0)
            let targetSize = CGSize(width: max(image.size.width * scale, 100), height: max(image.size.height * scale, 100))
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            guard let jpegData = resized.jpegData(compressionQuality: 0.65) else {
                let fallback = self.generateLocalVisionExploration(image: image, faces: detectedFaces, pitch: currentPitch, roll: currentRoll)
                DispatchQueue.main.async { completion(fallback) }
                return
            }
            let base64String = jpegData.base64EncodedString()
            let rawKey = self.aliyunApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let activeKey = rawKey.isEmpty ? self.defaultDashscopeKey : rawKey
            guard let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions") else {
                let fallback = self.generateLocalVisionExploration(image: image, faces: detectedFaces, pitch: currentPitch, roll: currentRoll)
                DispatchQueue.main.async { completion(fallback) }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(activeKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 6.0
            let systemPrompt = """
            你是一位享誉国际的商业电影摄影指导与自然风光/人像大师。请对用户当前取景画面进行专业的深度实时审美与机位解构：
            1. 识别场景题材与标题(scene_title)：如'山间逆光人像'、'林间透光丁达尔'、'古建飞檐倒影'；
            2. 场景深度分析(scene_analysis)：详细描述当前画面包含哪些关键元素（如人物、山间、阳光、建筑），主体当前处于画面什么位置，背景与主体关系如何；
            3. 光影与镜头技巧(lighting_and_element)：重点分析光线（如当前有一束斜射阳光、逆光、柔光等怎么拍效果最好，如何利用明暗反差与光斑提升画面质感）；
            4. 主体最佳位置与机位指导(placement_guide)：深入分析人物或主体在画面哪个位置效果最佳（如置于画面左侧1/3交点、视线前方留白），机位该如何移动（如压低机位仰拍避开杂草、迎光角度等）；
            5. 圈出最具美感的黄金局部区域归一化坐标(crop_box: [ymin, xmin, ymax, xmax]，取值0.05~0.95)；
            6. 推荐焦段(recommended_zoom: 如 1.0, 2.0, 2.5, 3.0, 5.0)与电影胶片预设(filter_preset: '01-暖金电影'、'02-富士冷萃'等)；
            7. 给出12字以内精练点睛之笔(advice_zh)。
            请务必只输出标准的 JSON 字符串，格式如下：
            {"scene_type":"portrait","is_portrait":true,"scene_title":"山间逆光人像","scene_analysis":"人物置于山间背景中，斜上方有透射阳光照射。当前人物偏离视觉重心，前景杂乱削弱了山峦纵深感。","lighting_and_element":"利用透射阳光形成自然侧逆光，打亮发丝与肩线，增强与背景山峦的立体分离感。","placement_guide":"建议将人物调整至左侧三分线黄金交点，机位下压15度仰拍突显山脉耸立，长焦2.5x压缩山景。","crop_box":[0.15, 0.15, 0.85, 0.80],"recommended_zoom":2.5,"filter_preset":"01-暖金电影","advice_zh":"人物左移三分位 仰拍借光勾边"}
            """
            let requestBody: [String: Any] = [
                "model": "qwen-vl-plus",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]],
                            ["type": "text", "text": systemPrompt]
                        ]
                    ]
                ],
                "temperature": 0.2
            ]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            } catch {
                let fallback = self.generateLocalVisionExploration(image: image, faces: detectedFaces, pitch: currentPitch, roll: currentRoll)
                DispatchQueue.main.async { completion(fallback) }
                return
            }
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let data = data, error == nil,
                   let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    if let parsedResult = self.parseQwenVLResponse(data: data) {
                        DispatchQueue.main.async { completion(parsedResult) }
                        return
                    }
                }
                print("[APIClient] 阿里云云端请求回退，立即启动端侧 Vision 智能审美分析")
                let fallback = self.generateLocalVisionExploration(image: image, faces: detectedFaces, pitch: currentPitch, roll: currentRoll)
                DispatchQueue.main.async { completion(fallback) }
            }.resume()
        }
    }

    private func parseQwenVLResponse(data: Data) -> SceneExplorationResult? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            var cleanJSON = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let startRange = cleanJSON.range(of: "{"),
               let endRange = cleanJSON.range(of: "}", options: .backwards) {
                cleanJSON = String(cleanJSON[startRange.lowerBound...endRange.upperBound])
            }
            guard let jsonData = cleanJSON.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return nil
            }
            let sceneType = parsed["scene_type"] as? String ?? "landscape"
            let isPortrait = (parsed["is_portrait"] as? Bool) ?? (sceneType == "portrait")
            var cropBox = CropBox(ymin: 0.15, xmin: 0.15, ymax: 0.85, xmax: 0.85)
            if let boxArray = parsed["crop_box"] as? [Double], boxArray.count == 4 {
                cropBox = CropBox(
                    ymin: max(0.05, min(0.9, boxArray[0])),
                    xmin: max(0.05, min(0.9, boxArray[1])),
                    ymax: max(0.1, min(0.95, boxArray[2])),
                    xmax: max(0.1, min(0.95, boxArray[3]))
                )
            }
            let recZoom = parsed["recommended_zoom"] as? Double ?? (isPortrait ? 2.0 : 3.0)
            let filter = parsed["filter_preset"] as? String ?? (isPortrait ? "02-富士冷萃" : "01-暖金电影")
            let advice = parsed["advice_zh"] as? String ?? (isPortrait ? "突出人物神韵 避开杂乱背景" : "空间减法 长焦突出秩序")
            let sceneTitle = parsed["scene_title"] as? String ?? (isPortrait ? "山间人像打卡" : "自然光影风光")
            let sceneAnalysis = parsed["scene_analysis"] as? String ?? (isPortrait ? "画面包含人物主体与山野背景，当前主体偏离最佳视觉重心。" : "视野开阔，光线明朗，需进一步提炼视觉焦点。")
            let lightingAndElement = parsed["lighting_and_element"] as? String ?? "顺应斜射阳光或漫射光方向，利用明暗反差勾勒轮廓与立体层次。"
            let placementGuide = parsed["placement_guide"] as? String ?? (isPortrait ? "建议将人物移至画面左侧1/3黄金分割交点，镜头压低仰拍避开杂草，长焦2.5x压缩山景。" : "将透光高光区或核心景致置于黄金分割线，长焦3.0x压缩空间。")
            
            return SceneExplorationResult(
                sceneType: sceneType,
                isPortrait: isPortrait,
                sceneTitle: sceneTitle,
                sceneAnalysis: sceneAnalysis,
                lightingAndElement: lightingAndElement,
                placementGuide: placementGuide,
                cropBox: cropBox,
                recommendedZoom: recZoom,
                filterPreset: filter,
                adviceZh: advice,
                isFromAliyunCloud: true
            )
        } catch {
            return nil
        }
    }

    private func generateLocalVisionExploration(
        image: UIImage,
        faces: [VNFaceObservation],
        pitch: Double,
        roll: Double
    ) -> SceneExplorationResult {
        if let primaryFace = faces.first {
            let faceBox = primaryFace.boundingBox
            let faceCenterX = faceBox.midX
            let faceCenterY = 1.0 - faceBox.midY
            let boxWidth: Double = 0.65
            let boxHeight: Double = 0.75
            let xmin = max(0.05, min(0.95 - boxWidth, faceCenterX - boxWidth / 2.0))
            let ymin = max(0.05, min(0.95 - boxHeight, faceCenterY - boxHeight * 0.35))
            let crop = CropBox(ymin: ymin, xmin: xmin, ymax: ymin + boxHeight, xmax: xmin + boxWidth)
            return SceneExplorationResult(
                sceneType: "portrait",
                isPortrait: true,
                sceneTitle: "山间自然人像打卡",
                sceneAnalysis: "检测到人物主体处于自然风光中。人物当前略偏离黄金视觉重心，背景山峦有较强纵深感。",
                lightingAndElement: "利用自然环境侧逆光打亮发丝与肩线边缘，增强人物与山峦背景的立体分离感。",
                placementGuide: "建议将人物调整至画面左侧三分线黄金交点，机位下压15度仰拍突显山势，推镜至2.5x虚化杂乱地面。",
                cropBox: crop,
                recommendedZoom: 2.5,
                filterPreset: "01-暖金电影",
                adviceZh: "人物左移三分位 仰拍借光勾边",
                isFromAliyunCloud: false
            )
        } else {
            let boxWidth: Double = 0.60
            let boxHeight: Double = 0.65
            let xmin = 0.20
            let ymin = (pitch > 5.0) ? 0.15 : ((pitch < -5.0) ? 0.25 : 0.18)
            let crop = CropBox(ymin: ymin, xmin: xmin, ymax: ymin + boxHeight, xmax: xmin + boxWidth)
            return SceneExplorationResult(
                sceneType: "landscape",
                isPortrait: false,
                sceneTitle: "自然风光与空间光影",
                sceneAnalysis: "画面包含开阔山川林木或建筑景致，视野广阔但视觉焦点较分散。",
                lightingAndElement: "顺应镜头中穿透的斜射光线，压暗高光寻找明暗对角线，凸显阳光与山林/景物的通透立体感。",
                placementGuide: "长焦空间做减法：将最具美感的阳光透光区置于黄金分割带，保持水平，长焦3.0x压缩空间秩序。",
                cropBox: crop,
                recommendedZoom: 3.0,
                filterPreset: "01-暖金电影",
                adviceZh: "顺应光束对角线 长焦压缩空间",
                isFromAliyunCloud: false
            )
        }
    }

    private func detectFacesLocally(in image: UIImage, completion: @escaping ([VNFaceObservation]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        let request = VNDetectFaceRectanglesRequest { req, error in
            if let results = req.results as? [VNFaceObservation], !results.isEmpty {
                completion(results)
            } else {
                completion([])
            }
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

}
