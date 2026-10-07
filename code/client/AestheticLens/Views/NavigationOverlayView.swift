import SwiftUI

/// 空间机位 4D 实时 AR 构图对齐 HUD (对标 Doka 相机实拍构图减法与黄金取景框)
/// 未点击 AI 实时构图指挥时 100% 纯净隐身，点击开启后唤出 AR 空间框线、推荐焦段与实时指令
public struct NavigationOverlayView: View {
    public let guidance: CompositionGuidance?
    @ObservedObject private var engine = RealtimeCompositionEngine.shared
    @ObservedObject private var motionManager = MotionManager.shared
    
    // 对准时呼吸特效
    @State private var pulseScale: CGFloat = 1.0
    
    public init(guidance: CompositionGuidance? = nil) {
        self.guidance = guidance
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            
            let isRealtimeActive = (engine.state != .inactive)
            
            if isRealtimeActive {
                let crop = engine.targetCropBox
                let isLocked = engine.isAligned
                
                let boxW = max((crop.xmax - crop.xmin) * w, 80)
                let boxH = max((crop.ymax - crop.ymin) * h, 80)
                let boxCenterX = (crop.xmin + crop.xmax) / 2.0 * w
                let boxCenterY = (crop.ymin + crop.ymax) / 2.0 * h
                
                ZStack {
                    // ==========================================
                    // 1. AR 黄金电影取景框 (Cinema Frame)
                    // ==========================================
                    ZStack {
                        // 锁定状态外发光光晕
                        if isLocked {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    Color(red: 0.0, green: 0.95, blue: 0.45).opacity(0.4),
                                    lineWidth: 6
                                )
                                .blur(radius: 5)
                                .frame(width: boxW, height: boxH)
                                .scaleEffect(pulseScale)
                                .onAppear {
                                    withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                        pulseScale = 1.04
                                    }
                                }
                        }
                        
                        // 黄金局部裁剪框 (未锁定时金色呼吸框，锁定时翠绿实线)
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.85),
                                style: StrokeStyle(
                                    lineWidth: isLocked ? 2.5 : 1.5,
                                    dash: isLocked ? [] : [6, 4]
                                )
                            )
                            .frame(width: boxW, height: boxH)
                        
                        // 四角电影级 L 型标尺
                        CornerBrackets(width: boxW, height: boxH, isLocked: isLocked)
                            .stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color.white.opacity(0.9),
                                lineWidth: 2.5
                            )
                        
                        // 推荐焦段与场景识别胶囊 (挂在框上方)
                        VStack {
                            HStack(spacing: 6) {
                                Text(engine.sceneTypeZh)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color(red: 1.0, green: 0.85, blue: 0.35))
                                    .cornerRadius(4)
                                
                                Text(String(format: "推荐 %.1f×", engine.recommendedZoom))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                if engine.isCloudAI {
                                    Text("云端大模型")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(Color(white: 0.8))
                                } else {
                                    Text("视觉神经引擎")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(Color(white: 0.8))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                            .offset(y: -boxH / 2.0 - 22)
                            
                            Spacer()
                        }
                        .frame(width: boxW, height: boxH)
                    }
                    .position(x: boxCenterX, y: boxCenterY)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isLocked)
                    
                    // ==========================================
                    // 2. 空间构图目标圆心 (Target Anchor)
                    // ==========================================
                    let targetAnchorX = engine.targetCenter.x * w
                    let targetAnchorY = engine.targetCenter.y * h
                    
                    ZStack {
                        Circle()
                            .stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45).opacity(0.8) : Color.yellow.opacity(0.4),
                                lineWidth: 1.5
                            )
                            .frame(width: 30, height: 30)
                        
                        Circle()
                            .stroke(
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color.yellow.opacity(0.8),
                                lineWidth: 2.0
                            )
                            .frame(width: 12, height: 12)
                    }
                    .position(x: targetAnchorX, y: targetAnchorY)
                    
                    // ==========================================
                    // 3. 动态平滑滤波空间准星 (Live Reticle)
                    // ==========================================
                    let liveX = engine.liveCrosshair.x * w
                    let liveY = engine.liveCrosshair.y * h
                    
                    ZStack {
                        Circle()
                            .fill(isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45) : Color.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: isLocked ? Color.green : Color.white, radius: 4)
                        
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
                    // 4. 实时指挥提示微胶囊
                    // ==========================================
                    VStack(spacing: 8) {
                        let tipText = engine.currentTip.isEmpty ? (guidance?.coachTip ?? "AI 正在全景分析...") : engine.currentTip
                        
                        HStack(spacing: 8) {
                            if isLocked {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.45))
                            } else {
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
                                isLocked ? Color(red: 0.0, green: 0.95, blue: 0.45).opacity(0.8) : Color.white.opacity(0.25),
                                lineWidth: 1.2
                            )
                        )
                        .shadow(color: isLocked ? Color.green.opacity(0.3) : Color.black.opacity(0.4), radius: 8)
                        
                        if !isLocked && engine.currentDirection != .perfect {
                            Text(engine.currentDirection.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(12)
                        }
                    }
                    .position(x: w / 2.0, y: min(boxCenterY + boxH / 2.0 + 36, h - 45))
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: engine.currentDirection)
                }
            }
        }
    }
}

/// 摄影专业四角取景锚点 (L型 Corner Brackets)
struct CornerBrackets: Shape {
    let width: CGFloat
    let height: CGFloat
    let isLocked: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let len: CGFloat = 16.0
        let left: CGFloat = (rect.width - width) / 2.0
        let top: CGFloat = (rect.height - height) / 2.0
        let right: CGFloat = left + width
        let bottom: CGFloat = top + height
        
        // 左上角
        path.move(to: CGPoint(x: left, y: top + len))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left + len, y: top))
        
        // 右上角
        path.move(to: CGPoint(x: right - len, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: top + len))
        
        // 左下角
        path.move(to: CGPoint(x: left, y: bottom - len))
        path.addLine(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left + len, y: bottom))
        
        // 右下角
        path.move(to: CGPoint(x: right - len, y: bottom))
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: bottom - len))
        
        return path
    }
}

/// 毛玻璃辅助视图
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}
