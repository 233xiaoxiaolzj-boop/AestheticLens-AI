import SwiftUI
import MetalKit

/// SwiftUI 与 Metal MTKView 的桥接容器
public struct MetalView: UIViewRepresentable {
    @ObservedObject var cameraManager = CameraManager.shared
    var activePreset: String = "自然原画"
    
    public init(activePreset: String = "自然原画") {
        self.activePreset = activePreset
    }
    
    public class Coordinator {
        let renderer: MetalRenderer
        init() {
            self.renderer = MetalRenderer()
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        let renderer = context.coordinator.renderer
        mtkView.device = renderer.device
        mtkView.delegate = renderer
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 60 // 锁定 60fps 满帧
        
        // 绑定相机帧输出至渲染器
        cameraManager.onFrameCaptured = { [weak renderer] sampleBuffer in
            renderer?.updateFrame(sampleBuffer)
        }
        
        renderer.applyPreset(activePreset)
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer.applyPreset(activePreset)
    }
}
