import Foundation
import UIKit
import SwiftUI
import AVFoundation
import CoreMedia
import Combine

/// AVFoundation 相机管道管理服务 (支持 60fps 预览与零拷贝 Metal 抽帧)
public final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public static let shared = CameraManager()
    
    @Published public var isAuthorized: Bool = false
    @Published public var isRunning: Bool = false
    @Published public var currentPosition: AVCaptureDevice.Position = .back
    
    public let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ai.aestheticlens.cameraQueue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentDeviceInput: AVCaptureDeviceInput?
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
            
            // 采用 1080p 优质预设
            if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                self.captureSession.sessionPreset = .hd1920x1080
            }
            
            // 配置初始摄像头 (默认后置广角)
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)
            self.currentDeviceInput = input
            
            // 配置视频输出 (BGRA 格式)
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
            
            // 配置照片输出
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
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
    
    /// 切换前后摄像头
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
                DispatchQueue.main.async {
                    self.currentPosition = newPosition
                }
            } else if let oldInput = self.currentDeviceInput {
                self.captureSession.addInput(oldInput)
            }
            
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
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
    
    /// 拍摄真实照片
    public func takePhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.photoCaptureCompletion = completion
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        self.onFrameCaptured?(sampleBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
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
