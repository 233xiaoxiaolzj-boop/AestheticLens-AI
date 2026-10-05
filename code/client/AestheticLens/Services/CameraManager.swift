import Foundation
import UIKit
import SwiftUI
import AVFoundation
import CoreMedia
import Combine

/// AVFoundation 工业级专业相机管理引擎
/// 对标苹果原生相机与影视飓风专业架构：
/// - 48MP / 24MP 硬件全像素原生输出 (maxPhotoDimensions)
/// - 苹果原生 Deep Fusion 与 Smart HDR 多帧画质深度优先 (.quality)
/// - Display P3 (.P3_D65) 广色域 ISP 色彩引擎直通
/// - 硬件级连续自动对焦、连续测光、自动白平衡与弱光增强
/// - 原生级轻触屏幕精准对焦与测光联动 (Tap-to-Focus)
/// - 线程安全、防重复点击、防连续快速点击死锁
/// - 硬件平滑无级变焦与 30Hz 软件节流
/// - 前后置全传感器原生 4:3 比例对齐与前置无畸变镜像
/// - 实时轻量视频帧缓存（彻底杜绝后台调用物理拍照引起的快门锁死）
public final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    public static let shared = CameraManager()
    
    // MARK: - Published 响应式状态
    @Published public var isAuthorized: Bool = false
    @Published public var isRunning: Bool = false
    @Published public var currentPosition: AVCaptureDevice.Position = .back
    
    // 变焦状态 (支持 0.5x ~ 15.0x，显示精度 0.1x)
    @Published public var currentZoom: CGFloat = 1.0
    @Published public var minZoom: CGFloat = 0.5
    @Published public var maxZoom: CGFloat = 10.0
    
    // 拍摄互斥锁与状态保护
    @Published public var isCapturingPhoto: Bool = false
    @Published public var isSwitchingCamera: Bool = false
    
    // 真实录像状态
    @Published public var isRecordingVideo: Bool = false
    @Published public var recordingSeconds: Int = 0
    private var recordingTimer: Timer?
    private var videoRecordingCompletion: ((URL?) -> Void)?
    
    // MARK: - 底层硬件捕获组件
    public let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ai.aestheticlens.cameraQueue", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentDeviceInput: AVCaptureDeviceInput?
    private var currentCameraDevice: AVCaptureDevice?
    private var photoCaptureCompletion: ((UIImage?) -> Void)?
    
    // 缓存最新一帧（供 AI 场景感知秒级提取，100% 避免调用硬件快门拍照）
    private let frameBufferLock = NSLock()
    private var latestVideoPixelBuffer: CVPixelBuffer?
    
    // 变焦节流计时器与目标参数
    private var pendingZoomFactor: CGFloat?
    private var lastZoomUpdateTime: TimeInterval = 0
    private let zoomThrottleInterval: TimeInterval = 0.033 // 最高 30Hz 硬件写入，彻底消除硬件锁堆积
    
    // 传递给 Metal 渲染器的 SampleBuffer 回调
    public var onFrameCaptured: ((CMSampleBuffer) -> Void)?
    
    public override init() {
        super.init()
        checkPermissions()
    }
    
    // MARK: - 权限检查
    public func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        }
    }
    
    // MARK: - 初始配置 Pipeline (工业级原生画质全开)
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            // 采用 4:3 最高原生画质 .photo 模式 (完美还原传感器 4:3 黄金视口，杜绝变形与压缩)
            if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .photo
            } else if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            
            // 优选三摄/双摄/广角后置镜头
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: self.currentPosition
            )
            guard let camera = discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                return
            }
            
            self.captureSession.addInput(input)
            self.currentDeviceInput = input
            self.currentCameraDevice = camera
            
            // 硬件镜头属性深度调校 (原生清晰度、宽色域、连续自动聚焦与曝光)
            self.optimizeCameraHardware(camera)
            
            let minFactor = camera.minAvailableVideoZoomFactor
            let maxFactor = min(camera.maxAvailableVideoZoomFactor, 15.0)
            DispatchQueue.main.async {
                self.minZoom = min(minFactor, 1.0)
                self.maxZoom = max(maxFactor, 5.0)
                self.currentZoom = max(1.0, minFactor)
            }
            
            // 配置实时视频输出 (供 Metal 实时滤镜渲染与 AI 实时抽帧)
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            
            // 配置方向与镜像
            self.configureConnection(for: self.videoOutput.connection(with: .video), position: self.currentPosition)
            
            // 配置全像素照片输出 (画质核心升级：全分辨率 + Deep Fusion / Smart HDR 多帧画质优先)
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                
                // 适配 iOS 16+ 4800 万像素 / 2400 万像素硬件全尺寸捕获
                if #available(iOS 16.0, *) {
                    let supportedDims = camera.activeFormat.supportedMaxPhotoDimensions
                    if let highestDim = supportedDims.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                        self.photoOutput.maxPhotoDimensions = highestDim
                    }
                }
            }
            
            // 配置文件录像输出
            if self.captureSession.canAddOutput(self.movieOutput) {
                self.captureSession.addOutput(self.movieOutput)
                self.configureConnection(for: self.movieOutput.connection(with: .video), position: self.currentPosition)
            }
            
            self.captureSession.commitConfiguration()
            
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                }
            }
        }
    }
    
    // MARK: - 硬件镜头原生光学与 ISP 深度优化 (画质对标 iPhone 原生相机)
    private func optimizeCameraHardware(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            
            // 1. 锁定连续自动对焦 (锐利清晰成像基石)
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            // 2. 锁定连续自动曝光 (精准光影阶调)
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            // 3. 锁定连续自动白平衡 (还原真实色彩)
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            // 4. 开启暗光画质增强 (Low Light Boost)
            if camera.isLowLightBoostSupported {
                camera.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            // 5. 广色域 Display P3 硬件直通 (色彩通透艳丽，告别发暗发灰)
            if camera.activeFormat.supportedColorSpaces.contains(.P3_D65) {
                camera.activeColorSpace = .P3_D65
            }
            // 6. 开启自动对焦范围限制与平滑变焦支持
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .none
            }
            
            camera.unlockForConfiguration()
        } catch {
            print("[CameraManager] optimizeCameraHardware 失败: \(error)")
        }
    }
    
    // MARK: - 屏幕轻触对焦与测光 (Tap-to-Focus 对标苹果原生交互)
    public func focusAndExpose(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self = self, let camera = self.currentCameraDevice else { return }
            do {
                try camera.lockForConfiguration()
                
                // 设置聚焦中心点 (0.0 ~ 1.0)
                if camera.isFocusPointOfInterestSupported && camera.isFocusModeSupported(.autoFocus) {
                    camera.focusPointOfInterest = devicePoint
                    camera.focusMode = .autoFocus
                }
                
                // 设置测光中心点 (0.0 ~ 1.0)
                if camera.isExposurePointOfInterestSupported && camera.isExposureModeSupported(.autoExpose) {
                    camera.exposurePointOfInterest = devicePoint
                    camera.exposureMode = .autoExpose
                }
                
                camera.isSubjectAreaChangeMonitoringEnabled = true
                camera.unlockForConfiguration()
            } catch {
                print("[CameraManager] focusAndExpose 失败: \(error)")
            }
        }
    }
    
    // MARK: - 统一连接配置 (修复前置自拍镜像变形与方向)
    private func configureConnection(for connection: AVCaptureConnection?, position: AVCaptureDevice.Position) {
        guard let connection = connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
    }
    
    // MARK: - 硬件平滑变焦 (带 30Hz 智能节流防抖，彻底消除主线程与硬件锁卡顿)
    public func setZoom(factor: CGFloat) {
        let clamped = max(minZoom, min(factor, maxZoom))
        
        DispatchQueue.main.async {
            self.currentZoom = clamped
        }
        
        let now = CACurrentMediaTime()
        if now - lastZoomUpdateTime >= zoomThrottleInterval {
            lastZoomUpdateTime = now
            applyZoomDirectly(clamped)
        } else {
            pendingZoomFactor = clamped
            let delay = zoomThrottleInterval - (now - lastZoomUpdateTime)
            sessionQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, let target = self.pendingZoomFactor else { return }
                self.pendingZoomFactor = nil
                self.lastZoomUpdateTime = CACurrentMediaTime()
                self.applyZoomDirectly(target)
            }
        }
    }
    
    private func applyZoomDirectly(_ target: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self, let camera = self.currentCameraDevice else { return }
            do {
                try camera.lockForConfiguration()
                let targetFactor = max(camera.minAvailableVideoZoomFactor, min(target, camera.maxAvailableVideoZoomFactor))
                if camera.isRampingVideoZoom {
                    camera.cancelVideoZoomRamp()
                }
                camera.videoZoomFactor = targetFactor
                camera.unlockForConfiguration()
            } catch {
                // 忽略频繁滑动的轻微争抢
            }
        }
    }
    
    public func stepZoom(by delta: CGFloat) {
        let target = currentZoom + delta
        setZoom(factor: target)
    }
    
    // MARK: - 前后摄像头一键安全切换 (防连续点击崩溃锁死)
    public func switchCamera() {
        guard !isSwitchingCamera else { return }
        DispatchQueue.main.async {
            self.isSwitchingCamera = true
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            if let currentInput = self.currentDeviceInput {
                self.captureSession.removeInput(currentInput)
            }
            
            let newPosition: AVCaptureDevice.Position = (self.currentPosition == .back) ? .front : .back
            let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition)
            
            if let camera = newCamera,
               let newInput = try? AVCaptureDeviceInput(device: camera),
               self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
                self.currentDeviceInput = newInput
                self.currentCameraDevice = camera
                
                // 同样为切换后的新镜头进行画质深度调校
                self.optimizeCameraHardware(camera)
                
                let minFactor = camera.minAvailableVideoZoomFactor
                let maxFactor = min(camera.maxAvailableVideoZoomFactor, newPosition == .front ? 3.0 : 15.0)
                
                DispatchQueue.main.async {
                    self.currentPosition = newPosition
                    self.minZoom = minFactor
                    self.maxZoom = maxFactor
                    self.currentZoom = 1.0
                }
            } else if let oldInput = self.currentDeviceInput {
                self.captureSession.addInput(oldInput)
            }
            
            // 重新刷新方向与前置无畸变镜像
            self.configureConnection(for: self.videoOutput.connection(with: .video), position: newPosition)
            self.configureConnection(for: self.movieOutput.connection(with: .video), position: newPosition)
            
            self.captureSession.commitConfiguration()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.isSwitchingCamera = false
            }
        }
    }
    
    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }
    
    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
    
    // MARK: - 极速安全原生拍照 (高解析力 48MP/24MP + Deep Fusion 深度画质优先)
    public func takePhoto(completion: @escaping (UIImage?) -> Void) {
        guard !isCapturingPhoto else {
            // 当前已有照片正在捕获中，丢弃多余并发请求，保护主管道
            return
        }
        
        DispatchQueue.main.async {
            self.isCapturingPhoto = true
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            self.photoCaptureCompletion = completion
            let settings = AVCapturePhotoSettings()
            
            // 开启高分辨率
            settings.isHighResolutionPhotoEnabled = true
            // 激活最高画质多帧合成 (苹果 Deep Fusion 与 Smart HDR)
            settings.photoQualityPrioritization = .quality
            
            // iOS 16+ 锁定全像素维度 (48MP / 24MP)
            if #available(iOS 16.0, *) {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }
            
            // 对齐拍照连接的前置镜像状态
            if let photoConn = self.photoOutput.connection(with: .video) {
                self.configureConnection(for: photoConn, position: self.currentPosition)
            }
            
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    // MARK: - 零延迟轻量实时预览帧抓取 (专门用于 AI 场景分析，0 开销，绝不触发物理快门拍照)
    public func captureLatestPreviewFrame() -> UIImage? {
        frameBufferLock.lock()
        defer { frameBufferLock.unlock() }
        guard let pixelBuffer = latestVideoPixelBuffer else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        // 保持人脸自拍正常朝向
        let orientation: UIImage.Orientation = (currentPosition == .front) ? .leftMirrored : .right
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
    
    // MARK: - 真实视频录制
    public func startRecordingVideo(completion: @escaping (URL?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.movieOutput.isRecording else { return }
            self.videoRecordingCompletion = completion
            
            let tempDir = FileManager.default.temporaryDirectory
            let outputURL = tempDir.appendingPathComponent("Record_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: outputURL)
            
            if let conn = self.movieOutput.connection(with: .video) {
                self.configureConnection(for: conn, position: self.currentPosition)
            }
            
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            
            DispatchQueue.main.async {
                self.isRecordingVideo = true
                self.recordingSeconds = 0
                self.recordingTimer?.invalidate()
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    self.recordingSeconds += 1
                }
            }
        }
    }
    
    public func stopRecordingVideo() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
            DispatchQueue.main.async {
                self.isRecordingVideo = false
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
            }
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 缓存轻量级帧供 AI 构图随时秒级调用，零等待
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            frameBufferLock.lock()
            self.latestVideoPixelBuffer = pixelBuffer
            frameBufferLock.unlock()
        }
        self.onFrameCaptured?(sampleBuffer)
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer {
            DispatchQueue.main.async {
                self.isCapturingPhoto = false
            }
        }
        
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.photoCaptureCompletion?(nil)
            }
            return
        }
        
        // 针对前置自拍照片进行原生标准镜像修正，杜绝左右反转
        let finalImage: UIImage
        if currentPosition == .front, let cgImage = image.cgImage {
            finalImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .leftMirrored)
        } else {
            finalImage = image
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.photoCaptureCompletion?(finalImage)
        }
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let success = (error == nil)
        DispatchQueue.main.async { [weak self] in
            if success {
                self?.videoRecordingCompletion?(outputFileURL)
            } else {
                self?.videoRecordingCompletion?(nil)
            }
        }
    }
}

/// 官方系统级超流畅相机硬件直通预览层 (对标原相机 4:3 原生比例，前置自拍防变形与自动镜像)
public struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager = CameraManager.shared
    
    public init() {}
    
    public class VideoPreviewUIView: UIView {
        override public class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
        
        override public func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
    
    public func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = cameraManager.captureSession
        // 严格以 4:3 比例填充取景框视口，100% 杜绝畸变拉伸
        view.previewLayer.videoGravity = .resizeAspectFill
        updateConnection(view.previewLayer)
        return view
    }
    
    public func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        if uiView.previewLayer.session != cameraManager.captureSession {
            uiView.previewLayer.session = cameraManager.captureSession
        }
        updateConnection(uiView.previewLayer)
    }
    
    private func updateConnection(_ layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (cameraManager.currentPosition == .front)
        }
    }
}
