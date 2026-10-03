import SwiftUI

/// 空间机位 4 向导航箭头与 AR 构图虚线框预览
public struct NavigationOverlayView: View {
    public let guidance: CompositionGuidance?
    
    public init(guidance: CompositionGuidance?) {
        self.guidance = guidance
    }
    
    public var body: some View {
        GeometryReader { proxy in
            if let guidance = guidance {
                let crop = guidance.suggestedCropBox
                let w = proxy.size.width
                let h = proxy.size.height
                
                ZStack {
                    // 1. 金色 AR 推荐构图虚线框 (归一化坐标投影)
                    Rectangle()
                        .stroke(
                            Color.yellow.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .frame(
                            width: (crop.xmax - crop.xmin) * w,
                            height: (crop.ymax - crop.ymin) * h
                        )
                        .position(
                            x: (crop.xmin + crop.xmax) / 2.0 * w,
                            y: (crop.ymin + crop.ymax) / 2.0 * h
                        )
                    
                    // 2. 4 向动态位姿导航胶囊指示器
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.yellow)
                            
                            Text(guidance.coachTip)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(BlurView(style: .systemUltraThinMaterialDark))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.yellow.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .position(x: w / 2.0, y: h * 0.22)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// iOS 磨砂玻璃背景封装
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
