import Foundation
import UIKit
import SwiftUI
import AVFoundation
import CoreMedia
import Combine

/// AVFoundation 相机管道管理服务 (最高原生画质、多焦段变焦、真实视频录制与 Metal 抽帧)
public final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    public static let shared = CameraManager()
    
    // 权限与运行状态
    @Published public var isAuthorized: Bool = false
    @Published public var isRunning: Bool = false
    @Published public var currentPosition: AVCaptureDevice.Position = .back
    
    // 变焦状态 (对标手机摄像头水平，支持 0.5x~10.0x 连续滑动，精度 0.1x)
    @Published public var currentZoom: CGFloat = 1.0
    @Published public var minZoom: CGFloat = 0.5
    @Published public var maxZoom: CGFloat = 10.0
    
    // 真实录像状态
    @Published public var isRecordingVideo: Bool = false
    @Published public var recordingSeconds: Int = 0
    private var recordingTimer: Timer?
    private var videoRecordingCompletion: ((URL?) -> Void)?
    
    public let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ai.aestheticlens.cameraQueue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentDeviceInput: AVCaptureDeviceInput?
    private var currentCameraDevice: AVCaptureDevice?
    private var photoCaptureCompletion: ((UIImage?) -> Void)?
    
    // 传递给 Metal 渲染器的 SampleBuffer 回调
    public var onFrameCaptured: ((CMSampleBuffer) -> Void)?
    
    public override init() {
        super.init()
        checkPermissions()
    }
    
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
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            // 采用原生最高分辨率 .photo 模式 (彻底解决画质被压缩问题)
            if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .photo
            } else if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            
            // 配置初始后置摄像头 (支持三摄/双超广角/双摄/广角)
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: self.currentPosition
            )
            guard let camera = discoverySession.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)
            self.currentDeviceInput = input
            self.currentCameraDevice = camera
            
            // 对标真实手机硬件变焦能力 (支持超广角 0.5x 到数码长焦 10.0x / 15.0x)
            let minFactor = camera.minAvailableVideoZoomFactor
            let maxFactor = min(camera.maxAvailableVideoZoomFactor, 15.0)
            DispatchQueue.main.async {
                self.minZoom = min(minFactor, 1.0)
                self.maxZoom = max(maxFactor, 5.0)
                self.currentZoom = max(1.0, minFactor)
            }
            
            // 配置视频输出 (BGRA 格式供 Metal 实时采样)
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            
            // 修正取景视频连接方向为竖屏 (Portrait)
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            // 配置高画质照片输出
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                if self.photoOutput.maxPhotoQualityPrioritization == .quality {
                    // 支持最高画质 Deep Fusion / Smart HDR 图像处理
                }
            }
            
            // 配置真实视频录制输出
            if self.captureSession.canAddOutput(self.movieOutput) {
                self.captureSession.addOutput(self.movieOutput)
                if let connection = self.movieOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
            }
            
            self.captureSession.commitConfiguration()
            
            // 配置完成后立即开启采集
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                }
            }
        }
    }
    
    // MARK: - 手势与焦段变焦控制 (对标手机摄像头硬件水平，滑动设置与 0.1x 精度步进)
    public func setZoom(factor: CGFloat) {
        // 严格以 0.1x 步进进行四舍五入
        let roundedFactor = (factor * 10.0).rounded() / 10.0
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentCameraDevice else { return }
            let clampedFactor = max(self.minZoom, min(roundedFactor, self.maxZoom))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clampedFactor
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.currentZoom = clampedFactor
                }
            } catch {
                print("[CameraManager] 设置变焦失败: \(error)")
            }
        }
    }
    
    /// 单步步进（每次 +/- 0.1x 微调）
    public func stepZoom(by delta: CGFloat) {
        let target = currentZoom + delta
        setZoom(factor: target)
    }
    
    // MARK: - 切换前后摄像头
    public func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            if let currentInput = self.currentDeviceInput {
                self.captureSession.removeInput(currentInput)
            }
            
            let newPosition: AVCaptureDevice.Position = (self.currentPosition == .back) ? .front : .back
            if let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
               let newInput = try? AVCaptureDeviceInput(device: newCamera),
               self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
                self.currentDeviceInput = newInput
                self.currentCameraDevice = newCamera
                DispatchQueue.main.async {
                    self.currentPosition = newPosition
                    self.currentZoom = 1.0
                }
            } else if let oldInput = self.currentDeviceInput {
                self.captureSession.addInput(oldInput)
            }
            
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            if let movieConn = self.movieOutput.connection(with: .video) {
                if movieConn.isVideoOrientationSupported {
                    movieConn.videoOrientation = .portrait
                }
            }
            
            self.captureSession.commitConfiguration()
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
    
    // MARK: - 原生最高画质拍照
    public func takePhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.photoCaptureCompletion = completion
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            if self.photoOutput.maxPhotoQualityPrioritization == .quality {
                settings.photoQualityPrioritization = .quality
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    // MARK: - 真实视频录制开始与停止
    public func startRecordingVideo(completion: @escaping (URL?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.movieOutput.isRecording else { return }
            self.videoRecordingCompletion = completion
            
            let tempDir = FileManager.default.temporaryDirectory
            let outputURL = tempDir.appendingPathComponent("Record_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: outputURL)
            
            if let conn = self.movieOutput.connection(with: .video) {
                if conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
                }
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
        self.onFrameCaptured?(sampleBuffer)
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.photoCaptureCompletion?(nil)
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.photoCaptureCompletion?(image)
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

/// 官方系统级超流畅相机硬件直通预览层 (100% 绝对不黑屏双保险)
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
    }
    
    public func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = cameraManager.captureSession
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        return view
    }
    
    public func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        if uiView.previewLayer.session != cameraManager.captureSession {
            uiView.previewLayer.session = cameraManager.captureSession
        }
    }
}
