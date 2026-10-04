import Foundation
import SwiftUI
import CoreMotion
import Combine

/// 实时构图引导状态枚举
public enum RealtimeGuidanceState: Equatable {
    case inactive       // 未启用实时引导
    case analyzing      // 正在深度透视与寻找最佳黄金构图
    case tracking       // 正在 60Hz 实时指挥用户移动镜头
    case aligned        // ✨ 完美就位！已移动到最佳构图位置！
}

/// 空间机位实时动作指令
public enum RealtimeMotionDirection: String, Equatable {
    case moveLeft = "向左平移 ◂◂"
    case moveRight = "向右平移 ▸▸"
    case moveCloser = "向前推进 ▲"
    case moveFurther = "后退少许 ▼"
    case tiltUp = "镜头上抬 ▴"
    case tiltDown = "压低机位 ▾"
    case levelHorizon = "水平校正 ⚖️"
    case perfect = "✨ 已移动到最佳构图位置！"
}

/// 灵瞳 AI 实时构图指挥引擎 (借鉴三星 Shot Suggestion 与谷歌 Guided Frame 双闭环端云协同架构)
public final class RealtimeCompositionEngine: ObservableObject {
    public static let shared = RealtimeCompositionEngine()
    
    // MARK: - 实时发布给 HUD 呈现层的响应式属性
    @Published public var state: RealtimeGuidanceState = .inactive
    @Published public var currentDirection: RealtimeMotionDirection = .perfect
    @Published public var currentTip: String = ""
    @Published public var alignmentProgress: Double = 0.0 // 0.0 ~ 1.0 对齐进度环
    
    // 目标黄金构图几何参数 (归一化 0.0 ~ 1.0)
    @Published public var targetCropBox: CropBox = CropBox(ymin: 0.15, xmin: 0.12, ymax: 0.85, xmax: 0.88)
    @Published public var targetCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published public var targetPitch: Double = 0.0
    
    // 实时机位准星位置 (随手机姿态与运动 60Hz 动态移动)
    @Published public var liveCrosshair: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published public var isAligned: Bool = false
    
    // MARK: - 底层传感器与依赖
    private let motionManager = MotionManager.shared
    private let apiClient = APIClient.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 连续稳定帧计数与触感反馈防抖
    private var alignedFrameCount: Int = 0
    private var hasTriggeredLockHaptic: Bool = false
    private var lastAnalysisTimestamp: Date = .distantPast
    
    // 动态空间位姿积分与偏移平滑
    private var smoothedOffsetX: Double = 0.0
    private var smoothedOffsetY: Double = 0.0
    private var smoothedPitchDelta: Double = 0.0
    
    // 容差带配置 (达到最佳构图的判定门限)
    private let centerTolerance: Double = 0.045      // 中心对准容差 (4.5%)
    private let angleTolerance: Double = 2.0         // 俯仰角度容差 (2.0°)
    private let rollTolerance: Double = 1.5          // 水平翻滚容差 (1.5°)
    
    public init() {
        setupMotionObserver()
    }
    
    // MARK: - 监听 60Hz 设备姿态，实时解算镜头移动与指挥逻辑
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
    
    // MARK: - 开启 / 关闭 AI 实时构图指挥模式
    public func toggleRealtimeMode(cameraManager: CameraManager) {
        if state == .inactive {
            startRealtimeGuidance(cameraManager: cameraManager)
        } else {
            stopRealtimeGuidance()
        }
    }
    
    public func startRealtimeGuidance(cameraManager: CameraManager) {
        state = .analyzing
        currentTip = "灵瞳 AI 正在透视场景，锁定最佳黄金构图..."
        alignmentProgress = 0.2
        hasTriggeredLockHaptic = false
        alignedFrameCount = 0
        
        // 抓取当前取景帧进行首帧审美分析
        fetchOptimalComposition(cameraManager: cameraManager)
    }
    
    public func stopRealtimeGuidance() {
        state = .inactive
        isAligned = false
        currentTip = ""
        alignmentProgress = 0.0
        hasTriggeredLockHaptic = false
    }
    
    // MARK: - 提取取景帧并向云端/本地美学中台请求最佳构图目标
    public func fetchOptimalComposition(cameraManager: CameraManager) {
        guard state != .inactive else { return }
        lastAnalysisTimestamp = Date()
        
        var hasDispatched = false
        let analyzeClosure: (UIImage?) -> Void = { [weak self] capturedFrame in
            guard let self = self, !hasDispatched else { return }
            hasDispatched = true
            
            var payloadBase64 = "dGVzdF9iYXNlNjQ="
            if let frame = capturedFrame {
                let maxSide: CGFloat = 720.0
                let scale = min(maxSide / max(frame.size.width, frame.size.height), 1.0)
                let targetSize = CGSize(width: max(frame.size.width * scale, 100), height: max(frame.size.height * scale, 100))
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                let resized = renderer.image { _ in
                    frame.draw(in: CGRect(origin: .zero, size: targetSize))
                }
                if let data = resized.jpegData(compressionQuality: 0.6) {
                    payloadBase64 = data.base64EncodedString()
                }
            }
            
            self.apiClient.fetchCompositionGuidance(
                pitch: self.motionManager.pitchDegrees,
                roll: self.motionManager.rollDegrees,
                imageBase64: payloadBase64
            ) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        let guidance = data.compositionGuidance
                        self.targetCropBox = guidance.suggestedCropBox
                        self.targetCenter = CGPoint(
                            x: (guidance.suggestedCropBox.xmin + guidance.suggestedCropBox.xmax) / 2.0,
                            y: (guidance.suggestedCropBox.ymin + guidance.suggestedCropBox.ymax) / 2.0
                        )
                        self.targetPitch = self.motionManager.pitchDegrees + (guidance.targetPitchAdjustmentDeg ?? 0.0)
                        self.state = .tracking
                        self.currentTip = "已锁定最佳构图！请跟随实时指示移动手机"
                    case .failure:
                        // 本地黄金对称/三分法保底
                        self.targetCropBox = CropBox(ymin: 0.15, xmin: 0.15, ymax: 0.85, xmax: 0.85)
                        self.targetCenter = CGPoint(x: 0.5, y: 0.5)
                        self.targetPitch = 0.0
                        self.state = .tracking
                        self.currentTip = "已开启智能构图，请跟随实时指示移动手机"
                    }
                }
            }
        }
        
        cameraManager.takePhoto { frame in
            analyzeClosure(frame)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            analyzeClosure(nil)
        }
    }
    
    // MARK: - 60Hz 核心数学计算：计算位姿偏差、生成实时指挥动作并检测是否对准
    private func processLiveMotionUpdate(currentPitch: Double, currentRoll: Double) {
        // 1. 俯仰差值与翻滚差值
        let deltaPitch = targetPitch - currentPitch
        let deltaRoll = 0.0 - currentRoll // 期望水平为 0°
        
        // 2. 空间游标位置计算 (结合俯仰角与翻滚角模拟镜头光轴投影，带来毫秒级体感反馈)
        // 俯仰 1 度对应垂直偏移约 0.02 归一化坐标，水平翻滚对应横向微移
        let rawOffsetX = (deltaRoll / 15.0).clamped(to: -0.35...0.35)
        let rawOffsetY = (-deltaPitch / 15.0).clamped(to: -0.35...0.35)
        
        // 低通平滑滤波器，避免手部微颤导致准星剧烈抖动 (Alpha = 0.25)
        smoothedOffsetX = smoothedOffsetX * 0.75 + rawOffsetX * 0.25
        smoothedOffsetY = smoothedOffsetY * 0.75 + rawOffsetY * 0.25
        
        let liveX = (targetCenter.x + smoothedOffsetX).clamped(to: 0.1...0.9)
        let liveY = (targetCenter.y + smoothedOffsetY).clamped(to: 0.1...0.9)
        self.liveCrosshair = CGPoint(x: liveX, y: liveY)
        
        // 3. 计算与目标中心的欧式距离与各轴向误差
        let errorX = targetCenter.x - liveX
        let errorY = targetCenter.y - liveY
        let absErrorPitch = abs(deltaPitch)
        let absErrorRoll = abs(deltaRoll)
        let totalDistance = sqrt(errorX * errorX + errorY * errorY)
        
        // 4. 计算综合对齐吻合度进度 (0% ~ 100%)
        let progress = max(0.0, min(1.0, 1.0 - (totalDistance / 0.35 * 0.6 + (absErrorPitch / 12.0) * 0.4)))
        self.alignmentProgress = progress
        
        // 5. 判断是否进入“最佳构图就位状态”
        let isPositionAligned = totalDistance < centerTolerance
        let isPitchAligned = absErrorPitch < angleTolerance
        let isRollAligned = absErrorRoll < rollTolerance
        
        if isPositionAligned && isPitchAligned && isRollAligned {
            alignedFrameCount += 1
            if alignedFrameCount >= 3 { // 连续 3 帧稳定即可锁定
                if !isAligned {
                    self.isAligned = true
                    self.state = .aligned
                    self.currentDirection = .perfect
                    self.currentTip = "✨ 已移动到最佳构图位置！"
                    
                    // 仅在初次对准时触发一次清脆触感反馈 (对标三星 Galaxy Shot Suggestion 触感)
                    if !hasTriggeredLockHaptic {
                        hasTriggeredLockHaptic = true
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                }
            }
        } else {
            // 未对准或移动偏离，恢复实时指挥
            alignedFrameCount = 0
            if isAligned {
                self.isAligned = false
                self.state = .tracking
                self.hasTriggeredLockHaptic = false
            }
            
            // 实时生成最迫切的修正指令 (优先级：水平校正 > 垂直俯仰 > 左右平移)
            if absErrorRoll > 3.0 {
                self.currentDirection = .levelHorizon
                self.currentTip = deltaRoll > 0 ? "向右顺时针摆正手机 ⚖️" : "向左逆时针摆正手机 ⚖️"
            } else if absErrorPitch > 3.0 {
                if deltaPitch > 0 {
                    self.currentDirection = .tiltUp
                    self.currentTip = String(format: "▴ 镜头稍微上抬 (%.0f°)", absErrorPitch)
                } else {
                    self.currentDirection = .tiltDown
                    self.currentTip = String(format: "▾ 镜头微向下压 (%.0f°)", absErrorPitch)
                }
            } else if abs(errorX) > 0.03 {
                if errorX > 0 {
                    self.currentDirection = .moveRight
                    self.currentTip = "▸▸ 镜头向右平移"
                } else {
                    self.currentDirection = .moveLeft
                    self.currentTip = "◂◂ 镜头向左平移"
                }
            } else if abs(errorY) > 0.03 {
                if errorY > 0 {
                    self.currentDirection = .tiltDown
                    self.currentTip = "▾ 压低机位俯拍"
                } else {
                    self.currentDirection = .tiltUp
                    self.currentTip = "▴ 提高机位仰拍"
                }
            } else {
                self.currentDirection = .perfect
                self.currentTip = "接近最佳构图，请保持稳定..."
            }
        }
    }
}

// MARK: - 辅助数学扩展
private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
