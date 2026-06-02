import Cocoa
import ImageIO

/// A high-performance image and GIF rendering engine built directly on CoreAnimation.
/// Features custom speed adjustments for animated GIFs and zero CPU drawing overhead for static photos.
class CanvasImageView: NSView {
    
    private var imageSource: CGImageSource?
    private var frames: [(image: CGImage, delay: Double)] = []
    private var currentFrameIndex = 0
    private var animationTimer: Timer?
    private var isAnimated = false
    
    var playbackSpeed: Double = 1.0 {
        didSet {
            if isAnimated {
                restartAnimation()
            }
        }
    }
    
    init(imageURL: URL, speed: Double = 1.0) {
        self.playbackSpeed = speed
        super.init(frame: .zero)
        
        setupLayerBackedView()
        loadImage(url: imageURL)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayerBackedView() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
        self.layer?.contentsGravity = .resizeAspectFill
    }
    
    private func loadImage(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            handleLoadingFailure()
            return
        }
        
        self.imageSource = source
        let count = CGImageSourceGetCount(source)
        
        // 1. Check if the asset is an animated GIF
        if count > 1 {
            isAnimated = true
            parseGIF(source: source, count: count)
            startAnimation()
        } else {
            // 2. Static Photo: Single frame loaded directly into CoreAnimation layer
            isAnimated = false
            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                self.layer?.contents = cgImage
            } else {
                handleLoadingFailure()
            }
        }
    }
    
    private func parseGIF(source: CGImageSource, count: Int) {
        frames.removeAll()
        
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            
            // Extract frame delay
            var delay = 0.1 // Default fallback delay
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
               let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                
                if let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclampedDelay > 0 {
                    delay = unclampedDelay
                } else if let standardDelay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double, standardDelay > 0 {
                    delay = standardDelay
                }
            }
            
            // Prevent division-by-zero or extremely fast rendering loops
            if delay < 0.02 {
                delay = 0.1
            }
            
            frames.append((image: cgImage, delay: delay))
        }
    }
    
    private func startAnimation() {
        guard !frames.isEmpty else { return }
        currentFrameIndex = 0
        scheduleNextFrame()
    }
    
    private func scheduleNextFrame() {
        animationTimer?.invalidate()
        guard isAnimated, !frames.isEmpty else { return }
        
        let frame = frames[currentFrameIndex]
        self.layer?.contents = frame.image
        
        // Dynamic speed adaptation: Divide delay by playbackSpeed
        let adjustedDelay = frame.delay / playbackSpeed
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: adjustedDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentFrameIndex = (self.currentFrameIndex + 1) % self.frames.count
            self.scheduleNextFrame()
        }
    }
    
    private func restartAnimation() {
        animationTimer?.invalidate()
        scheduleNextFrame()
    }
    
    func pause() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    func play() {
        if isAnimated && animationTimer == nil {
            scheduleNextFrame()
        }
    }
    
    func throttlePlayback(lowPowerMode: Bool) {
        if lowPowerMode {
            // Half the speed of GIF animation in low power mode to save battery
            playbackSpeed = playbackSpeed * 0.5
        } else {
            // Reset to default (we can read this from state, but this acts as default toggle)
            playbackSpeed = 1.0
        }
    }
    
    private func handleLoadingFailure() {
        print("Canvas Image Engine Error: Failed to load image asset.")
        let error = NSError(domain: "com.canvas.image", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to load static photo or GIF asset"])
        NotificationCenter.default.post(name: .CanvasWallpaperPlaybackFailed, object: error)
    }
    
    deinit {
        animationTimer?.invalidate()
        frames.removeAll()
        imageSource = nil
    }
}
