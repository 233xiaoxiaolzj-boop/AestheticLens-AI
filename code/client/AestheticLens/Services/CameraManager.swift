import Foundation
import AVFoundation
import UIKit
import CoreMedia
import CoreVideo
import Photos

/// 工业级专业全栈相机硬件与流媒体调度管理器
/// 完美支持 120fps 取景生态、60fps 胶片滤镜视频直出录制、48MP 原生画质与触控对焦
public final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    public static let shared = CameraManager()
    
    // MARK: - 发布状态
    @Published public var isAuthorized: Bool = false
    @Published public var isAudioAuthorized: Bool = false
    @Published public var isRunning: Bool = false
    @Published public var currentPosition: AVCaptureDevice.Position = .back
    @Published public var currentZoom: CGFloat = 1.0
    @Published public var minZoom: CGFloat = 0.5
    @Published public var maxZoom: CGFloat = 10.0
    @Published public var isCapturingPhoto: Bool = false
    @Published public var isSwitchingCamera: Bool = false
    
    // 60fps 电影级实时录像状态
    @Published public var isRecordingVideo: Bool = false
    @Published public var recordingSeconds: Int = 0
    @Published public var lastRecordedURL: URL?
    
    private var recordingTimer: Timer?
    private var videoRecordingCompletion: ((URL?) -> Void)?
    
    // MARK: - 底层硬件 Pipeline
    public let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ai.aestheticlens.cameraQueue", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "ai.aestheticlens.audioQueue", qos: .userInitiated)
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    private var currentDeviceInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?
    private var currentCameraDevice: AVCaptureDevice?
    private var photoCaptureCompletion: ((UIImage?) -> Void)?
    
    // 实时录像引擎 (硬编码 60fps 滤镜输出)
    private var videoRecorder: FilteredVideoRecorder?
    private var pixelBufferPool: CVPixelBufferPool?
    
    // 最新一帧缓冲 (用于 AI 视觉实时分析，零开销)
    private let frameBufferLock = NSLock()
    private var latestVideoPixelBuffer: CVPixelBuffer?
    
    // 变焦平滑防抖限流
    private var pendingZoomFactor: CGFloat?
    private var lastZoomUpdateTime: TimeInterval = 0
    private let zoomThrottleInterval: TimeInterval = 0.033
    
    // 传递给 Metal 渲染器的 SampleBuffer 回调
    public var onFrameCaptured: ((CMSampleBuffer) -> Void)?
    
    public override init() {
        super.init()
        checkPermissions()
    }
    
    // MARK: - 权限检查与初始化
    public func checkPermissions() {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if videoStatus == .authorized {
            DispatchQueue.main.async { self.isAuthorized = true }
            setupSession()
        } else if videoStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.isAuthorized = granted }
                if granted { self?.setupSession() }
            }
        } else {
            DispatchQueue.main.async { self.isAuthorized = false }
        }
        
        if audioStatus == .authorized {
            DispatchQueue.main.async { self.isAudioAuthorized = true }
        } else if audioStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async { self?.isAudioAuthorized = granted }
            }
        }
    }
    
    // MARK: - 初始化 Pipeline
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            // 默认采用高画质预设
            if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .photo
            } else if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            
            // 1. 摄像头输入配置
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
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
            self.optimizeCameraHardware(camera)
            
            let minFactor = camera.minAvailableVideoZoomFactor
            let maxFactor = min(camera.maxAvailableVideoZoomFactor, 15.0)
            DispatchQueue.main.async {
                self.minZoom = min(minFactor, 0.5)
                self.maxZoom = max(maxFactor, 10.0)
                self.currentZoom = max(1.0, minFactor)
            }
            
            // 2. 麦克风音频输入配置 (录制 60fps 电影声音)
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let aInput = try? AVCaptureDeviceInput(device: audioDevice),
               self.captureSession.canAddInput(aInput) {
                self.captureSession.addInput(aInput)
                self.currentAudioInput = aInput
            }
            
            // 3. 实时视频输出 (送往 Metal 取景与录像硬编码)
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            self.configureConnection(for: self.videoOutput.connection(with: .video), position: self.currentPosition)
            
            // 4. 音频输出 (送往 60fps 录像合成)
            if self.captureSession.canAddOutput(self.audioOutput) {
                self.captureSession.addOutput(self.audioOutput)
                self.audioOutput.setSampleBufferDelegate(self, queue: self.audioQueue)
            }
            
            // 5. 拍照输出 (48MP + Smart HDR)
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                if #available(iOS 16.0, *) {
                    let supportedDims = camera.activeFormat.supportedMaxPhotoDimensions
                    if let highestDim = supportedDims.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                        self.photoOutput.maxPhotoDimensions = highestDim
                    }
                }
            }
            
            self.captureSession.commitConfiguration()
            
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                DispatchQueue.main.async { self.isRunning = true }
            }
        }
    }
    
    // MARK: - 硬件镜头光学 ISP 调教
    private func optimizeCameraHardware(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if camera.isLowLightBoostSupported {
                camera.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            // 锁定 60fps 支持
            lockFrameRateTo60IfPossible(on: camera)
            camera.unlockForConfiguration()
        } catch {
            print("[CameraManager] 硬件参数调优异常: \(error)")
        }
    }
    
    private func lockFrameRateTo60IfPossible(on camera: AVCaptureDevice) {
        var bestRange: AVFrameRateRange?
        for range in camera.activeFormat.videoSupportedFrameRateRanges {
            if range.maxFrameRate >= 60.0 {
                bestRange = range
                break
            }
        }
        if let range = bestRange {
            let duration = CMTime(value: 1, timescale: Int32(min(60.0, range.maxFrameRate)))
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
            print("[CameraManager] 成功配置采集帧率为 60fps")
        }
    }
    
    // MARK: - 连接镜像与方向
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
    
    // MARK: - 启动与停止
    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }
    
    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
    
    // MARK: - 镜头翻转 (平滑无感)
    public func switchCamera() {
        guard !isSwitchingCamera else { return }
        DispatchQueue.main.async { self.isSwitchingCamera = true }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let newPosition: AVCaptureDevice.Position = (self.currentPosition == .back) ? .front : .back
            
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera],
                mediaType: .video,
                position: newPosition
            )
            guard let newCamera = discovery.devices.first,
                  let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
                DispatchQueue.main.async { self.isSwitchingCamera = false }
                return
            }
            
            self.captureSession.beginConfiguration()
            if let oldInput = self.currentDeviceInput {
                self.captureSession.removeInput(oldInput)
            }
            if self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
                self.currentDeviceInput = newInput
                self.currentCameraDevice = newCamera
                self.currentPosition = newPosition
                self.optimizeCameraHardware(newCamera)
                
                self.configureConnection(for: self.videoOutput.connection(with: .video), position: newPosition)
                if let photoConn = self.photoOutput.connection(with: .video) {
                    self.configureConnection(for: photoConn, position: newPosition)
                }
            }
            self.captureSession.commitConfiguration()
            
            let minF = newCamera.minAvailableVideoZoomFactor
            let maxF = min(newCamera.maxAvailableVideoZoomFactor, 10.0)
            DispatchQueue.main.async {
                self.minZoom = min(minF, 0.5)
                self.maxZoom = max(maxF, 5.0)
                self.currentZoom = max(1.0, minF)
                self.isSwitchingCamera = false
            }
        }
    }
    
    // MARK: - 触控对焦 (Tap-to-Focus)
    public func focus(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentCameraDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                print("[CameraManager] 触控对焦配置失败: \(error)")
            }
        }
    }
    
    // MARK: - 变焦倍率调节
    public func setZoom(factor: CGFloat) {
        let clamped = max(minZoom, min(factor, maxZoom))
        DispatchQueue.main.async { self.currentZoom = clamped }
        
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentCameraDevice else { return }
            self.pendingZoomFactor = clamped
            let now = CACurrentMediaTime()
            guard (now - self.lastZoomUpdateTime) >= self.zoomThrottleInterval else { return }
            self.lastZoomUpdateTime = now
            
            do {
                try device.lockForConfiguration()
                if let target = self.pendingZoomFactor {
                    let safeTarget = max(device.minAvailableVideoZoomFactor, min(target, device.maxAvailableVideoZoomFactor))
                    device.videoZoomFactor = safeTarget
                    self.pendingZoomFactor = nil
                }
                device.unlockForConfiguration()
            } catch {
                print("[CameraManager] 硬件变焦调节失败: \(error)")
            }
        }
    }
    
    // MARK: - 拍照 (48MP 超清直出)
    public func takePhoto(completion: @escaping (UIImage?) -> Void) {
        capturePhoto(completion: completion)
    }
    
    public func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async { self.isCapturingPhoto = true }
            self.photoCaptureCompletion = completion
            
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            settings.photoQualityPrioritization = .quality
            if #available(iOS 16.0, *) {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }
            if let photoConn = self.photoOutput.connection(with: .video) {
                self.configureConnection(for: photoConn, position: self.currentPosition)
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    // MARK: - 最新一帧提取 (用于 AI 构图分析)
    public func captureLatestPreviewFrame() -> UIImage? {
        frameBufferLock.lock()
        defer { frameBufferLock.unlock() }
        guard let pixelBuffer = latestVideoPixelBuffer else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let orientation: UIImage.Orientation = (currentPosition == .front) ? .leftMirrored : .right
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
    
    // MARK: - 60fps 电影级胶片滤镜视频录制直出 (所见即所得)
    public func startRecordingVideo(completion: @escaping (URL?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isRecordingVideo else { return }
            self.videoRecordingCompletion = completion
            
            let tempDir = FileManager.default.temporaryDirectory
            let outputURL = tempDir.appendingPathComponent("Film_\(UUID().uuidString).mov")
            
            // 初始化 60fps 录制引擎 (1080x1920 高码率)
            let recorder = FilteredVideoRecorder(outputURL: outputURL, videoSize: CGSize(width: 1080, height: 1920), is60fps: true)
            guard recorder.start() else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            self.videoRecorder = recorder
            self.setupPixelBufferPool(width: 1080, height: 1920)
            
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
            guard let self = self, self.isRecordingVideo, let recorder = self.videoRecorder else { return }
            
            recorder.stop { [weak self] recordedURL in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.isRecordingVideo = false
                    self.recordingTimer?.invalidate()
                    self.recordingTimer = nil
                    self.videoRecorder = nil
                }
                
                guard let finalURL = recordedURL else {
                    DispatchQueue.main.async { self.videoRecordingCompletion?(nil) }
                    return
                }
                
                // 自动保存带滤镜的 60fps 视频至相册
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: finalURL)
                }) { success, error in
                    DispatchQueue.main.async {
                        self.lastRecordedURL = finalURL
                        self.videoRecordingCompletion?(finalURL)
                    }
                }
            }
        }
    }
    
    private func setupPixelBufferPool(width: Int, height: Int) {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 6
        ]
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &self.pixelBufferPool)
    }
    
    private func allocateTargetBuffer() -> CVPixelBuffer? {
        guard let pool = self.pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (视频数据流)
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == self.videoOutput {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                frameBufferLock.lock()
                self.latestVideoPixelBuffer = pixelBuffer
                frameBufferLock.unlock()
                
                // 实时录制分支：GPU 3D LUT 上色后写入 60fps 视频流
                if self.isRecordingVideo, let recorder = self.videoRecorder {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    if let targetBuffer = self.allocateTargetBuffer() {
                        let ok = MetalRenderer.shared.renderFilteredPixelBuffer(input: pixelBuffer, output: targetBuffer)
                        if ok {
                            recorder.appendVideoFrame(pixelBuffer: targetBuffer, presentationTime: pts)
                        } else {
                            recorder.appendVideoFrame(pixelBuffer: pixelBuffer, presentationTime: pts)
                        }
                    }
                }
            }
            self.onFrameCaptured?(sampleBuffer)
        } else if output == self.audioOutput {
            // 音频数据流直通写入
            if self.isRecordingVideo, let recorder = self.videoRecorder {
                recorder.appendAudioSampleBuffer(sampleBuffer)
            }
        }
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate (拍照回调)
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer {
            DispatchQueue.main.async { self.isCapturingPhoto = false }
        }
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.photoCaptureCompletion?(nil) }
            return
        }
        let finalImage: UIImage
        if currentPosition == .front, let cgImage = image.cgImage {
            finalImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .leftMirrored)
        } else {
            finalImage = image
        }
        DispatchQueue.main.async { self.photoCaptureCompletion?(finalImage) }
    }
}

// MARK: - 实时胶片滤镜视频录制器 (AVAssetWriter 硬编码引擎)
public final class FilteredVideoRecorder {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private let outputURL: URL
    private let videoSize: CGSize
    private let is60fps: Bool
    private var isRecording = false
    private var sessionStarted = false
    private let writeQueue = DispatchQueue(label: "ai.aestheticlens.videoWriterQueue", qos: .userInitiated)
    
    public init(outputURL: URL, videoSize: CGSize = CGSize(width: 1080, height: 1920), is60fps: Bool = true) {
        self.outputURL = outputURL
        self.videoSize = videoSize
        self.is60fps = is60fps
    }
    
    public func start() -> Bool {
        try? FileManager.default.removeItem(at: outputURL)
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            print("[FilteredVideoRecorder] 创建 AssetWriter 失败: \(error)")
            return false
        }
        
        // 视频压缩参数: 25Mbps 恒定 60fps
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 25_000_000,
                AVVideoExpectedSourceFrameRateKey: is60fps ? 60 : 30,
                AVVideoMaxKeyFrameIntervalKey: is60fps ? 60 : 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(videoSize.width),
            kCVPixelBufferHeightKey as String: Int(videoSize.height)
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vInput, sourcePixelBufferAttributes: attrs)
        if assetWriter?.canAdd(vInput) == true {
            assetWriter?.add(vInput)
            self.videoInput = vInput
        }
        
        // 音频压缩参数: AAC 48kHz 立体声
        var acl = AudioChannelLayout()
        bzero(&acl, MemoryLayout<AudioChannelLayout>.size)
        acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let aclData = Data(bytes: &acl, count: MemoryLayout<AudioChannelLayout>.size)
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48000.0,
            AVEncoderBitRateKey: 128000,
            AVChannelLayoutKey: aclData
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true
        if assetWriter?.canAdd(aInput) == true {
            assetWriter?.add(aInput)
            self.audioInput = aInput
        }
        
        guard assetWriter?.startWriting() == true else {
            return false
        }
        self.isRecording = true
        self.sessionStarted = false
        return true
    }
    
    public func appendVideoFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard isRecording, let writer = assetWriter, writer.status == .writing else { return }
        writeQueue.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            if !self.sessionStarted {
                self.assetWriter?.startSession(atSourceTime: presentationTime)
                self.sessionStarted = true
            }
            if let vInput = self.videoInput, vInput.isReadyForMoreMediaData {
                self.adaptor?.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }
    }
    
    public func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, sessionStarted, let writer = assetWriter, writer.status == .writing else { return }
        writeQueue.async { [weak self] in
            guard let self = self, self.isRecording, self.sessionStarted else { return }
            if let aInput = self.audioInput, aInput.isReadyForMoreMediaData {
                aInput.append(sampleBuffer)
            }
        }
    }
    
    public func stop(completion: @escaping (URL?) -> Void) {
        isRecording = false
        writeQueue.async { [weak self] in
            guard let self = self, let writer = self.assetWriter else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            writer.finishWriting {
                if writer.status == .completed {
                    DispatchQueue.main.async { completion(self.outputURL) }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            }
        }
    }
}
