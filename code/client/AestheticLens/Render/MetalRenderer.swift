import Foundation
import Metal
import MetalKit
import CoreMedia
import CoreVideo
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import UIKit
import simd

/// 与 Shaders.metal 对齐的顶点裁剪缩放矩阵参数 (Aspect Fill 居中无畸变裁剪)
public struct VertexUniforms {
    public var uvScale: SIMD2<Float>
    public var uvOffset: SIMD2<Float>
    
    public init(uvScale: SIMD2<Float> = SIMD2<Float>(1.0, 1.0), uvOffset: SIMD2<Float> = SIMD2<Float>(0.0, 0.0)) {
        self.uvScale = uvScale
        self.uvOffset = uvOffset
    }
}

/// Metal 高性能胶片滤镜渲染引擎 (与传感器帧率 1:1 同步、Aspect Fill 比例保真、广色域与 EXIF 保留)
public final class MetalRenderer: NSObject, MTKViewDelegate {
    public static let shared = MetalRenderer()
    
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    
    // 渲染管线状态
    private var pipelineState: MTLRenderPipelineState?
    private var passThroughPipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    
    // 线程安全状态锁 (隔离相机采集线程与主线程渲染访问)
    private let stateLock = NSLock()
    private var currentTexture: MTLTexture?
    private var currentTextureSize: CGSize = .zero
    private var lutTexture: MTLTexture?
    
    // 当前关联的取景器视图 (用于按需帧同步刷新，消除空转功耗与发热降频)
    public weak var activeMTKView: MTKView?
    
    // 复用共享 CIContext (避免重复创建 Metal 上下文导致卡顿和内存飙升)
    private lazy var ciContext: CIContext = {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        return CIContext(mtlDevice: device, options: [
            .workingColorSpace: p3,
            .cacheIntermediates: false
        ])
    }()
    
    // 拍照滤镜后台串行处理队列 (绝不阻塞主线程)
    private let photoProcessingQueue = DispatchQueue(label: "ai.aestheticlens.photoFilterQueue", qos: .userInitiated)
    
    // 实时滤镜强度 (0.0 ~ 1.0)
    public var lutIntensity: Float = 0.90
    public private(set) var currentPresetName: String = "00-自然原画"
    
    // 最新一帧取景实际 Aspect Fill 参数 (供触控对焦坐标反算使用)
    public private(set) var latestPreviewUniforms = VertexUniforms()
    
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
    
    /// 计算 Aspect Fill 居中裁剪所需的 UV 缩放与偏移 (保证源图在任意比例视口下 1:1 等比无拉伸)
    public func computeAspectFillUniforms(sourceWidth: Int, sourceHeight: Int, targetWidth: Int, targetHeight: Int) -> VertexUniforms {
        guard sourceWidth > 0, sourceHeight > 0, targetWidth > 0, targetHeight > 0 else {
            return VertexUniforms()
        }
        let srcAspect = Float(sourceWidth) / Float(sourceHeight)
        let dstAspect = Float(targetWidth) / Float(targetHeight)
        
        var scaleX: Float = 1.0
        var scaleY: Float = 1.0
        
        if srcAspect > dstAspect {
            // 源图偏宽 (例如 4:3 塞入 9:16 竖屏)：高度铺满，水平居中裁掉多余两侧
            scaleX = dstAspect / srcAspect
        } else if srcAspect < dstAspect {
            // 源图偏窄 (例如 3:4 塞入 16:9 横幅或 1:1)：宽度铺满，垂直居中裁掉上下
            scaleY = srcAspect / dstAspect
        }
        
        let offsetX = (1.0 - scaleX) * 0.5
        let offsetY = (1.0 - scaleY) * 0.5
        return VertexUniforms(uvScale: SIMD2<Float>(scaleX, scaleY), uvOffset: SIMD2<Float>(offsetX, offsetY))
    }
    
    /// 加载 512x512 3D LUT PNG 纹理
    public func loadLUT(from url: URL) {
        let loader = MTKTextureLoader(device: device)
        do {
            let options: [MTKTextureLoader.Option: Any] = [
                .SRGB: false,
                .generateMipmaps: false
            ]
            let tex = try loader.newTexture(URL: url, options: options)
            stateLock.lock()
            self.lutTexture = tex
            stateLock.unlock()
            print("[MetalRenderer] 成功加载 LUT 纹理: \(url.lastPathComponent)")
        } catch {
            print("[MetalRenderer] 加载 LUT 纹理失败: \(error)")
        }
    }
    
    /// 切换预设滤镜 (支持标准胶片编号与中文名)
    public func applyPreset(_ presetName: String) {
        let cleanName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        stateLock.lock()
        if self.currentPresetName == cleanName && (cleanName.contains("原画") || self.lutTexture != nil) {
            stateLock.unlock()
            return
        }
        self.currentPresetName = cleanName
        
        if cleanName == "00-自然原画" || cleanName == "自然原画" || cleanName.contains("原画") || cleanName.contains("自然") || cleanName.lowercased() == "raw" || cleanName.lowercased() == "natural" {
            self.lutTexture = nil
            stateLock.unlock()
            DispatchQueue.main.async { self.activeMTKView?.setNeedsDisplay() }
            return
        }
        stateLock.unlock()
        
        let fileName: String
        let targetIntensity: Float
        if cleanName.contains("暖金") || cleanName.contains("01") {
            fileName = "lut_film_warm_01"
            targetIntensity = 0.90
        } else if cleanName.contains("富士") || cleanName.contains("冷萃") || cleanName.contains("02") {
            fileName = "lut_clean_bright_02"
            targetIntensity = 0.88
        } else if cleanName.contains("青橙") || cleanName.contains("赛博") || cleanName.contains("03") {
            fileName = "lut_cyber_teal_orange_03"
            targetIntensity = 0.92
        } else if cleanName.contains("质感") || cleanName.contains("04") {
            fileName = "lut_film_warm_01"
            targetIntensity = 0.82
        } else if cleanName.contains("日落") || cleanName.contains("海边") || cleanName.contains("05") {
            fileName = "lut_film_warm_01"
            targetIntensity = 0.95
        } else if cleanName.contains("黑白") || cleanName.contains("徕卡") || cleanName.contains("06") {
            fileName = "lut_mono_contrast_04"
            targetIntensity = 1.0
        } else {
            fileName = "lut_film_warm_01"
            targetIntensity = 0.88
        }
        
        stateLock.lock()
        self.lutIntensity = targetIntensity
        stateLock.unlock()
        
        if let url = Bundle.main.url(forResource: fileName, withExtension: "png") {
            loadLUT(from: url)
            DispatchQueue.main.async { self.activeMTKView?.setNeedsDisplay() }
        }
    }
    
    /// 从摄像头采集流 CMSampleBuffer 提取实时纹理并按需同步刷新取景器
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
        
        if status == kCVReturnSuccess, let cvTex = cvTexture, let metalTex = CVMetalTextureGetTexture(cvTex) {
            stateLock.lock()
            self.currentTexture = metalTex
            self.currentTextureSize = CGSize(width: width, height: height)
            stateLock.unlock()
            
            DispatchQueue.main.async { [weak self] in
                self?.activeMTKView?.setNeedsDisplay()
            }
        }
    }
    
    /// 高性能离屏渲染：将当前输入帧经 3D LUT 上色并等比 Aspect Fill 裁剪后渲染到目标 CVPixelBuffer (供录像写入队列调用)
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
        
        var uniforms = computeAspectFillUniforms(sourceWidth: inWidth, sourceHeight: inHeight, targetWidth: outWidth, targetHeight: outHeight)
        
        stateLock.lock()
        let activeLut = self.lutTexture
        let activeIntensity = self.lutIntensity
        stateLock.unlock()
        
        if let lutTex = activeLut, let pipeline = self.pipelineState {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 0)
                encoder.setFragmentTexture(inTex, index: 0)
                encoder.setFragmentTexture(lutTex, index: 1)
                var intensity = activeIntensity
                encoder.setFragmentBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        } else if let passThrough = self.passThroughPipelineState {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.setRenderPipelineState(passThrough)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 0)
                encoder.setFragmentTexture(inTex, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        } else {
            return false
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return true
    }
    // MARK: - MTKViewDelegate (与相机传感器帧率 1:1 同步渲染)
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        stateLock.lock()
        let camTexture = self.currentTexture
        let activeLut = self.lutTexture
        let activeIntensity = self.lutIntensity
        stateLock.unlock()
        
        guard let tex = camTexture else {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        
        let targetW = Int(view.drawableSize.width)
        let targetH = Int(view.drawableSize.height)
        var uniforms = computeAspectFillUniforms(sourceWidth: tex.width, sourceHeight: tex.height, targetWidth: targetW, targetHeight: targetH)
        self.latestPreviewUniforms = uniforms
        
        if let lutTex = activeLut, let pipeline = pipelineState {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 0)
                encoder.setFragmentTexture(tex, index: 0)
                encoder.setFragmentTexture(lutTex, index: 1)
                var intensity = activeIntensity
                encoder.setFragmentBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        } else if let passThrough = passThroughPipelineState {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                encoder.setRenderPipelineState(passThrough)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 0)
                encoder.setFragmentTexture(tex, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - 拍照成片异步无损处理 (00-原画直接透传原始文件数据，开启滤镜/裁剪时保留广色域与完整 EXIF)
    /// - Parameters:
    ///   - rawData: AVCapturePhoto.fileDataRepresentation() 原始二进制数据
    ///   - applyFilter: 是否启用了非原画 LUT 滤镜
    ///   - displayAspectRatio: 当前取景画幅目标宽高比 (例如 3/4, 9/16, 1/1，为 nil 则保留原始 sensor 比例)
    ///   - completion: (用于写入相册的最终照片二进制数据, 用于 App 内预览的轻量高清图)
    public func processCapturedPhotoData(
        _ rawData: Data,
        applyFilter: Bool,
        displayAspectRatio: CGFloat? = nil,
        completion: @escaping (Data?, UIImage?) -> Void
    ) {
        photoProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 生成轻量级预览图 (最大边 1440px，极低内存占用且包含正确方向)
            let previewThumbnail = self.makeOrientedThumbnail(from: rawData, maxPixelSize: 1440)
            
            // 2. 检查是否需要裁剪比例
            guard let source = CGImageSourceCreateWithData(rawData as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                DispatchQueue.main.async { completion(rawData, previewThumbnail) }
                return
            }
            
            let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
            let exifOrientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
            let isRotated90Or270 = [5, 6, 7, 8].contains(exifOrientation)
            
            let rawW = cgImage.width
            let rawH = cgImage.height
            let displayW = isRotated90Or270 ? rawH : rawW
            let displayH = isRotated90Or270 ? rawW : rawH
            
            // 判断目标画幅比例是否与原图不同 (容差 0.02 以避免浮点误差导致不必要的重编码)
            var needsAspectCrop = false
            var targetRawW = rawW
            var targetRawH = rawH
            
            if let targetDisplayAspect = displayAspectRatio, targetDisplayAspect > 0, displayW > 0, displayH > 0 {
                let currentDisplayAspect = CGFloat(displayW) / CGFloat(displayH)
                if abs(currentDisplayAspect - targetDisplayAspect) > 0.02 {
                    needsAspectCrop = true
                    // 将屏幕显示比例映射回传感器未旋转像素坐标比例
                    let targetRawAspect = isRotated90Or270 ? (1.0 / targetDisplayAspect) : targetDisplayAspect
                    let currentRawAspect = CGFloat(rawW) / CGFloat(rawH)
                    if currentRawAspect > targetRawAspect {
                        targetRawH = rawH
                        targetRawW = max(1, Int((CGFloat(rawH) * targetRawAspect).rounded()))
                    } else {
                        targetRawW = rawW
                        targetRawH = max(1, Int((CGFloat(rawW) / targetRawAspect).rounded()))
                    }
                }
            }
            
            stateLock.lock()
            let activeLut = applyFilter ? self.lutTexture : nil
            let activeIntensity = self.lutIntensity
            stateLock.unlock()
            
            // 3. 原画直通分支：未开启滤镜且无需裁切画幅 -> 100% 原封不动透传原生拍照 Data (零重压缩、零丢 EXIF/HDR)
            if activeLut == nil && !needsAspectCrop {
                DispatchQueue.main.async {
                    completion(rawData, previewThumbnail)
                }
                return
            }
            
            // 4. 需要 GPU 3D LUT 上色或等比画幅裁切：使用 IOSurface CVPixelBuffer 零内存风暴输出，保留 P3 广色域与完整 EXIF
            let processedData = self.renderCGImageWithMetal(
                cgImage: cgImage,
                properties: properties,
                targetRawWidth: targetRawW,
                targetRawHeight: targetRawH,
                lutTexture: activeLut,
                lutIntensity: activeIntensity
            )
            
            let finalData = processedData ?? rawData
            let finalPreview = processedData.flatMap { self.makeOrientedThumbnail(from: $0, maxPixelSize: 1440) } ?? previewThumbnail
            
            DispatchQueue.main.async {
                completion(finalData, finalPreview)
            }
        }
    }
    
    private func renderCGImageWithMetal(
        cgImage: CGImage,
        properties: [CFString: Any],
        targetRawWidth: Int,
        targetRawHeight: Int,
        lutTexture: MTLTexture?,
        lutIntensity: Float
    ) -> Data? {
        guard let textureCache = self.textureCache,
              targetRawWidth > 0, targetRawHeight > 0 else { return nil }
        
        // 确保尺寸在 Metal 纹理上限内
        let maxTexSide = 16384
        let rawW = cgImage.width
        let rawH = cgImage.height
        guard rawW <= maxTexSide, rawH <= maxTexSide else { return nil }
        
        let loader = MTKTextureLoader(device: self.device)
        let loaderOptions: [MTKTextureLoader.Option: Any] = [
            .origin: MTKTextureLoader.Origin.topLeft,
            .SRGB: false
        ]
        
        guard let inTexture = try? loader.newTexture(cgImage: cgImage, options: loaderOptions) else {
            return nil
        }
        
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var outPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetRawWidth,
            targetRawHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &outPixelBuffer
        )
        guard status == kCVReturnSuccess, let outBuffer = outPixelBuffer else { return nil }
        
        var outCvTex: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            outBuffer,
            nil,
            .bgra8Unorm,
            targetRawWidth,
            targetRawHeight,
            0,
            &outCvTex
        ) == kCVReturnSuccess,
              let outTex = outCvTex.flatMap({ CVMetalTextureGetTexture($0) }) else {
            return nil
        }
        
        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else { return nil }
        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = outTex
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDesc.colorAttachments[0].storeAction = .store
        
        var uniforms = computeAspectFillUniforms(sourceWidth: rawW, sourceHeight: rawH, targetWidth: targetRawWidth, targetHeight: targetRawHeight)
        
        if let lutTex = lutTexture, let pipeline = self.pipelineState {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return nil }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 0)
            encoder.setFragmentTexture(inTexture, index: 0)
            encoder.setFragmentTexture(lutTex, index: 1)
            var intensity = lutIntensity
            encoder.setFragmentBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        } else if let passThrough = self.passThroughPipelineState {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return nil }
            encoder.setRenderPipelineState(passThrough)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 0)
            encoder.setFragmentTexture(inTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        } else {
            return nil
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let p3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let colorSpace: CGColorSpace = {
            if let srcSpace = cgImage.colorSpace, srcSpace.model == .rgb {
                return srcSpace
            }
            return p3
        }()
        let ciImage = CIImage(cvPixelBuffer: outBuffer, options: [.colorSpace: colorSpace])
        guard let resultCGImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent, format: .BGRA8, colorSpace: colorSpace) else {
            return nil
        }
        
        // 优先输出高画质 HEIC (保留原始 EXIF / Orientation / 色彩空间)，不支持则回退高码率 JPEG
        let mutableData = NSMutableData()
        let targetUTI = UTType.heic.identifier as CFString
        let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, targetUTI, 1, nil)
            ?? CGImageDestinationCreateWithData(mutableData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        guard let imageDestination = dest else { return nil }
        
        var outProperties = properties
        outProperties[kCGImageDestinationLossyCompressionQuality] = 0.95
        // 更新裁切后的像素宽高元数据，避免 EXIF PixelXDimension/YDimension 与实际不符
        outProperties[kCGImagePropertyPixelWidth] = targetRawWidth
        outProperties[kCGImagePropertyPixelHeight] = targetRawHeight
        
        CGImageDestinationAddImage(imageDestination, resultCGImage, outProperties as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else { return nil }
        return mutableData as Data
    }
    
    /// 快速生成带正确方向的轻量缩略图 (避免把 48MP 原图塞进 UI 占用几十 MB 内存)
    public func makeOrientedThumbnail(from imageData: Data, maxPixelSize: Int = 1440) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return UIImage(data: imageData)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cgThumb)
        }
        return UIImage(data: imageData)
    }

    // MARK: - 向后兼容静态图单张滤镜方法 (基于共享 CIContext + IOSurface 避免大数组内存暴涨)
    public func applyFilterToImage(_ input: UIImage) -> UIImage {
        stateLock.lock()
        let activeLut = self.lutTexture
        let activeIntensity = self.lutIntensity
        stateLock.unlock()
        
        guard let lutTex = activeLut, let cgImage = input.cgImage else {
            return input
        }
        guard let data = renderCGImageWithMetal(
            cgImage: cgImage,
            properties: [:],
            targetRawWidth: cgImage.width,
            targetRawHeight: cgImage.height,
            lutTexture: lutTex,
            lutIntensity: activeIntensity
        ), let outImg = UIImage(data: data) else {
            return input
        }
        return UIImage(cgImage: outImg.cgImage ?? cgImage, scale: input.scale, orientation: input.imageOrientation)
    }
}