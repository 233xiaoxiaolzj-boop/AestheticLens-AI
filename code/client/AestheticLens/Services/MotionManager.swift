import Foundation
import CoreMotion
import AVFoundation
import Combine

/// 60Hz CoreMotion 设备姿态解算与物理横竖屏检测服务
public final class MotionManager: ObservableObject {
    public static let shared = MotionManager()
    
    private let motionManager = CMMotionManager()
    
    // 发布给 SwiftUI 取景器的实时数据
    @Published public var pitchDegrees: Double = 0.0
    @Published public var rollDegrees: Double = 0.0
    @Published public var isLevel: Bool = false
    @Published public var physicalOrientation: AVCaptureVideoOrientation = .portrait
    
    // 判定水平状态的标准误差阈值 (< 0.5°)
    private let levelThresholdDeg: Double = 0.5
    // 物理横竖屏切换重力阈值 (带滞后区间避免 45° 临界抖动)
    private let orientationThreshold: Double = 0.68
    
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
            self.isLevel = (abs(pitchDeg) < self.levelThresholdDeg) && (abs(rollDeg) < self.levelThresholdDeg)
            
            // 利用重力分量检测真实物理朝向 (即使系统锁定了竖屏依然生效)
            let gx = motion.gravity.x
            let gy = motion.gravity.y
            var nextOrientation: AVCaptureVideoOrientation? = nil
            
            if gx < -self.orientationThreshold {
                // 设备逆时针横置 (充电口在右) -> 对应 AVCaptureVideoOrientation.landscapeRight
                nextOrientation = .landscapeRight
            } else if gx > self.orientationThreshold {
                // 设备顺时针横置 (充电口在左) -> 对应 AVCaptureVideoOrientation.landscapeLeft
                nextOrientation = .landscapeLeft
            } else if gy < -self.orientationThreshold {
                nextOrientation = .portrait
            } else if gy > self.orientationThreshold {
                nextOrientation = .portraitUpsideDown
            }
            
            if let detected = nextOrientation, detected != self.physicalOrientation {
                self.physicalOrientation = detected
            }
        }
    }
    
    public func stopDeviceMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}