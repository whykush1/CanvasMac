import Cocoa
import AVFoundation

/// A performance-optimized video playback view built directly on AVPlayerLayer.
/// Avoids preventing system sleep and includes low-overhead looping.
class CanvasVideoPlayerView: NSView {
    
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    
    // Performance and configuration tracking
    var playbackSpeed: Double = 1.0 {
        didSet {
            updatePlaybackRate()
        }
    }
    
    var isMuted: Bool = true {
        didSet {
            player?.isMuted = isMuted
        }
    }
    
    var volume: Float = 0.0 {
        didSet {
            player?.volume = volume
        }
    }
    
    init(videoURL: URL, speed: Double = 1.0, muted: Bool = true, volume: Float = 0.0) {
        self.playbackSpeed = speed
        self.isMuted = muted
        self.volume = volume
        super.init(frame: .zero)
        
        setupLayerBackedView()
        initializePlayer(url: videoURL)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayerBackedView() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }
    
    private func initializePlayer(url: URL) {
        // Create the asset and player item
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let playerItem = AVPlayerItem(asset: asset)
        
        // Optimize video loading performance
        playerItem.audioTimePitchAlgorithm = .timeDomain // High-fidelity audio stretching
        
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        
        // Prevent player from blocking sleep
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.isMuted = isMuted
        player.volume = volume
        
        // Setup Player Layer
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = self.bounds
        // Optimize for ProMotion displays (enables smoother rendering pipelines)
        playerLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        self.layer?.addSublayer(playerLayer)
        self.playerLayer = playerLayer
        
        // Loop completion listener
        player.actionAtItemEnd = .none
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.rewindAndPlay()
        }
        
        // Handle loading errors or asset status
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, change in
            if item.status == .failed {
                let error = item.error ?? NSError(domain: "com.canvas.video", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown video playback error"])
                self?.handlePlaybackFailure(error: error)
            }
        }
        
        // Start playback
        play()
    }
    
    private func rewindAndPlay() {
        guard let player = player else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                self?.play()
            }
        }
    }
    
    func play() {
        guard let player = player else { return }
        player.play()
        updatePlaybackRate()
    }
    
    func pause() {
        player?.pause()
    }
    
    func stop() {
        pause()
        rewindAndPlay()
    }
    
    func throttlePlayback(lowPowerMode: Bool) {
        if lowPowerMode {
            // Half the speed or pause to conserve GPU/CPU resources in Low Power Mode
            player?.rate = Float(playbackSpeed * 0.5)
        } else {
            updatePlaybackRate()
        }
    }
    
    private func updatePlaybackRate() {
        guard let player = player, player.rate != 0.0 else { return }
        player.rate = Float(playbackSpeed)
    }
    
    private func handlePlaybackFailure(error: Error) {
        print("Canvas Video Engine Error: \(error.localizedDescription)")
        // Post failure notification for settings panel error state
        NotificationCenter.default.post(name: .CanvasWallpaperPlaybackFailed, object: error)
    }
    
    override func layout() {
        super.layout()
        // Keep AVPlayerLayer frame perfectly sized
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = self.bounds
        CATransaction.commit()
    }
    
    deinit {
        statusObserver?.invalidate()
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
}

extension Notification.Name {
    static let CanvasWallpaperPlaybackFailed = Notification.Name("CanvasWallpaperPlaybackFailed")
}
