import Cocoa
import Combine

/// Monitors system-wide states to pause, throttle, or resume wallpaper playback.
/// Handles screensaver, low-power mode, full-screen apps, games, and system sleep/wake.
class StateMonitor: ObservableObject {
    
    static let shared = StateMonitor()
    
    @Published var isSystemSleeping = false
    @Published var isScreensaverActive = false
    @Published var isLowPowerModeActive = false
    @Published var isFullscreenAppActive = false
    @Published var isGameActive = false
    
    private var cancellables = Set<AnyCancellable>()
    private var checkTimer: Timer?
    
    private init() {
        setupSleepObservers()
        setupPowerStateObservers()
        setupScreensaverObservers()
        setupWorkspaceObservers()
        
        // Start background polling for fullscreen applications (sandbox-safe bounds checking)
        startStatePolling()
    }
    
    private func setupSleepObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        wsCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                print("Canvas StateMonitor: System going to sleep. Pausing.")
                self?.isSystemSleeping = true
                self?.evaluatePlaybackState()
            }
            .store(in: &cancellables)
        
        wsCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                print("Canvas StateMonitor: System woke up. Resuming.")
                self?.isSystemSleeping = false
                self?.evaluatePlaybackState()
            }
            .store(in: &cancellables)
    }
    
    private func setupPowerStateObservers() {
        // Init state
        isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
                print("Canvas StateMonitor: Low Power Mode changed -> \(lpm)")
                self?.isLowPowerModeActive = lpm
                self?.evaluateThrottlingState()
            }
            .store(in: &cancellables)
    }
    
    private func setupScreensaverObservers() {
        let distCenter = DistributedNotificationCenter.default()
        
        distCenter.publisher(for: Notification.Name("com.apple.screensaver.didstart"))
            .sink { [weak self] _ in
                print("Canvas StateMonitor: Screensaver started. Pausing.")
                self?.isScreensaverActive = true
                self?.evaluatePlaybackState()
            }
            .store(in: &cancellables)
        
        distCenter.publisher(for: Notification.Name("com.apple.screensaver.didstop"))
            .sink { [weak self] _ in
                print("Canvas StateMonitor: Screensaver stopped. Resuming.")
                self?.isScreensaverActive = false
                self?.evaluatePlaybackState()
            }
            .store(in: &cancellables)
    }
    
    private func setupWorkspaceObservers() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                self?.checkActiveWindowStatus()
            }
            .store(in: &cancellables)
    }
    
    private func startStatePolling() {
        // Poll every 3 seconds to check active window dimensions and process states.
        // Extremely lightweight, executes on background queue.
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkActiveWindowStatus()
        }
    }
    
    /// Queries the active frontmost window size and application category using standard macOS API.
    /// Safely fits Sandbox guidelines without asking for special user Accessibility access.
    private func checkActiveWindowStatus() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        
        // Skip check if the frontmost app is Canvas or Finder
        let bundleId = frontmostApp.bundleIdentifier ?? ""
        if bundleId == "com.canvas.CanvasApp" || bundleId == "com.apple.finder" {
            if isFullscreenAppActive || isGameActive {
                isFullscreenAppActive = false
                isGameActive = false
                evaluatePlaybackState()
            }
            return
        }
        
        // Check game category from process names
        let gameActive = detectGame(app: frontmostApp)
        
        // Retrieve open window information to check for full-screen overlapping
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        
        var fullscreenDetected = false
        let screens = NSScreen.screens
        
        // Find if the frontmost application has a window matching any monitor size exactly
        for windowInfo in windowListInfo {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  windowPID == frontmostApp.processIdentifier,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            // Check if window bounds overlap or match any connected monitor bounds exactly
            for screen in screens {
                let screenFrame = screen.frame
                // Sometimes fullscreen windows extend slightly past screen bounds or match exactly.
                // Allow a small padding of 5 points.
                if abs(bounds.width - screenFrame.width) < 5 && abs(bounds.height - screenFrame.height) < 5 {
                    fullscreenDetected = true
                    break
                }
            }
            
            if fullscreenDetected { break }
        }
        
        // If state changed, update and evaluate
        if fullscreenDetected != isFullscreenAppActive || gameActive != isGameActive {
            print("Canvas StateMonitor: Fullscreen active: \(fullscreenDetected), Game active: \(gameActive)")
            self.isFullscreenAppActive = fullscreenDetected
            self.isGameActive = gameActive
            evaluatePlaybackState()
        }
    }
    
    private func detectGame(app: NSRunningApplication) -> Bool {
        let name = app.localizedName?.lowercased() ?? ""
        let bid = app.bundleIdentifier?.lowercased() ?? ""
        
        // Core list of game platforms and processes
        let gameIndicators = [
            "steam", "epicgames", "origin", "battlenet", "gog", "retroarch",
            "minecraft", "unity", "unreal", "godot", "playstation", "geforce",
            "dolphin", "pcsx2", "rpcs3", "citra", "yuzu", "cemu", "openemu"
        ]
        
        for indicator in gameIndicators {
            if name.contains(indicator) || bid.contains(indicator) {
                return true
            }
        }
        
        return false
    }
    
    /// Evaluates if wallpaper playback should be paused to preserve GPU/CPU.
    private func evaluatePlaybackState() {
        let shouldPause = isSystemSleeping || isScreensaverActive || isFullscreenAppActive || isGameActive
        
        DispatchQueue.main.async {
            if shouldPause {
                DisplayManager.shared.pause()
            } else {
                DisplayManager.shared.play()
            }
        }
    }
    
    /// Evaluates if wallpaper playback should be throttled (Low Power Mode).
    private func evaluateThrottlingState() {
        DispatchQueue.main.async {
            DisplayManager.shared.throttle(lowPower: self.isLowPowerModeActive)
        }
    }
    
    deinit {
        cancellables.removeAll()
        checkTimer?.invalidate()
    }
}
