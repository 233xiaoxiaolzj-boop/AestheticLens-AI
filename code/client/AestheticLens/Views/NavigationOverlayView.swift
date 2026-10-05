import SwiftUI

/// 空间机位 4D 实时 AR 构图对齐 HUD (对标三星 Shot Suggestion 与谷歌 Guided Frame)
/// 严格遵守用户交互规范：未点击 AI 实时构图指挥时 100% 纯净隐身，点击开启后才唤出 AR 空间框线与实时指令胶囊
public struct NavigationOverlayView: View {
    public let guidance: CompositionGuidance?
    @ObservedObject private var engine = RealtimeCompositionEngine.shared
    @ObservedObject private var motionManager = MotionManager.shared
    
    // 对准时呼吸特效
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.5
    
    public init(guidance: CompositionGuidance? = nil) {
        self.guidance = guidance
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            
            // 判断是否实时引导中 (严格门控：仅在引擎处于激活跟踪/锁定状态时呈现，彻底杜绝开机常驻固定死板提示)
            let isRealtimeActive = (engine.state != .inactive)
            
            if isRealtimeActive {
                let crop = engine.targetCropBox
                let isLocked = engine.isAligned
                
                let boxW = (crop.xmax - crop.xmin) * w
                let boxH = (crop.ymax - crop.ymin) * h
                let boxCenterX = (crop.xmin + crop.xmax) / 2.0 * w
                let boxCenterY = (crop.ymin + crop.ymax) / 2.0 * h
                
                ZStack {
                    // ==========================================
                    // 1. AR 黄金构图目标框 (未对准时金色虚线，对准时翠绿实线加粗并伴随外发光脉冲)
                    // ==========================================
                    ZStack {
                        // 锁定状态外发光脉冲
                        if isLocked {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    Color(red: 0.0, green: 0.95, blue: 0.45).opacity(0.35),
                                    lineWidth: 8
                                )
                                .blur(radius: 6)
                                .frame(width: boxW, height: boxH)
                                .scaleEffect(pulseScale)
                                .animation(
                                    Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                    value: pulseScale
                                )
                        }
                        
                        // 构图建议目标框
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color(red: 1.0, green: 0.85, blue: 0.3).opacity(0.85),
                                style: StrokeStyle(
                                    lineWidth: isLocked ? 2.5 : 1.5,
                                    dash: isLocked ? [] : [7, 5]
                                )
                            )
                            .frame(width: boxW, height: boxH)
                        
                        // 四角专业摄影取景锚点 (L型标尺)
                        CornerBrackets(width: boxW, height: boxH, isLocked: isLocked)
                            .stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color.white.opacity(0.9),
                                lineWidth: 2.5
                            )
                    }
                    .position(x: boxCenterX, y: boxCenterY)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isLocked)
                    
                    // ==========================================
                    // 2. 空间构图目标锚点环 (Target Halo Ring)
                    // ==========================================
                    let targetAnchorX = engine.targetCenter.x * w
                    let targetAnchorY = engine.targetCenter.y * h
                    
                    ZStack {
                        // 目标环外围
                        Circle()
                            .stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45).opacity(0.8) : Color.yellow.opacity(0.4),
                                lineWidth: 1.5
                            )
                            .frame(width: 32, height: 32)
                            .scaleEffect(isLocked ? pulseScale : 1.0)
                        
                        // 目标圆心小环
                        Circle()
                            .stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color.yellow.opacity(0.8),
                                lineWidth: 2.0
                            )
                            .frame(width: 14, height: 14)
                    }
                    .position(x: targetAnchorX, y: targetAnchorY)
                    
                    // ==========================================
                    // 3. 手机 60Hz 动态空间陀螺准星 (Live Reticle)
                    // ==========================================
                    let liveX = engine.liveCrosshair.x * w
                    let liveY = engine.liveCrosshair.y * h
                    
                    ZStack {
                        // 动态准星光点
                        Circle()
                            .fill(isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: isLocked ? Color.green : Color.white, radius: 4)
                        
                        // 未对准时虚线引导准星朝目标环靠拢
                        if !isLocked {
                            Path { path in
                                path.move(to: CGPoint(x: liveX, y: liveY))
                                path.addLine(to: CGPoint(x: targetAnchorX, y: targetAnchorY))
                            }
                            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))
                        }
                    }
                    .position(x: liveX, y: liveY)
                    .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: engine.liveCrosshair)
                    
                    // ==========================================
                    // 4. 实时指挥动态微胶囊 (对标三星/谷歌实拍指挥浮层)
                    // ==========================================
                    VStack(spacing: 8) {
                        let tipText = engine.currentTip.isEmpty ? (guidance?.coachTip ?? "正在智能分析构图...") : engine.currentTip
                        
                        HStack(spacing: 8) {
                            if isLocked {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.45))
                            } else {
                                // 吻合对准度指示环
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                        .frame(width: 16, height: 16)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(engine.alignmentProgress))
                                        .stroke(Color.yellow, lineWidth: 2)
                                        .frame(width: 16, height: 16)
                                        .rotationEffect(.degrees(-90))
                                }
                            }
                            
                            Text(tipText)
                                .font(.system(size: 13, weight: isLocked ? .bold : .medium))
                                .foregroundColor(isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : .white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(BlurView(style: .systemUltraThinMaterialDark))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45).opacity(0.8) : Color.yellow.opacity(0.6),
                                lineWidth: isLocked ? 1.5 : 1
                            )
                        )
                        .shadow(color: isLocked ? Color.green.opacity(0.4) : Color.black.opacity(0.4), radius: 8, x: 0, y: 3)
                    }
                    .position(x: w / 2.0, y: h * 0.16)
                    .animation(.easeInOut(duration: 0.25), value: isLocked)
                }
                .onAppear {
                    pulseScale = 1.05
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 四角摄影标尺形状
private struct CornerBrackets: Shape {
    let width: CGFloat
    let height: CGFloat
    let isLocked: Bool
    let bracketLen: CGFloat = 18.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let halfW = width / 2.0
        let halfH = height / 2.0
        let cX = rect.midX
        let cY = rect.midY
        
        let left = cX - halfW
        let right = cX + halfW
        let top = cY - halfH
        let bottom = cY + halfH
        
        // 左上角
        path.move(to: CGPoint(x: left, y: top + bracketLen))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left + bracketLen, y: top))
        
        // 右上角
        path.move(to: CGPoint(x: right - bracketLen, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: top + bracketLen))
        
        // 左下角
        path.move(to: CGPoint(x: left, y: bottom - bracketLen))
        path.addLine(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left + bracketLen, y: bottom))
        
        // 右下角
        path.move(to: CGPoint(x: right - bracketLen, y: bottom))
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: bottom - bracketLen))
        
        return path
    }
}

// MARK: - iOS 磨砂玻璃视觉封装
private struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
