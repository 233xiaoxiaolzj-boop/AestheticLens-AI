import SwiftUI
import MetalKit

/// SwiftUI 与 Metal MTKView 的桥接容器
public struct MetalView: UIViewRepresentable {
    @ObservedObject var cameraManager = CameraManager.shared
    private let renderer = MetalRenderer()
    
    public init() {}
    
    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.device
        mtkView.delegate = renderer
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 60 // 锁定 60fps 满帧
        
        // 绑定相机帧输出至渲染器
        cameraManager.onFrameCaptured = { sampleBuffer in
            renderer.updateFrame(sampleBuffer)
        }
        
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {}
}
