import SwiftUI
import MetalKit

/// SwiftUI 与 Metal MTKView 的高性能高刷取景桥接器
/// 采用按需帧同步模式 (isPaused = true + enableSetNeedsDisplay = true)，1:1 跟随相机帧输出刷新，消除 GPU 空转发热与掉帧
public struct MetalView: UIViewRepresentable {
    var activePreset: String = "00-自然原画"
    
    public init(activePreset: String = "00-自然原画") {
        self.activePreset = activePreset
    }
    
    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        let renderer = MetalRenderer.shared
        mtkView.device = renderer.device
        mtkView.delegate = renderer
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.contentMode = .scaleToFill
        mtkView.autoResizeDrawable = true
        
        // 与相机输入帧同步绘制，禁止无新帧空转浪费 GPU 算力
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        
        renderer.activeMTKView = mtkView
        
        // 挂载相机帧回调
        CameraManager.shared.onFrameCaptured = { sampleBuffer in
            MetalRenderer.shared.updateFrame(sampleBuffer)
        }
        
        renderer.applyPreset(activePreset)
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        MetalRenderer.shared.activeMTKView = uiView
        MetalRenderer.shared.applyPreset(activePreset)
    }
}