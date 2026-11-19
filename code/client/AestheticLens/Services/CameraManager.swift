import Foundation
import AVFoundation
import UIKit
import CoreMedia
import CoreVideo
import Photos
import Combine

/// 工业级专业全栈相机硬件与流媒体调度管理器
/// 1. 变焦倍率与 iPhone 原生相机 1:1 绝对对齐 (通过 switchOverVideoZoomFactors 物理映射主摄与超广角)
/// 2. 支持原生无损拍照 Data 输出 (保留 Smart HDR / Deep Fusion / Display P3 / EXIF)
/// 3. 拍照(.photo 4:3) 与 视频(.hd1920x1080 16:9 60fps) 会话自动切换与平滑硬件变焦 ramp
/// 4. 精确触控对焦坐标反算与自动恢复连续对焦
/// 5. 录像离屏着色与写入彻底解耦出 sessionQueue，防止预览卡顿掉帧
public final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    public static let shared = CameraManager()
    
    // MARK: - 发布状态
    @Published public var isAuthorized: Bool = false
    @Published public var permissionDenied: Bool = false
    @Published public var isAudioAuthorized: Bool = false
    @Published public var isRunning: Bool = false
    @Published public var currentPosition: AVCaptureDevice.Position = .back
    @Published public var captureMode: Int = 0 // 0: 拍照(.photo), 1: 视频(16:9 60fps)
    
    // UI 显示层倍率 (0.5x ~ 15.0x，对标苹果原生相机)
    @Published public var currentZoom: CGFloat = 1.0
    @Published public var minZoom: CGFloat = 0.5
    @Published public var maxZoom: CGFloat = 10.0
    @Published public var availableZoomPresets: [CGFloat] = [0.5, 1.0, 2.0, 3.0, 5.0]
    
    @Published public var isCapturingPhoto: Bool = false
    @Published public var isSwitchingCamera: Bool = false
    
    // 当前物理设备朝向 (用于按钮 UI、拍照和 60fps 视频写入方向锁定)
    @Published public var deviceOrientation: AVCaptureVideoOrientation = .portrait
    
    // 60fps 电影级实时录像状态
    @Published public var isRecordingVideo: Bool = false
    @Published public var recordingSeconds: Int = 0
    @Published public var lastRecordedURL: URL?
    
    private var recordingTimer: Timer?
    private var videoRecordingCompletion: ((URL?, String?) -> Void)?
    private var isStoppingVideo = false
    
    // MARK: - 底层硬件 Pipeline
    public let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ai.aestheticlens.cameraQueue", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "ai.aestheticlens.audioQueue", qos: .userInitiated)
    private let videoRenderQueue = DispatchQueue(label: "ai.aestheticlens.videoRenderQueue", qos: .userInitiated)
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    private var currentDeviceInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?
    private var currentCameraDevice: AVCaptureDevice?
    private var isSessionConfigured = false
    
    private var photoCaptureCompletion: ((UIImage?) -> Void)?
    private var rawPhotoDataCompletion: ((Data?, AVCaptureDevice.Position) -> Void)?
    
    // 实时录像引擎
    private let recorderLock = NSLock()
    private var videoRecorder: FilteredVideoRecorder?
    private var pixelBufferPool: CVPixelBufferPool?
    private var isProcessingVideoFrame = false
    
    // 最新一帧缓冲 (用于 AI 视觉分析)
    private let frameBufferLock = NSLock()
    private var latestVideoPixelBuffer: CVPixelBuffer?
    
    // 连续变焦单槽位最新值覆盖控制 (零积压、零卡顿)
    private let zoomLock = NSLock()
    private var latestPendingUIZoom: CGFloat?
    private var isSubmittingZoom = false
    
    // 对焦恢复控制
    private var focusResetWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    
    // 传递给 Metal 渲染器的 SampleBuffer 回调
    public var onFrameCaptured: ((CMSampleBuffer) -> Void)?
    
    public override init() {
        super.init()
        setupNotifications()
        DispatchQueue.main.async { [weak self] in
            self?.setupOrientationObserver()
        }
    }
    
    private func setupOrientationObserver() {
        MotionManager.shared.$physicalOrientation
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newOrientation in
                guard let self = self, !self.isRecordingVideo else { return }
                self.updateDeviceOrientation(newOrientation)
            }
            .store(in: &cancellables)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSubjectAreaDidChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
    }
    
    @objc private func handleSubjectAreaDidChange() {
        // 画面构图发生较大移动后温和恢复连续自动对焦与测光
        restoreContinuousFocusAndExposure()
    }
    
    @objc private func handleSessionWasInterrupted(_ notification: Notification) {
        if isRecordingVideo {
            stopRecordingVideo()
        }
        DispatchQueue.main.async { self.isRunning = false }
    }
    
    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        startSession()
    }
    
    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        if let err = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            print("[CameraManager] 会话运行时异常: \(err.localizedDescription)")
        }
        startSession()
    }
    
    // MARK: - 物理镜头主摄基准倍率计算
    public var baseMainLensZoomFactor: CGFloat {
        guard let device = currentCameraDevice else { return 1.0 }
        let switchovers = device.virtualDeviceSwitchOverVideoZoomFactors
        if let firstSwitch = switchovers.first as? CGFloat, firstSwitch > 1.0 {
            return firstSwitch
        }
        return 1.0
    }
    
    private func mapUIToHardwareZoom(_ uiZoom: CGFloat, on device: AVCaptureDevice? = nil) -> CGFloat {
        guard let dev = device ?? currentCameraDevice else { return uiZoom }
        let switchovers = dev.virtualDeviceSwitchOverVideoZoomFactors
        let base = (switchovers.first as? CGFloat).flatMap { $0 > 1.0 ? $0 : nil } ?? 1.0
        let hwZoom = (base > 1.0) ? (base * uiZoom) : uiZoom
        return max(dev.minAvailableVideoZoomFactor, min(hwZoom, dev.maxAvailableVideoZoomFactor))
    }
    
    private func updateZoomBounds(for camera: AVCaptureDevice, position: AVCaptureDevice.Position) {
        let switchovers = camera.virtualDeviceSwitchOverVideoZoomFactors
        let base = (switchovers.first as? CGFloat).flatMap { $0 > 1.0 ? $0 : nil } ?? 1.0
        let hasUltraWide = (position == .back && base > 1.0)
        
        let dynamicMinUI: CGFloat = hasUltraWide ? 0.5 : 1.0
        let hwMax = camera.maxAvailableVideoZoomFactor
        let dynamicMaxUI = (base > 1.0) ? (hwMax / base) : hwMax
        let safeMaxUI: CGFloat = (position == .front) ? min(max(2.0, dynamicMaxUI), 3.0) : max(5.0, min(dynamicMaxUI, 15.0))
        
        var presets: [CGFloat] = []
        if hasUltraWide { presets.append(0.5) }
        presets.append(1.0)
        if safeMaxUI >= 2.0 { presets.append(2.0) }
        if position == .back {
            if safeMaxUI >= 3.0 { presets.append(3.0) }
            if safeMaxUI >= 5.0 { presets.append(5.0) }
        }
        
        DispatchQueue.main.async {
            self.minZoom = dynamicMinUI
            self.maxZoom = safeMaxUI
            self.availableZoomPresets = presets
            self.currentZoom = 1.0
        }
    }
    
    // MARK: - 权限检查与初始化
    public func checkPermissions() {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch videoStatus {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
                self.permissionDenied = false
            }
            setupSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    self?.permissionDenied = !granted
                }
                if granted {
                    self?.setupSessionIfNeeded()
                }
            }
        default:
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.permissionDenied = true
            }
        }
        
        if audioStatus == .authorized {
            DispatchQueue.main.async { self.isAudioAuthorized = true }
        } else if audioStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async { self?.isAudioAuthorized = granted }
            }
        }
    }
    
    private func setupSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isSessionConfigured else { return }
            self.configureSessionLocked()
        }
    }
    
    private func configureSessionLocked() {
        captureSession.beginConfiguration()
        
        // 默认拍照模式采用 .photo 保持 4:3 全传感器画幅与最高静态拍照质量
        if captureMode == 1 && captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        } else if captureSession.canSetSessionPreset(.photo) {
            captureSession.sessionPreset = .photo
        } else if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        
        // 1. 摄像头输入配置 (优先三摄/双广角以支持 0.5x~15x 无缝光学变焦)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: currentPosition
        )
        guard let camera = discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        
        captureSession.addInput(input)
        currentDeviceInput = input
        currentCameraDevice = camera
        optimizeCameraHardware(camera)
        updateZoomBounds(for: camera, position: currentPosition)
        
        // 2. 麦克风音频输入配置
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let aInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(aInput) {
            captureSession.addInput(aInput)
            currentAudioInput = aInput
        }
        
        // 3. 实时视频输出
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        configureConnection(for: videoOutput.connection(with: .video), position: currentPosition, orientation: .portrait)
        
        // 4. 音频输出
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
            audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
        }
        
        // 5. 拍照输出 (最大化原生画质：Smart HDR + 最高分辨率)
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
            updateMaxPhotoDimensions(for: camera)
            configureConnection(for: photoOutput.connection(with: .video), position: currentPosition, orientation: deviceOrientation)
        }
        
        captureSession.commitConfiguration()
        isSessionConfigured = true
        
        // commitConfiguration 后再将物理镜头锁定至 1.0x 广角主摄，防止预设重配重置倍率
        applyHardwareZoom(mapUIToHardwareZoom(1.0, on: camera), on: camera)
        
        if !captureSession.isRunning {
            captureSession.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }
    
    private func updateMaxPhotoDimensions(for camera: AVCaptureDevice) {
        if #available(iOS 16.0, *) {
            let supportedDims = camera.activeFormat.supportedMaxPhotoDimensions
            if let highestDim = supportedDims.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                photoOutput.maxPhotoDimensions = highestDim
            }
        }
    }
    
    // MARK: - 硬件参数调教与自适应最高帧率 (拍照优先画质，视频模式优先解锁 60fps)
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
            camera.isSubjectAreaChangeMonitoringEnabled = true
            
            // 在视频模式或当前格式原生支持 60fps 时锁定 60fps，否则按格式上限运行避免非法设置报错
            let targetFPS: Double = (captureMode == 1) ? 60.0 : 60.0
            let maxSupported = camera.activeFormat.videoSupportedFrameRateRanges
                .map { $0.maxFrameRate }
                .max() ?? 30.0
            
            if maxSupported >= 59.0 {
                let duration = CMTime(value: 1, timescale: Int32(min(targetFPS, maxSupported)))
                camera.activeVideoMinFrameDuration = duration
                camera.activeVideoMaxFrameDuration = duration
            }
            camera.unlockForConfiguration()
        } catch {
            print("[CameraManager] 硬件参数调优异常: \(error)")
        }
    }
    
    private func applyHardwareZoom(_ hwFactor: CGFloat, on camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            camera.cancelVideoZoomRamp()
            let safe = max(camera.minAvailableVideoZoomFactor, min(hwFactor, camera.maxAvailableVideoZoomFactor))
            camera.videoZoomFactor = safe
            camera.unlockForConfiguration()
        } catch {
            print("[CameraManager] 硬件变焦配置失败: \(error)")
        }
    }
    
    // MARK: - 拍照 / 视频会话模式切换 (保证 4:3 原生画质与 16:9 60fps 录像各自处于最佳格式)
    public func setCaptureMode(_ mode: Int) {
        guard mode != captureMode, !isRecordingVideo else { return }
        DispatchQueue.main.async { self.captureMode = mode }
        
        sessionQueue.async { [weak self] in
            guard let self = self, self.isSessionConfigured, let camera = self.currentCameraDevice else { return }
            let targetPreset: AVCaptureSession.Preset = (mode == 1 && self.captureSession.canSetSessionPreset(.hd1920x1080)) ? .hd1920x1080 : .photo
            guard self.captureSession.sessionPreset != targetPreset,
                  self.captureSession.canSetSessionPreset(targetPreset) else { return }
            
            let previousUIZoom = self.currentZoom
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = targetPreset
            self.captureSession.commitConfiguration()
            
            self.optimizeCameraHardware(camera)
            if mode == 0 {
                self.updateMaxPhotoDimensions(for: camera)
            }
            self.configureConnection(for: self.videoOutput.connection(with: .video), position: self.currentPosition, orientation: .portrait)
            self.applyHardwareZoom(self.mapUIToHardwareZoom(previousUIZoom, on: camera), on: camera)
        }
    }
    
    // MARK: - 连接镜像、防抖与方向自适应
    public func updateDeviceOrientation(_ orientation: AVCaptureVideoOrientation) {
        DispatchQueue.main.async { self.deviceOrientation = orientation }
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isRecordingVideo else { return }
            if let photoConn = self.photoOutput.connection(with: .video) {
                self.configureConnection(for: photoConn, position: self.currentPosition, orientation: orientation)
            }
        }
    }
    
    private func configureConnection(
        for connection: AVCaptureConnection?,
        position: AVCaptureDevice.Position,
        orientation: AVCaptureVideoOrientation
    ) {
        guard let connection = connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
    }
    
    // MARK: - 启动与停止 (含前后台安全调度)
    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.isSessionConfigured {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .authorized {
                    self.configureSessionLocked()
                }
                return
            }
            guard !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }
    
    public func stopSession() {
        if isRecordingVideo {
            stopRecordingVideo()
        }
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
    
    // MARK: - 镜头翻转
    public func switchCamera() {
        guard !isSwitchingCamera, !isRecordingVideo else { return }
        DispatchQueue.main.async { self.isSwitchingCamera = true }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let newPosition: AVCaptureDevice.Position = (self.currentPosition == .back) ? .front : .back
            
            let deviceTypes: [AVCaptureDevice.DeviceType] = (newPosition == .back)
                ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
                : [.builtInWideAngleCamera, .builtInTrueDepthCamera]
            
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
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
                self.updateMaxPhotoDimensions(for: newCamera)
                
                self.configureConnection(for: self.videoOutput.connection(with: .video), position: newPosition, orientation: .portrait)
                if let photoConn = self.photoOutput.connection(with: .video) {
                    self.configureConnection(for: photoConn, position: newPosition, orientation: self.deviceOrientation)
                }
            }
            self.captureSession.commitConfiguration()
            
            self.updateZoomBounds(for: newCamera, position: newPosition)
            self.applyHardwareZoom(self.mapUIToHardwareZoom(1.0, on: newCamera), on: newCamera)
            
            DispatchQueue.main.async {
                self.isSwitchingCamera = false
            }
        }
    }
    
    // MARK: - 精确触控对焦 (Aspect Fill + 设备旋转 + 前置镜像完整坐标转换) + 自动恢复连续对焦
    public func focus(at point: CGPoint) {
        focus(atNormalizedViewPoint: point)
    }
    
    public func focus(atNormalizedViewPoint viewPoint: CGPoint) {
        let clampedX = max(0.0, min(1.0, viewPoint.x))
        let clampedY = max(0.0, min(1.0, viewPoint.y))
        
        // 1. 结合当前 Metal Aspect Fill 裁剪矩阵，反算回视频纹理坐标 [0, 1]
        let uniforms = MetalRenderer.shared.latestPreviewUniforms
        let texX = CGFloat(uniforms.uvOffset.x) + clampedX * CGFloat(uniforms.uvScale.x)
        let texY = CGFloat(uniforms.uvOffset.y) + clampedY * CGFloat(uniforms.uvScale.y)
        
        // 2. 将始终为 .portrait 的预览图像坐标转换回传感器原生横屏坐标系
        let isMirrored = (currentPosition == .front)
        let devicePoint = isMirrored
            ? CGPoint(x: texY, y: texX)
            : CGPoint(x: texY, y: 1.0 - texX)
        
        let safeDevicePoint = CGPoint(
            x: max(0.0, min(1.0, devicePoint.x)),
            y: max(0.0, min(1.0, devicePoint.y))
        )
        
        focusResetWorkItem?.cancel()
        
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentCameraDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = safeDevicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = safeDevicePoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                print("[CameraManager] 触控对焦失败: \(error)")
            }
        }
        
        // 3.5 秒后自动温和恢复连续自动对焦，防止拍完一次移动手机画面失焦
        let resetTask = DispatchWorkItem { [weak self] in
            self?.restoreContinuousFocusAndExposure()
        }
        focusResetWorkItem = resetTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: resetTask)
    }
    
    private func restoreContinuousFocusAndExposure() {
        focusResetWorkItem?.cancel()
        focusResetWorkItem = nil
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentCameraDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) && device.focusMode != .continuousAutoFocus {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) && device.exposureMode != .continuousAutoExposure {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                print("[CameraManager] 恢复连续对焦失败: \(error)")
            }
        }
    }
    
    // MARK: - 变焦调节：快捷按钮使用原生平滑推拉 ramp，连续滑动使用零积压单槽位跟手控制
    public func rampZoom(to factor: CGFloat, rate: Float = 12.0) {
        let clamped = max(minZoom, min(factor, maxZoom))
        let rounded = (clamped * 10.0).rounded() / 10.0
        
        zoomLock.lock()
        latestPendingUIZoom = nil
        zoomLock.unlock()
        
        DispatchQueue.main.async {
            self.currentZoom = rounded
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentCameraDevice else { return }
            let hwTarget = self.mapUIToHardwareZoom(rounded, on: device)
            do {
                try device.lockForConfiguration()
                if device.isRampingVideoZoom {
                    device.cancelVideoZoomRamp()
                }
                let safeTarget = max(device.minAvailableVideoZoomFactor, min(hwTarget, device.maxAvailableVideoZoomFactor))
                device.ramp(toVideoZoomFactor: safeTarget, withRate: rate)
                device.unlockForConfiguration()
            } catch {
                print("[CameraManager] 平滑变焦 ramp 异常: \(error)")
            }
        }
    }
    
    public func setZoom(factor: CGFloat, publishToUI: Bool = true) {
        let clamped = max(minZoom, min(factor, maxZoom))
        let rounded = (clamped * 10.0).rounded() / 10.0
        
        if publishToUI {
            if Thread.isMainThread {
                if self.currentZoom != rounded {
                    self.currentZoom = rounded
                }
            } else {
                DispatchQueue.main.async {
                    if self.currentZoom != rounded {
                        self.currentZoom = rounded
                    }
                }
            }
        }
        
        zoomLock.lock()
        latestPendingUIZoom = rounded
        let shouldDispatch = !isSubmittingZoom
        if shouldDispatch {
            isSubmittingZoom = true
        }
        zoomLock.unlock()
        
        if shouldDispatch {
            sessionQueue.async { [weak self] in
                self?.drainPendingZoom()
            }
        }
    }
    
    private func drainPendingZoom() {
        while true {
            zoomLock.lock()
            let nextZoom = latestPendingUIZoom
            latestPendingUIZoom = nil
            if nextZoom == nil {
                isSubmittingZoom = false
                zoomLock.unlock()
                return
            }
            zoomLock.unlock()
            
            if let uiZoom = nextZoom, let device = currentCameraDevice {
                let hwTarget = mapUIToHardwareZoom(uiZoom, on: device)
                do {
                    try device.lockForConfiguration()
                    if device.isRampingVideoZoom {
                        device.cancelVideoZoomRamp()
                    }
                    let safeTarget = max(device.minAvailableVideoZoomFactor, min(hwTarget, device.maxAvailableVideoZoomFactor))
                    device.videoZoomFactor = safeTarget
                    device.unlockForConfiguration()
                } catch {
                    print("[CameraManager] 硬件变焦提交异常: \(error)")
                }
            }
        }
    }
    
    // MARK: - 拍照：提供原生二进制 Data 无损通道与向后兼容 UIImage 通道
    public func captureRawPhotoData(completion: @escaping (Data?, AVCaptureDevice.Position) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async { self.isCapturingPhoto = true }
            self.rawPhotoDataCompletion = completion
            self.photoCaptureCompletion = nil
            
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            settings.photoQualityPrioritization = .quality
            if #available(iOS 16.0, *) {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }
            if let photoConn = self.photoOutput.connection(with: .video) {
                self.configureConnection(for: photoConn, position: self.currentPosition, orientation: self.deviceOrientation)
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    public func takePhoto(completion: @escaping (UIImage?) -> Void) {
        captureRawPhotoData { data, _ in
            guard let data = data, let img = UIImage(data: data) else {
                completion(nil)
                return
            }
            completion(img)
        }
    }
    
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async { self.isCapturingPhoto = false }
        let rawCompletion = self.rawPhotoDataCompletion
        let imgCompletion = self.photoCaptureCompletion
        self.rawPhotoDataCompletion = nil
        self.photoCaptureCompletion = nil
        
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                rawCompletion?(nil, self.currentPosition)
                imgCompletion?(nil)
            }
            return
        }
        
        if let rawCompletion = rawCompletion {
            let pos = self.currentPosition
            DispatchQueue.main.async { rawCompletion(data, pos) }
        } else if let imgCompletion = imgCompletion {
            let image = UIImage(data: data)
            DispatchQueue.main.async { imgCompletion(image) }
        }
    }
    
    // MARK: - 最新一帧提取 (修正：videoOutput 已按设备方向旋转过，直接输出正向 UIImage 供 AI/Vision 使用)
    public func captureLatestPreviewFrame() -> UIImage? {
        frameBufferLock.lock()
        guard let pixelBuffer = latestVideoPixelBuffer else {
            frameBufferLock.unlock()
            return nil
        }
        frameBufferLock.unlock()
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

    // MARK: - 实时录像 (Metal 3D LUT 上色 + 60fps 硬件编码写入，彻底解耦出 sessionQueue)
    public func startRecordingVideo(completion: @escaping (URL?, String?) -> Void) {
        guard !isRecordingVideo, !isStoppingVideo else { return }
        
        recorderLock.lock()
        guard videoRecorder == nil else {
            recorderLock.unlock()
            return
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AestheticLens_\(Int(Date().timeIntervalSince1970)).mp4")
        
        let recordWidth: Int
        let recordHeight: Int
        if deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight {
            recordWidth = 1920
            recordHeight = 1080
        } else {
            recordWidth = 1080
            recordHeight = 1920
        }
        
        let recorder = FilteredVideoRecorder(
            outputURL: tempURL,
            width: recordWidth,
            height: recordHeight,
            hasAudio: isAudioAuthorized,
            orientation: deviceOrientation
        )
        self.videoRecorder = recorder
        self.pixelBufferPool = createPixelBufferPool(width: recordWidth, height: recordHeight)
        recorderLock.unlock()
        
        self.videoRecordingCompletion = completion
        
        DispatchQueue.main.async {
            self.isRecordingVideo = true
            self.recordingSeconds = 0
            self.recordingTimer?.invalidate()
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.recordingSeconds += 1
            }
        }
    }
    
    public func stopRecordingVideo() {
        guard isRecordingVideo, !isStoppingVideo else { return }
        isStoppingVideo = true
        
        DispatchQueue.main.async {
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
        }
        
        recorderLock.lock()
        let activeRecorder = self.videoRecorder
        self.videoRecorder = nil
        recorderLock.unlock()
        
        videoRenderQueue.async { [weak self] in
            guard let self = self else { return }
            guard let recorder = activeRecorder else {
                DispatchQueue.main.async {
                    self.isRecordingVideo = false
                    self.isStoppingVideo = false
                }
                return
            }
            
            recorder.finish { [weak self] url in
                guard let self = self else { return }
                guard let url = url else {
                    DispatchQueue.main.async {
                        self.isRecordingVideo = false
                        self.isStoppingVideo = false
                        self.videoRecordingCompletion?(nil, "视频写入失败")
                        self.videoRecordingCompletion = nil
                    }
                    return
                }
                
                self.saveVideoToPhotosLibrary(url: url) { success, errMsg in
                    DispatchQueue.main.async {
                        self.lastRecordedURL = url
                        self.isRecordingVideo = false
                        self.isStoppingVideo = false
                        self.videoRecordingCompletion?(url, success ? nil : (errMsg ?? "保存到相册失败"))
                        self.videoRecordingCompletion = nil
                    }
                }
            }
        }
    }
    
    private func createPixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 6
        ]
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &pool)
        return pool
    }
    
    private func saveVideoToPhotosLibrary(url: URL, completion: @escaping (Bool, String?) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                completion(success, error?.localizedDescription)
            }
        } else if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    }) { success, error in
                        completion(success, error?.localizedDescription)
                    }
                } else {
                    completion(false, "未获得相册写入权限")
                }
            }
        } else {
            completion(false, "请在系统设置中允许访问相册")
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AudioDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoOutput {
            if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                frameBufferLock.lock()
                self.latestVideoPixelBuffer = pb
                frameBufferLock.unlock()
            }
            
            // 1. 取景器按需刷新通知 (极快，不阻塞采集)
            onFrameCaptured?(sampleBuffer)
            
            // 2. 录像离线着色与写入解耦到 videoRenderQueue (背压丢帧保护，绝不卡死预览流)
            recorderLock.lock()
            let activeRecorder = self.videoRecorder
            let activePool = self.pixelBufferPool
            let busy = self.isProcessingVideoFrame
            if activeRecorder != nil && activePool != nil && !busy {
                self.isProcessingVideoFrame = true
            }
            recorderLock.unlock()
            
            if let recorder = activeRecorder, let pool = activePool, !busy,
               let inputPB = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                videoRenderQueue.async { [weak self] in
                    defer {
                        self?.recorderLock.lock()
                        self?.isProcessingVideoFrame = false
                        self?.recorderLock.unlock()
                    }
                    var outPB: CVPixelBuffer?
                    let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outPB)
                    if status == kCVReturnSuccess, let dst = outPB {
                        if MetalRenderer.shared.renderFilteredPixelBuffer(input: inputPB, output: dst) {
                            recorder.appendVideoBuffer(dst, presentationTime: pts)
                        }
                    }
                }
            }
        } else if output == audioOutput {
            recorderLock.lock()
            let activeRecorder = self.videoRecorder
            recorderLock.unlock()
            if let recorder = activeRecorder {
                recorder.appendAudioSample(sampleBuffer)
            }
        }
    }
    
    /// 获取当前相机最新画面 CVPixelBuffer 供端侧 Vision 多维感知分析
    public func getLatestPixelBuffer() -> CVPixelBuffer? {
        frameBufferLock.lock()
        let pb = self.latestVideoPixelBuffer
        frameBufferLock.unlock()
        return pb
    }
}

// MARK: - 60fps 电影级滤镜视频硬件编码写入器
final class FilteredVideoRecorder {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let writeQueue = DispatchQueue(label: "ai.aestheticlens.videoWriteQueue", qos: .userInitiated)
    
    private var isStarted = false
    private var isFinished = false
    
    init?(outputURL: URL, width: Int, height: Int, hasAudio: Bool, orientation: AVCaptureVideoOrientation) {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            return nil
        }
        self.assetWriter = writer
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 20_000_000,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        self.videoInput = vInput
        
        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: adaptorAttrs
        )
        
        if writer.canAdd(vInput) {
            writer.add(vInput)
        }
        
        if hasAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128_000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) {
                writer.add(aInput)
                self.audioInput = aInput
            } else {
                self.audioInput = nil
            }
        } else {
            self.audioInput = nil
        }
    }
    
    func appendVideoBuffer(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        writeQueue.async { [weak self] in
            guard let self = self, !self.isFinished else { return }
            if !self.isStarted {
                guard self.assetWriter.startWriting() else { return }
                self.assetWriter.startSession(atSourceTime: presentationTime)
                self.isStarted = true
            }
            if self.videoInput.isReadyForMoreMediaData && self.assetWriter.status == .writing {
                self.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }
    }
    
    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        writeQueue.async { [weak self] in
            guard let self = self, !self.isFinished, self.isStarted,
                  let aInput = self.audioInput else { return }
            if aInput.isReadyForMoreMediaData && self.assetWriter.status == .writing {
                aInput.append(sampleBuffer)
            }
        }
    }
    
    func finish(completion: @escaping (URL?) -> Void) {
        writeQueue.async { [weak self] in
            guard let self = self, !self.isFinished else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.isFinished = true
            
            guard self.isStarted, self.assetWriter.status == .writing else {
                self.assetWriter.cancelWriting()
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            self.videoInput.markAsFinished()
            self.audioInput?.markAsFinished()
            let url = self.assetWriter.outputURL
            self.assetWriter.finishWriting {
                DispatchQueue.main.async {
                    completion(self.assetWriter.status == .completed ? url : nil)
                }
            }
        }
    }
}
