import SwiftUI
import MetalKit

/// SwiftUI 与 Metal MTKView 的高性能高刷取景桥接器
public struct MetalView: UIViewRepresentable {
    @ObservedObject var cameraManager = CameraManager.shared
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
        
        // 满血高刷生态：自适应屏幕最高刷新率 (在 iPhone Pro 120Hz ProMotion 设备上打满 120fps)
        let maxFps = UIScreen.main.maximumFramesPerSecond
        mtkView.preferredFramesPerSecond = maxFps > 0 ? maxFps : 60
        
        // 挂载帧渲染监听
        cameraManager.onFrameCaptured = { sampleBuffer in
            MetalRenderer.shared.updateFrame(sampleBuffer)
        }
        
        renderer.applyPreset(activePreset)
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        MetalRenderer.shared.applyPreset(activePreset)
    }
}
