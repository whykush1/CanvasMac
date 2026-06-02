import Cocoa
import Combine
import AVFoundation

enum WallpaperLayoutMode: String, Codable {
    case independent // Each display has its own independent wallpaper
    case stretched   // A single wallpaper stretched across all displays
}

/// Coordinates multiple displays, reacts to monitor layout changes,
/// and handles high-fidelity wallpaper window stitching or independent monitors.
class DisplayManager: ObservableObject {
    
    static let shared = DisplayManager()
    
    @Published var layoutMode: WallpaperLayoutMode = .independent {
        didSet {
            rebuildWallpaperWindows()
        }
    }
    
    private var windowControllers: [NSScreen: WallpaperWindowController] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Holds reference to currently selected asset metadata
    @Published var currentWallpaperURL: URL?
    private var currentIsVideo = false
    private var currentSpeed: Double = 1.0
    private var currentMuted: Bool = true
    private var currentVolume: Float = 0.0
    
    // Core shared player reference for stretched multi-monitor setups
    var sharedPlayer: AVPlayer?
    
    private init() {
        setupDisplayNotificationObservers()
    }
    
    private func setupDisplayNotificationObservers() {
        // Listen to display connection, resolution, or arrangement alterations
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleDisplayArrangementChanged()
            }
            .store(in: &cancellables)
    }
    
    /// Triggered when macOS screen configuration is modified.
    private func handleDisplayArrangementChanged() {
        print("Canvas DisplayManager: Monitor layout change detected.")
        rebuildWallpaperWindows()
    }
    
    /// Cleans up existing windows and regenerates wallpaper layouts matching the current display configuration.
    func rebuildWallpaperWindows() {
        // 1. Terminate existing window controllers gracefully
        for controller in windowControllers.values {
            controller.close()
        }
        windowControllers.removeAll()
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        // 2. Re-create windows for each active monitor
        for screen in screens {
            let controller = WallpaperWindowController(screen: screen)
            windowControllers[screen] = controller
            controller.showWindow(nil)
        }
        
        // 3. Re-apply current active wallpaper with correct mode mapping
        if let url = currentWallpaperURL {
            applyWallpaper(url: url, isVideo: currentIsVideo, speed: currentSpeed, muted: currentMuted, volume: currentVolume)
        }
    }
    
    /// Sets a new active wallpaper and constructs appropriate multi-monitor views.
    func applyWallpaper(url: URL, isVideo: Bool, speed: Double = 1.0, muted: Bool = true, volume: Float = 0.0) {
        self.currentWallpaperURL = url
        self.currentIsVideo = isVideo
        self.currentSpeed = speed
        self.currentMuted = muted
        self.currentVolume = volume
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        if layoutMode == .stretched && screens.count > 1 {
            applyStretchedWallpaper(url: url, isVideo: isVideo, speed: speed, muted: muted, volume: volume)
        } else {
            applyIndependentWallpaper(url: url, isVideo: isVideo, speed: speed, muted: muted, volume: volume)
        }
    }
    
    private func applyIndependentWallpaper(url: URL, isVideo: Bool, speed: Double, muted: Bool, volume: Float) {
        for (screen, controller) in windowControllers {
            let view: NSView
            if isVideo {
                view = CanvasVideoPlayerView(videoURL: url, speed: speed, muted: muted, volume: volume)
            } else {
                view = CanvasImageView(imageURL: url, speed: speed)
            }
            controller.transition(to: view)
        }
    }
    
    /// Stretches a single video or image canvas over multiple screens.
    /// Uses CoreAnimation contentsRect math to split visual output correctly.
    private func applyStretchedWallpaper(url: URL, isVideo: Bool, speed: Double, muted: Bool, volume: Float) {
        let screens = NSScreen.screens
        
        // 1. Calculate overall union bounding rect of all screens combined
        var unionRect = CGRect.null
        for screen in screens {
            unionRect = unionRect.union(screen.frame)
        }
        
        guard unionRect.width > 0 && unionRect.height > 0 else { return }
        
        // 2. For video, we can share a single AVPlayer instance and add separate AVPlayerLayers for each monitor
        // to avoid playback lag/audio stutter.
        var sharedPlayer: AVPlayer? = nil
        if isVideo {
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let item = AVPlayerItem(asset: asset)
            sharedPlayer = AVPlayer(playerItem: item)
            sharedPlayer?.preventsDisplaySleepDuringVideoPlayback = false
            sharedPlayer?.isMuted = muted
            sharedPlayer?.volume = volume
            
            // Loop completion listener
            sharedPlayer?.actionAtItemEnd = .none
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                sharedPlayer?.seek(to: CMTime.zero, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero) { finished in
                    if finished { sharedPlayer?.play() }
                }
            }
        }
        
        // 3. Set content parts for each screen
        for screen in screens {
            guard let controller = windowControllers[screen] else { continue }
            
            // Calculate normalized coordinate of this display in the layout canvas
            let screenFrame = screen.frame
            
            // CoreAnimation contentsRect coordinates have bottom-left as (0,0) in Cocoa
            let relativeX = (screenFrame.origin.x - unionRect.origin.x) / unionRect.width
            let relativeY = (screenFrame.origin.y - unionRect.origin.y) / unionRect.height
            let relativeW = screenFrame.width / unionRect.width
            let relativeH = screenFrame.height / unionRect.height
            
            let contentsRect = CGRect(x: relativeX, y: relativeY, width: relativeW, height: relativeH)
            
            if isVideo, let player = sharedPlayer {
                // Video Stretching using custom Layer
                let playerView = CanvasVideoPlayerView(videoURL: url, speed: speed, muted: muted, volume: volume)
                // Retrieve player layer and apply cropped contentsRect
                if let sublayers = playerView.layer?.sublayers {
                    for layer in sublayers {
                        if let avLayer = layer as? AVPlayerLayer {
                            // Link to same shared player
                            avLayer.player = player
                            avLayer.contentsRect = contentsRect
                        }
                    }
                }
                controller.transition(to: playerView)
            } else {
                // Image/GIF Stretching
                let imageView = CanvasImageView(imageURL: url, speed: speed)
                imageView.layer?.contentsRect = contentsRect
                controller.transition(to: imageView)
            }
        }
        
        // Start the shared player if it is a video
        self.sharedPlayer = sharedPlayer
        sharedPlayer?.play()
        if let speedFloat = Float(exactly: speed) {
            sharedPlayer?.rate = speedFloat
        }
    }
    
    func updateVolume(_ volume: Float) {
        self.currentVolume = volume
        sharedPlayer?.volume = volume
        for controller in windowControllers.values {
            if let window = controller.window, let contentView = window.contentView {
                for subview in contentView.subviews {
                    if let videoView = subview as? CanvasVideoPlayerView {
                        videoView.volume = volume
                    }
                }
            }
        }
    }
    
    func updateMute(_ muted: Bool) {
        self.currentMuted = muted
        sharedPlayer?.isMuted = muted
        for controller in windowControllers.values {
            if let window = controller.window, let contentView = window.contentView {
                for subview in contentView.subviews {
                    if let videoView = subview as? CanvasVideoPlayerView {
                        videoView.isMuted = muted
                    }
                }
            }
        }
    }
    
    func updateSpeed(_ speed: Double) {
        self.currentSpeed = speed
        if let speedFloat = Float(exactly: speed) {
            sharedPlayer?.rate = speedFloat
        }
        for controller in windowControllers.values {
            if let window = controller.window, let contentView = window.contentView {
                for subview in contentView.subviews {
                    if let videoView = subview as? CanvasVideoPlayerView {
                        videoView.playbackSpeed = speed
                    } else if let imageView = subview as? CanvasImageView {
                        imageView.playbackSpeed = speed
                    }
                }
            }
        }
    }
    
    func pause() {
        sharedPlayer?.pause()
        for controller in windowControllers.values {
            if let window = controller.window, let contentView = window.contentView {
                for subview in contentView.subviews {
                    if let videoView = subview as? CanvasVideoPlayerView {
                        videoView.pause()
                    } else if let imageView = subview as? CanvasImageView {
                        imageView.pause()
                    }
                }
            }
        }
    }
    
    func play() {
        sharedPlayer?.play()
        if let speedFloat = Float(exactly: currentSpeed) {
            sharedPlayer?.rate = speedFloat
        }
        for controller in windowControllers.values {
            if let window = controller.window, let contentView = window.contentView {
                for subview in contentView.subviews {
                    if let videoView = subview as? CanvasVideoPlayerView {
                        videoView.play()
                    } else if let imageView = subview as? CanvasImageView {
                        imageView.play()
                    }
                }
            }
        }
    }
    
    func throttle(lowPower: Bool) {
        if lowPower {
            sharedPlayer?.rate = Float(currentSpeed * 0.5)
        } else {
            if let speedFloat = Float(exactly: currentSpeed) {
                sharedPlayer?.rate = speedFloat
            }
        }
        for controller in windowControllers.values {
            if let window = controller.window, let contentView = window.contentView {
                for subview in contentView.subviews {
                    if let videoView = subview as? CanvasVideoPlayerView {
                        videoView.throttlePlayback(lowPowerMode: lowPower)
                    } else if let imageView = subview as? CanvasImageView {
                        imageView.throttlePlayback(lowPowerMode: lowPower)
                    }
                }
            }
        }
    }
    
    deinit {
        cancellables.removeAll()
    }
}
