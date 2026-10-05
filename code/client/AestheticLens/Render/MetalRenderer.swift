import Foundation
import Metal
import MetalKit
import CoreMedia
import CoreVideo
import UIKit

/// Metal 高性能胶片滤镜渲染引擎 (全面支持 120fps 取景与 60fps 录制直出)
public final class MetalRenderer: NSObject, MTKViewDelegate {
    public static let shared = MetalRenderer()
    
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    
    // 渲染管线状态
    private var pipelineState: MTLRenderPipelineState?
    private var passThroughPipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var currentTexture: MTLTexture?
    private var lutTexture: MTLTexture?
    
    // 实时滤镜强度 (0.0 ~ 1.0)
    public var lutIntensity: Float = 0.90
    public private(set) var currentPresetName: String = "00-自然原画"
    
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
              let vertexFunc = defaultLibrary.makeFunction(name: "passThroughVertex") else {
            print("[MetalRenderer] 默认 Shader 库未找到或未编译")
            return
        }
        
        // 1. 直通原画管线 (PassThrough)
        if let passFragmentFunc = defaultLibrary.makeFunction(name: "passThroughFragmentShader") {
            let passDesc = MTLRenderPipelineDescriptor()
            passDesc.vertexFunction = vertexFunc
            passDesc.fragmentFunction = passFragmentFunc
            passDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                self.passThroughPipelineState = try device.makeRenderPipelineState(descriptor: passDesc)
            } catch {
                print("[MetalRenderer] 直通管线创建失败: \(error)")
            }
        }
        
        // 2. 3D LUT 胶片滤镜管线
        if let lutFragmentFunc = defaultLibrary.makeFunction(name: "lutFragmentShader") {
            let lutDesc = MTLRenderPipelineDescriptor()
            lutDesc.vertexFunction = vertexFunc
            lutDesc.fragmentFunction = lutFragmentFunc
            lutDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                self.pipelineState = try device.makeRenderPipelineState(descriptor: lutDesc)
            } catch {
                print("[MetalRenderer] 3D LUT 管线创建失败: \(error)")
            }
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
    
    /// 切换预设滤镜 (支持标准胶片编号与中文名)
    public func applyPreset(_ presetName: String) {
        self.currentPresetName = presetName
        let cleanName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanName == "00-自然原画" || cleanName == "自然原画" || cleanName.contains("原画") || cleanName.contains("自然") || cleanName.lowercased() == "raw" || cleanName.lowercased() == "natural" {
            self.lutTexture = nil
            return
        }
        
        let fileName: String
        if cleanName.contains("暖金") || cleanName.contains("01") {
            fileName = "lut_film_warm_01"
            self.lutIntensity = 0.90
        } else if cleanName.contains("富士") || cleanName.contains("冷萃") || cleanName.contains("02") {
            fileName = "lut_clean_bright_02"
            self.lutIntensity = 0.88
        } else if cleanName.contains("青橙") || cleanName.contains("赛博") || cleanName.contains("03") {
            fileName = "lut_cyber_teal_orange_03"
            self.lutIntensity = 0.92
        } else if cleanName.contains("质感") || cleanName.contains("04") {
            fileName = "lut_film_warm_01"
            self.lutIntensity = 0.82
        } else if cleanName.contains("日落") || cleanName.contains("海边") || cleanName.contains("05") {
            fileName = "lut_film_warm_01"
            self.lutIntensity = 0.95
        } else if cleanName.contains("黑白") || cleanName.contains("徕卡") || cleanName.contains("06") {
            fileName = "lut_mono_contrast_04"
            self.lutIntensity = 1.0
        } else {
            fileName = "lut_film_warm_01"
            self.lutIntensity = 0.88
        }
        
        if let url = Bundle.main.url(forResource: fileName, withExtension: "png") {
            loadLUT(from: url)
        }
    }
    
    /// 从摄像头采集流 CMSampleBuffer 提取实时纹理
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
    
    /// 高性能离屏渲染：将当前输入帧经 3D LUT 上色后渲染到目标 CVPixelBuffer (用于 60fps 视频录制直出)
    public func renderFilteredPixelBuffer(input: CVPixelBuffer, output: CVPixelBuffer) -> Bool {
        guard let textureCache = self.textureCache else { return false }
        
        let inWidth = CVPixelBufferGetWidth(input)
        let inHeight = CVPixelBufferGetHeight(input)
        let outWidth = CVPixelBufferGetWidth(output)
        let outHeight = CVPixelBufferGetHeight(output)
        
        var inCvTex: CVMetalTexture?
        var outCvTex: CVMetalTexture?
        
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, input, nil, .bgra8Unorm, inWidth, inHeight, 0, &inCvTex) == kCVReturnSuccess,
              let inTex = inCvTex.flatMap({ CVMetalTextureGetTexture($0) }) else {
            return false
        }
        
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, output, nil, .bgra8Unorm, outWidth, outHeight, 0, &outCvTex) == kCVReturnSuccess,
              let outTex = outCvTex.flatMap({ CVMetalTextureGetTexture($0) }) else {
            return false
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        
        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = outTex
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDesc.colorAttachments[0].storeAction = .store
        
        if let lutTex = self.lutTexture, let pipeline = self.pipelineState {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(inTex, index: 0)
                encoder.setFragmentTexture(lutTex, index: 1)
                var intensity = self.lutIntensity
                encoder.setFragmentBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        } else if let passThrough = self.passThroughPipelineState {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.setRenderPipelineState(passThrough)
                encoder.setFragmentTexture(inTex, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return true
    }
    
    // MARK: - MTKViewDelegate (取景器 120fps / 60fps 实时渲染)
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        guard let camTexture = currentTexture else {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        
        // 渲染分支：有 LUT 则执行 3D LUT 片元着色，无则直通原画
        if let lutTex = lutTexture, let pipeline = pipelineState {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(camTexture, index: 0)
                encoder.setFragmentTexture(lutTex, index: 1)
                var intensity = self.lutIntensity
                encoder.setFragmentBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        } else if let passThrough = passThroughPipelineState {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.setRenderPipelineState(passThrough)
                encoder.setFragmentTexture(camTexture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
