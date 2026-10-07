import Foundation
import SwiftUI
import CoreMotion
import Combine

/// 实时构图引导状态枚举
public enum RealtimeGuidanceState: Equatable {
    case inactive       // 未启用实时引导
    case analyzing      // 正在深度透视与寻找最佳黄金构图 (阿里云大模型或端侧 Vision)
    case tracking       // 正在 60Hz 实时指挥用户移动镜头
    case aligned        // 完美就位！已移动到最佳构图位置！
}

/// 空间机位实时动作指令
public enum RealtimeMotionDirection: String, Equatable {
    case moveLeft = "向左平移 ◂◂"
    case moveRight = "向右平移 ▸▸"
    case moveCloser = "向前推进 ⊕"
    case moveFurther = "后退少许 ⊖"
    case tiltUp = "镜头上抬 ▴"
    case tiltDown = "压低机位 ▾"
    case levelHorizon = "水平校正 ⚖️"
    case perfect = "已处于最佳构图机位"
}

/// 灵瞳 AI 实时构图指挥引擎 (对标 Doka 相机与专业摄影做减法，具备抗微抖低通滤波与双门槛迟滞磁吸)
public final class RealtimeCompositionEngine: ObservableObject {
    public static let shared = RealtimeCompositionEngine()
    
    // MARK: - 实时发布给 HUD 呈现层的响应式属性
    @Published public var state: RealtimeGuidanceState = .inactive
    @Published public var currentDirection: RealtimeMotionDirection = .perfect
    @Published public var currentTip: String = ""
    @Published public var sceneTypeZh: String = "风光建筑"
    @Published public var recommendedZoom: Double = 1.0
    @Published public var isCloudAI: Bool = false
    @Published public var alignmentProgress: Double = 0.0 // 0.0 ~ 1.0
    
    // 目标黄金取景框与中心坐标 (归一化 0.0 ~ 1.0)
    @Published public var targetCropBox: CropBox = CropBox(ymin: 0.15, xmin: 0.15, ymax: 0.85, xmax: 0.85)
    @Published public var targetCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published public var targetPitch: Double = 0.0
    
    // 当前十字准星 (经低通防抖滤波后)
    @Published public var liveCrosshair: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published public var isAligned: Bool = false
    
    // MARK: - 内部抗手颤滤波与容差参数
    private let motionManager = MotionManager.shared
    private let apiClient = APIClient.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 磁吸滞后窗口参数 (彻底解决人手微颤反复丢失最佳角度问题)
    private let snapInCenterTolerance: Double = 0.085    // 进入对齐门槛 (8.5% 容差)
    private let snapInAngleTolerance: Double = 2.8      // 进入角度门槛 (2.8°)
    private let snapInRollTolerance: Double = 2.2       // 进入水平门槛 (2.2°)
    
    private let releaseCenterTolerance: Double = 0.140  // 迟滞脱离门槛 (14.0% 宽容度)
    private let releaseAngleTolerance: Double = 4.2     // 迟滞脱离门槛 (4.2°)
    
    // 磁吸保持时间戳 (一旦对齐立即锁定 1.5 秒从容快门窗口)
    private var stickyLockUntil: Date = .distantPast
    private var hasTriggeredLockHaptic: Bool = false
    
    // 一阶低通滤波平滑变量 (过滤 3~5Hz 人手微颤)
    private var smoothedOffsetX: Double = 0.0
    private var smoothedOffsetY: Double = 0.0
    
    public init() {
        setupMotionObserver()
    }
    
    // MARK: - 监听运动传感器
    private func setupMotionObserver() {
        motionManager.$pitchDegrees
            .combineLatest(motionManager.$rollDegrees, motionManager.$isLevel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pitch, roll, isLevel in
                guard let self = self, self.state == .tracking || self.state == .aligned else { return }
                self.processLiveMotionUpdate(currentPitch: pitch, currentRoll: roll)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 启动与停止
    public func startRealtimeGuidance(cameraManager: CameraManager) {
        state = .analyzing
        currentTip = "AI 正在全景透视，寻找黄金机位..."
        alignmentProgress = 0.3
        hasTriggeredLockHaptic = false
        stickyLockUntil = .distantPast
        
        // 捕获全景帧并调用阿里云大模型/本地 Vision
        fetchOptimalComposition(cameraManager: cameraManager)
    }
    
    public func stopRealtimeGuidance() {
        state = .inactive
        isAligned = false
        currentTip = ""
        alignmentProgress = 0.0
        hasTriggeredLockHaptic = false
        stickyLockUntil = .distantPast
    }
    
    // MARK: - 调用阿里云 Qwen-VL 与端侧双引擎圈定最佳区域
    public func fetchOptimalComposition(cameraManager: CameraManager) {
        guard state != .inactive else { return }
        
        let handleFrame: (UIImage) -> Void = { [weak self] frame in
            guard let self = self else { return }
            self.apiClient.exploreSceneWithAliyunVLM(
                image: frame,
                currentPitch: self.motionManager.pitchDegrees,
                currentRoll: self.motionManager.rollDegrees
            ) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.targetCropBox = result.cropBox
                    self.targetCenter = CGPoint(
                        x: (result.cropBox.xmin + result.cropBox.xmax) / 2.0,
                        y: (result.cropBox.ymin + result.cropBox.ymax) / 2.0
                    )
                    self.targetPitch = (abs(self.motionManager.pitchDegrees) > 8.0) ? self.motionManager.pitchDegrees : 0.0
                    self.currentTip = result.adviceZh
                    self.sceneTypeZh = result.isPortrait ? "人物肖像" : "风光建筑"
                    self.recommendedZoom = result.recommendedZoom
                    self.isCloudAI = result.isFromAliyunCloud
                    self.state = .tracking
                }
            }
        }
        
        if let currentImage = cameraManager.captureLatestPreviewFrame() {
            handleFrame(currentImage)
        } else {
            cameraManager.takePhoto { photo in
                if let p = photo {
                    handleFrame(p)
                } else {
                    DispatchQueue.main.async {
                        self.state = .tracking
                        self.currentTip = "长焦空间压缩 避开边缘人流"
                        self.sceneTypeZh = "风光建筑"
                        self.recommendedZoom = 3.0
                    }
                }
            }
        }
    }
    
    // MARK: - 实时抗手抖平滑与磁吸锁止算法
    private func processLiveMotionUpdate(currentPitch: Double, currentRoll: Double) {
        let deltaPitch = targetPitch - currentPitch
        let deltaRoll = 0.0 - currentRoll
        
        // 1. 物理位置偏移量计算 (归一化空间)
        let rawOffsetX = (deltaRoll / 18.0).clamped(to: -0.35...0.35)
        let rawOffsetY = (-deltaPitch / 18.0).clamped(to: -0.35...0.35)
        
        // 2. 一阶低通滤波：平滑手部 3~5Hz 生理微颤 (Alpha = 0.28)
        smoothedOffsetX = smoothedOffsetX * 0.72 + rawOffsetX * 0.28
        smoothedOffsetY = smoothedOffsetY * 0.72 + rawOffsetY * 0.28
        
        let liveX = (targetCenter.x + smoothedOffsetX).clamped(to: 0.1...0.9)
        let liveY = (targetCenter.y + smoothedOffsetY).clamped(to: 0.1...0.9)
        self.liveCrosshair = CGPoint(x: liveX, y: liveY)
        
        let errorX = targetCenter.x - liveX
        let errorY = targetCenter.y - liveY
        let totalDistance = sqrt(errorX * errorX + errorY * errorY)
        let absErrorPitch = abs(deltaPitch)
        let absErrorRoll = abs(deltaRoll)
        
        // 3. 计算连续平滑对齐进度 (0% ~ 100%)
        let progress = max(0.0, min(1.0, 1.0 - (totalDistance / 0.35 * 0.6 + (absErrorPitch / 14.0) * 0.4)))
        self.alignmentProgress = progress
        
        // 4. 双门槛迟滞吸附逻辑 (Hysteresis Snap)
        let now = Date()
        let isWithinSnapIn = (totalDistance < snapInCenterTolerance && absErrorPitch < snapInAngleTolerance && absErrorRoll < snapInRollTolerance)
        let isWithinRelease = (totalDistance < releaseCenterTolerance && absErrorPitch < releaseAngleTolerance)
        
        if isWithinSnapIn || (self.isAligned && isWithinRelease) || (now < stickyLockUntil) {
            // 处于最佳对齐或磁吸保持窗内
            if !self.isAligned {
                self.isAligned = true
                self.state = .aligned
                self.currentDirection = .perfect
                // 启动 1.5 秒磁吸锁止保护窗
                stickyLockUntil = now.addingTimeInterval(1.5)
                
                if !hasTriggeredLockHaptic {
                    hasTriggeredLockHaptic = true
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }
            }
        } else {
            // 真正超出容差保护范围才脱离
            self.isAligned = false
            self.state = .tracking
            self.hasTriggeredLockHaptic = false
            
            // 实时给出方向指引
            if absErrorRoll > 2.5 {
                currentDirection = .levelHorizon
            } else if deltaPitch > 3.0 {
                currentDirection = .tiltUp
            } else if deltaPitch < -3.0 {
                currentDirection = .tiltDown
            } else if deltaRoll > 2.0 {
                currentDirection = .moveLeft
            } else if deltaRoll < -2.0 {
                currentDirection = .moveRight
            } else {
                currentDirection = .perfect
            }
        }
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
