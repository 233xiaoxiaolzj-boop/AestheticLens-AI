import Foundation
import CoreMotion
import Combine

/// 60Hz CoreMotion 设备姿态解算服务
public final class MotionManager: ObservableObject {
    public static let shared = MotionManager()
    
    private let motionManager = CMMotionManager()
    
    // 发布给 SwiftUI 取景器的实时数据
    @Published public var pitchDegrees: Double = 0.0
    @Published public var rollDegrees: Double = 0.0
    @Published public var isLevel: Bool = false
    
    // 判定水平状态的标准误差阈值 (对齐附录 A 与 M1 验收指标 < 0.5°)
    private let levelThresholdDeg: Double = 0.5
    
    public init() {
        startDeviceMotionUpdates()
    }
    
    public func startDeviceMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("[MotionManager] 模拟器或硬件不支持 DeviceMotion")
            return
        }
        
        // 60Hz 采样率 (1.0 / 60.0 = 0.0166s)
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion, error == nil else { return }
            
            // 弧度转角度
            let pitchDeg = motion.attitude.pitch * (180.0 / .pi)
            let rollDeg = motion.attitude.roll * (180.0 / .pi)
            
            self.pitchDegrees = pitchDeg
            self.rollDegrees = rollDeg
            
            // 绝对误差在 0.5° 以内判定为水平锁准
            let pitchError = abs(pitchDeg)
            let rollError = abs(rollDeg)
            self.isLevel = (pitchError < self.levelThresholdDeg) && (rollError < self.levelThresholdDeg)
        }
    }
    
    public func stopDeviceMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}
