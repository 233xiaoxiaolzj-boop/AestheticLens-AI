import SwiftUI

/// 60Hz 采样微光水平仪 HUD (误差 <0.5° 时亮绿吸附)
public struct LevelGaugeView: View {
    @ObservedObject var motionManager = MotionManager.shared
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 水平基准中轴虚线
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 140, height: 1)
            
            // 实时倾角指示横线 (随 roll 角度动态旋转)
            Rectangle()
                .fill(motionManager.isLevel ? Color.green : Color.yellow.opacity(0.8))
                .frame(width: motionManager.isLevel ? 160 : 120, height: motionManager.isLevel ? 2.5 : 1.5)
                .rotationEffect(.degrees(-motionManager.rollDegrees))
                .shadow(color: motionManager.isLevel ? Color.green.opacity(0.8) : Color.clear, radius: 4)
                .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: motionManager.rollDegrees)
            
            // 中心圆点对准器
            Circle()
                .fill(motionManager.isLevel ? Color.green : Color.white.opacity(0.6))
                .frame(width: 4, height: 4)
        }
        .allowsHitTesting(false)
    }
}
