import Foundation
import AVFoundation
import Combine

/// 视频播放与调色导出管线服务 (REQ-13)
public final class VideoPlayerService: ObservableObject {
    public static let shared = VideoPlayerService()
    
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: Double = 0.0
    @Published public var duration: Double = 15.0
    @Published public var isExporting: Bool = false
    @Published public var exportProgress: Double = 0.0
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    
    public init() {}
    
    // MARK: - 载入并初始化视频
    public func loadVideo(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        self.player = AVPlayer(playerItem: playerItem)
        
        // 监听播放时间
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    // MARK: - 播放与暂停切换
    public func togglePlayPause() {
        guard let p = player else {
            // 模拟器/预览纯演示模式
            isPlaying.toggle()
            return
        }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }
    
    // MARK: - 进度条拖拽毫秒级跳转 (Scrubbing)
    public func seek(to seconds: Double) {
        currentTime = seconds
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    // MARK: - 提取 3 张关键帧用于云端 AI 美学感知
    public func extractKeyframes(from asset: AVAsset, completion: @escaping ([KeyframeItem]) -> Void) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        
        let times = [
            NSValue(time: CMTime(seconds: 0.5, preferredTimescale: 600)),
            NSValue(time: CMTime(seconds: 5.0, preferredTimescale: 600)),
            NSValue(time: CMTime(seconds: 10.0, preferredTimescale: 600))
        ]
        
        // 快速异步生成
        DispatchQueue.global(qos: .userInitiated).async {
            var items: [KeyframeItem] = []
            for (idx, timeVal) in times.enumerated() {
                let cmTime = timeVal.timeValue
                if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) {
                    #if canImport(UIKit)
                    let uiImg = UIImage(cgImage: cgImage)
                    if let jpegData = uiImg.jpegData(compressionQuality: 0.75) {
                        items.append(KeyframeItem(
                            timestampSec: cmTime.seconds,
                            frameIndex: idx * 300,
                            imageBase64: jpegData.base64EncodedString()
                        ))
                    }
                    #endif
                }
            }
            DispatchQueue.main.async {
                completion(items)
            }
        }
    }
    
    // MARK: - 硬件加速导出调色成品视频
    public func exportGradedVideo(
        recipe: RecipeParameters,
        lutId: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.isExporting = true
        self.exportProgress = 0.0
        
        // 模拟硬件加速压制进度 (真实真机上使用 AVAssetExportSession)
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.exportProgress += 0.2
            if self.exportProgress >= 1.0 {
                timer.invalidate()
                self.isExporting = false
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("graded_export_\(UUID().uuidString).mp4")
                completion(.success(tempURL))
            }
        }
    }
    
    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
    }
}
