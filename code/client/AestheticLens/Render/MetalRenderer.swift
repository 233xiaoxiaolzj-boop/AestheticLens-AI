import Foundation
import Metal
import MetalKit
import CoreMedia
import CoreVideo

/// Metal 零拷贝片元渲染器 (目标 60fps 稳定输出，零显存泄漏)
public final class MetalRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    
    // 渲染管线与状态
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var currentTexture: MTLTexture?
    private var lutTexture: MTLTexture?
    
    // 实时滤镜强度 (0.0 ~ 1.0)
    public var lutIntensity: Float = 0.85
    
    public override init() {
        guard let defaultDevice = MTLCreateSystemDefaultDevice(),
              let queue = defaultDevice.makeCommandQueue() else {
            fatalError("[MetalRenderer] 当前设备不支持 Metal")
        }
        self.device = defaultDevice
        self.commandQueue = queue
        super.init()
        
        setupTextureCache()
        setupPipeline()
    }
    
    private func setupTextureCache() {
        #if !targetEnvironment(simulator)
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        #endif
    }
    
    private func setupPipeline() {
        guard let defaultLibrary = device.makeDefaultLibrary(),
              let vertexFunc = defaultLibrary.makeFunction(name: "passThroughVertex"),
              let fragmentFunc = defaultLibrary.makeFunction(name: "lutFragmentShader") else {
            print("[MetalRenderer] 默认 Shader 库未找到或尚未编译，进入 PassThrough 纯透模式")
            return
        }
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("[MetalRenderer] 渲染管线创建失败: \(error)")
        }
    }
    
    /// 加载 512x512 3D LUT PNG 纹理
    public func loadLUT(from url: URL) {
        let loader = MTKTextureLoader(device: device)
        do {
            let options: [MTKTextureLoader.Option: Any] = [
                .SRGB: false,
                .generateMipmaps: false
            ]
            self.lutTexture = try loader.newTexture(URL: url, options: options)
            print("[MetalRenderer] 成功加载 LUT 纹理: \(url.lastPathComponent)")
        } catch {
            print("[MetalRenderer] 加载 LUT 纹理失败: \(error)")
        }
    }
    
    /// 从 AVCaptureSession 的 CMSampleBuffer 提取纹理 (零拷贝)
    public func updateFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let textureCache = self.textureCache else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        if status == kCVReturnSuccess, let cvTex = cvTexture {
            self.currentTexture = CVMetalTextureGetTexture(cvTex)
        }
    }
    
    // MARK: - MTKViewDelegate
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        guard let pipeline = pipelineState,
              let camTexture = currentTexture,
              let lutTex = lutTexture else {
            // 无滤镜或管线未就绪时的兜底清屏
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        
        // 绑定 Shader 与片元着色器输入纹理
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(camTexture, index: 0)
            encoder.setFragmentTexture(lutTex, index: 1)
            var intensity = self.lutIntensity
            encoder.setFragmentBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)
            
            // 绘制全屏两个三角形覆盖画幅
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
