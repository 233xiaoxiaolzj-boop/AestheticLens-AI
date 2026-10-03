import Foundation
import Combine

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

/// 端云通信中台客户端 (支持生产 Live 与离线 Mock 双保险自由切换)
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
        request.timeoutInterval = 3.0
        
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
    
    // MARK: - 取景抽帧场景与构图分析
    public func fetchCompositionGuidance(
        pitch: Double,
        roll: Double,
        imageBase64: String = "dGVzdF9iYXNlNjQ=",
        completion: @escaping (Result<AnalyzeCompositionData, Error>) -> Void
    ) {
        // 1. 本地 Mock 模式直接从预置样本读取 (0 延迟，断网防翻车)
        if currentMode == .mock {
            if let mockData = loadLocalMockComposition() {
                DispatchQueue.main.async {
                    completion(.success(mockData))
                }
                return
            }
        }
        
        // 2. 检查是否有 JWT 令牌，若无先静默注册
        if jwtToken == nil {
            registerDevice { [weak self] authResult in
                switch authResult {
                case .success:
                    self?.fetchCompositionGuidance(pitch: pitch, roll: roll, imageBase64: imageBase64, completion: completion)
                case .failure(let err):
                    completion(.failure(err))
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
        request.timeoutInterval = 2.0 // 2.0s 严格熔断阈值
        
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
                let envelope = try JSONDecoder().decode(Envelope<AnalyzeCompositionData>.self, from: data)
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
    
    // MARK: - 拍后美学调色配方生成
    public func fetchRetouchRecipe(
        photoId: String = UUID().uuidString,
        photoBase64: String = "dGVzdF9waG90b19iYXNlNjQ=",
        completion: @escaping (Result<AnalyzeAndGradeData, Error>) -> Void
    ) {
        // 1. 本地 Mock 模式直接从预置样本读取
        if currentMode == .mock {
            if let mockData = loadLocalMockRetouch() {
                DispatchQueue.main.async {
                    completion(.success(mockData))
                }
                return
            }
        }
        
        // 2. 检查是否有 JWT 令牌
        if jwtToken == nil {
            registerDevice { [weak self] authResult in
                switch authResult {
                case .success:
                    self?.fetchRetouchRecipe(photoId: photoId, photoBase64: photoBase64, completion: completion)
                case .failure(let err):
                    completion(.failure(err))
                }
            }
            return
        }
        
        // 3. 在线云端请求
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
        request.timeoutInterval = 3.5 // 调色分析给与更充裕的云端时延
        
        let body: [String: Any] = [
            "client_version": "2.0.0",
            "photo_id": photoId,
            "image_meta": ["width": 1080, "height": 1440, "format": "jpeg"],
            "image_base64": photoBase64
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
                let envelope = try JSONDecoder().decode(Envelope<AnalyzeAndGradeData>.self, from: data)
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
    
    // MARK: - 读取本地预埋 Mock 构图桩
    private func loadLocalMockComposition() -> AnalyzeCompositionData? {
        let jsonString = """
        {
          "scene_analysis": {
            "scene_type": "portrait_sunset",
            "scene_label_zh": "逆光夕阳人像",
            "confidence": 0.95,
            "detected_issues": ["headroom_too_large", "horizon_tilted"]
          },
          "composition_guidance": {
            "coach_tip": "建议放低机位并前进两步，突出人物特写",
            "action_type": "low_angle_and_closer",
            "recommended_grid": "rule_of_thirds",
            "suggested_crop_box": {
              "ymin": 0.15,
              "xmin": 0.10,
              "ymax": 0.95,
              "xmax": 0.90
            },
            "target_pitch_adjustment_deg": 5.0,
            "navigation_vector": {
              "forward_steps": 2,
              "horizontal_translation_m": -0.5,
              "vertical_translation_cm": -15.0
            }
          },
          "filter_recommendation": {
            "recommended_lut_id": "lut_film_warm_01",
            "preset_name_zh": "落日余晖胶片",
            "recommended_intensity": 0.85
          }
        }
        """
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AnalyzeCompositionData.self, from: data)
    }
    
    // MARK: - 读取本地预埋 Mock 调色配方桩
    private func loadLocalMockRetouch() -> AnalyzeAndGradeData? {
        let jsonString = """
        {
          "aesthetic_diagnosis": {
            "overall_critique": "原片逆光导致面部轻微暗沉，AI已自动提亮暗部、压制天际高光，并增强暖金调色温。",
            "target_style": "warm_sunset_film",
            "style_name_zh": "落日余晖胶片"
          },
          "recommended_recipe": {
            "lut_id": "lut_film_warm_01",
            "lut_intensity": 0.85,
            "parameters": {
              "exposure": 0.25,
              "contrast": 0.12,
              "highlights": -0.30,
              "shadows": 0.35,
              "temperature": 15.0,
              "tint": 2.0,
              "vibrance": 0.20,
              "saturation": 0.08,
              "vignette": -0.10,
              "grain": 0.05
            }
          }
        }
        """
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AnalyzeAndGradeData.self, from: data)
    }
    
    // MARK: - 视频多关键帧 AI 调色配方生成
    public func fetchVideoRetouchRecipe(
        videoId: String = UUID().uuidString,
        videoMeta: VideoMeta = VideoMeta(durationSec: 15.0, width: 1920, height: 1080),
        keyframes: [KeyframeItem] = [],
        completion: @escaping (Result<VideoRetouchData, Error>) -> Void
    ) {
        // 1. 本地 Mock 模式直接从预置视频样本读取
        if currentMode == .mock {
            if let mockData = loadLocalMockVideoRetouch() {
                DispatchQueue.main.async {
                    completion(.success(mockData))
                }
                return
            }
        }
        
        // 2. 检查是否有 JWT 令牌
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
        
        // 3. 在线云端请求
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
        
        // 组装关键帧字典
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
    
    // MARK: - 读取本地预埋视频调色配方桩
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
}

