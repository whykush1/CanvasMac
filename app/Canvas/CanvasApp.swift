import SwiftUI
import Cocoa
import Sparkle

@main
struct CanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("Canvas", id: "main") {
            MainView()
        }
        .windowStyle(.titleBar) // Configures standard native macOS window titlebar
        
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var updaterController: SPUStandardUpdaterController?
    var appearanceObservation: NSKeyValueObservation?
    weak var trackedMainWindow: NSWindow?
    var windowProxy: WindowDelegateProxy?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Enforce single instance
        enforceSingleInstance()
        
        // 2. Initialize Sparkle Auto-Updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        // 3. Initialize Display Management Windows
        DisplayManager.shared.rebuildWallpaperWindows()
        
        // 4. Initialize Core State Monitors & Folder monitors
        _ = StateMonitor.shared
        _ = FolderMonitor.shared
        
        // 5. Establish Menu Bar Status Popover
        setupStatusItem()
        
        // 6. Monitor Cache Downloads to Update Dock Badge Dynamically
        setupDockBadgeMonitoring()
        
        // 7. Register Dynamic Key Window Observer
        // This is 100% race-condition free. The moment SwiftUI instantiates the window
        // and displays it, we capture it and bind the delegate instantly.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onboardingFinished(_:)),
            name: NSNotification.Name("CanvasOnboardingFinished"),
            object: nil
        )
        
        // 8. Apply default or last active wallpaper if saved
        applyDefaultWallpaper()
        
        // 9. Observe appearance changes dynamically to update Dock icon
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new, .initial]) { [weak self] _, _ in
            self?.appearanceDidChange(Notification(name: NSNotification.Name("CanvasAppearanceDidChange")))
        }
        // 10. Let SwiftUI handle window creation natively
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceDidChange(_:)),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        
        updateDockIconForAppearance()
        
        // 11. Run initial window check in case it already spawned
        DispatchQueue.main.async {
            self.configureInitialWindowIfNeeded()
        }
        
        print("Canvas App: Loaded all engines successfully.")
    }
    
    private func isMainLibraryWindow(_ window: NSWindow) -> Bool {
        let isTitled = window.styleMask.contains(.titled)
        let isNormalLayer = window.level == .normal
        let isWallpaper = window.className.contains("Wallpaper") || window.title.contains("Wallpaper")
        let isMainTitle = window.title == "Canvas"
        return isTitled && isNormalLayer && !isWallpaper && isMainTitle
    }
    
    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        if isMainLibraryWindow(window) {
            if self.trackedMainWindow == nil {
                self.trackedMainWindow = window
                print("Canvas App: Dynamically bound delegate to active main window.")
                
                // Set proxy delegate cleanly to preserve SwiftUI internals
                if !(window.delegate is WindowDelegateProxy) {
                    let proxy = WindowDelegateProxy(originalDelegate: window.delegate, appDelegate: self)
                    self.windowProxy = proxy
                    window.delegate = proxy
                }
                
                // Premium: Hijack standard close button to cleanly hide (orderOut) instead of destroying or minimizing
                if let closeButton = window.standardWindowButton(.closeButton) {
                    closeButton.target = self
                    closeButton.action = #selector(closeButtonTapped(_:))
                }
                
                configureWindowDimensions(window)
            }
        }
    }
    
    private func configureWindowDimensions(_ window: NSWindow) {
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_v2_completed")
        if !onboardingCompleted {
            // Style window as non-resizable for onboarding
            window.styleMask.remove(.resizable)
            window.collectionBehavior.insert(.fullScreenNone)
            
            let newWidth: CGFloat = 550
            let newHeight: CGFloat = 480
            
            // Centered perfectly on screen
            DispatchQueue.main.async {
                let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
                if let screenFrame = screen?.visibleFrame {
                    let newX = screenFrame.minX + (screenFrame.width - newWidth) / 2
                    let newY = screenFrame.minY + (screenFrame.height - newHeight) / 2
                    let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
                    window.setFrame(newFrame, display: true, animate: false)
                } else {
                    window.setContentSize(NSSize(width: newWidth, height: newHeight))
                    window.center()
                }
                
                window.minSize = NSSize(width: 550, height: 480)
                window.maxSize = NSSize(width: 550, height: 480)
            }
        } else {
            // Ensure standard resizable properties are restored
            window.styleMask.insert(.resizable)
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenPrimary)
            
            let newWidth: CGFloat = 950
            let newHeight: CGFloat = 650
            
            // Center standard window
            DispatchQueue.main.async {
                let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
                if let screenFrame = screen?.visibleFrame {
                    let newX = screenFrame.minX + (screenFrame.width - newWidth) / 2
                    let newY = screenFrame.minY + (screenFrame.height - newHeight) / 2
                    let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
                    window.setFrame(newFrame, display: true, animate: false)
                } else {
                    window.setContentSize(NSSize(width: newWidth, height: newHeight))
                    window.center()
                }
                
                window.minSize = NSSize(width: 950, height: 650)
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }
    
    @objc func closeButtonTapped(_ sender: AnyObject?) {
        if let button = sender as? NSButton, let window = button.window, isMainLibraryWindow(window) {
            window.orderOut(nil)
            print("Canvas App: Close button click intercepted. Main window hidden cleanly.")
        } else {
            trackedMainWindow?.orderOut(nil)
            print("Canvas App: Close button click intercepted. Tracked main window hidden cleanly.")
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true 
    }
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Intercept close events strictly for the main library window and hide cleanly
        if isMainLibraryWindow(sender) {
            sender.orderOut(nil)
            print("Canvas App: Delegate close event intercepted. Main window hidden cleanly.")
            return false // Prevents destruction of the main window
        }
        return true // Allows Settings/Preferences and helper windows to close normally!
    }
    
    private func enforceSingleInstance() {
        let runningApps = NSWorkspace.shared.runningApplications
        let currentApp = NSRunningApplication.current
        
        let duplicates = runningApps.filter { app in
            guard app.processIdentifier != currentApp.processIdentifier else { return false }
            
            // 1. Match on Bundle Identifier (most standard)
            if let currentBid = currentApp.bundleIdentifier, let appBid = app.bundleIdentifier, currentBid == appBid {
                return true
            }
            
            // 2. Match on Localized Name ("Canvas")
            if let currentName = currentApp.localizedName, let appName = app.localizedName, currentName == appName {
                return true
            }
            
            // 3. Match on Executable Binary Name ("Canvas")
            if let currentExec = currentApp.executableURL?.lastPathComponent,
               let appExec = app.executableURL?.lastPathComponent,
               currentExec == appExec {
                return true
            }
            
            return false
        }
        
        if !duplicates.isEmpty {
            if let existingApp = duplicates.first {
                // Modern API replacing deprecated activateIgnoringOtherApps
                existingApp.activate()
            }
            exit(0)
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Canvas")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Setup SwiftUI Menu Popover
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        popover.behavior = .transient
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
    
    private func setupDockBadgeMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let active = CacheManager.shared.activeDownloads.values
            if let firstDownload = active.first {
                let percent = Int(firstDownload.progress * 100)
                DispatchQueue.main.async {
                    NSApp.dockTile.badgeLabel = "\(percent)%"
                }
            } else {
                DispatchQueue.main.async {
                    NSApp.dockTile.badgeLabel = nil
                }
            }
        }
    }
    
    @objc func showMainWindow() {
        let window = trackedMainWindow ?? NSApp.windows.first(where: { isMainLibraryWindow($0) })
        
        if let window = window {
            if !(window.delegate is WindowDelegateProxy) {
                let proxy = WindowDelegateProxy(originalDelegate: window.delegate, appDelegate: self)
                self.windowProxy = proxy
                window.delegate = proxy
            }
            // De-minimize if it was minimized to the Dock
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            // Order front if it was hidden (ordered out)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("Canvas App: Restored and ordered front library window.")
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func onboardingFinished(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let window = self.trackedMainWindow ?? NSApp.windows.first(where: { self.isMainLibraryWindow($0) }) else { return }
            
            // Restore standard resizability and fullscreen controls
            window.styleMask.insert(.resizable)
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenPrimary)
            
            // Perform centering layout on the next tick to avoid AppKit style-mask race conditions
            DispatchQueue.main.async {
                let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
                if let screenFrame = screen?.visibleFrame {
                    let newWidth: CGFloat = 950
                    let newHeight: CGFloat = 650
                    let newX = screenFrame.minX + (screenFrame.width - newWidth) / 2
                    let newY = screenFrame.minY + (screenFrame.height - newHeight) / 2
                    let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
                    
                    window.setFrame(newFrame, display: true, animate: true)
                } else {
                    let newWidth: CGFloat = 950
                    let newHeight: CGFloat = 650
                    window.setContentSize(NSSize(width: newWidth, height: newHeight))
                    window.center()
                }
                
                window.minSize = NSSize(width: 950, height: 650)
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }
    
    private func configureInitialWindowIfNeeded() {
        let window = NSApp.windows.first(where: { isMainLibraryWindow($0) })
        
        if let window = window {
            if self.trackedMainWindow == nil {
                self.trackedMainWindow = window
                print("Canvas App: Configured initial window on startup.")
                
                // Set proxy delegate cleanly to preserve SwiftUI internals
                if !(window.delegate is WindowDelegateProxy) {
                    let proxy = WindowDelegateProxy(originalDelegate: window.delegate, appDelegate: self)
                    self.windowProxy = proxy
                    window.delegate = proxy
                }
                
                // Hijack close button
                if let closeButton = window.standardWindowButton(.closeButton) {
                    closeButton.target = self
                    closeButton.action = #selector(closeButtonTapped(_:))
                }
                
                configureWindowDimensions(window)
            }
        }
    }
    
    private func applyDefaultWallpaper() {
        let catalog = WallpaperCatalog.shared
        if let firstPreset = catalog.wallpapers.first, let url = firstPreset.resolvedURL {
            let volume = UserDefaults.standard.float(forKey: "com.canvas.playback.volume")
            let speed = UserDefaults.standard.double(forKey: "com.canvas.playback.speed")
            let muted = UserDefaults.standard.bool(forKey: "com.canvas.playback.muted")
            
            DisplayManager.shared.applyWallpaper(
                url: url,
                isVideo: firstPreset.type == .video,
                speed: speed == 0 ? 1.0 : speed,
                muted: muted,
                volume: volume
            )
        }
    }
    
    private func updateDockIconForAppearance() {
        // Query the system's global "Icon & widget style" preference.
        // It is stored under the global domain key "AppleIconAppearanceTheme".
        // In macOS Sequoia/Tahoe:
        // - "Dark" style sets AppleIconAppearanceTheme = "Dark"
        // - "Clear" style sets AppleIconAppearanceTheme = "Clear"
        // - "Default" style sets AppleIconAppearanceTheme = "Default" or nil
        let iconTheme = CFPreferencesCopyAppValue("AppleIconAppearanceTheme" as CFString, kCFPreferencesAnyApplication) as? String
        
        let imageName: String
        if iconTheme == "Dark" {
            imageName = "AppIconDark"
        } else if iconTheme == "Clear" {
            imageName = "AppIconLight" // "Clear" icon in our Asset Catalog
        } else {
            imageName = "NSApplicationIcon" // The system's standard application icon (Default)
        }
        
        // Use NSApplicationIcon system name or load custom image from assets
        let customIcon: NSImage?
        if imageName == "NSApplicationIcon" {
            customIcon = NSImage(named: imageName) ?? NSImage(named: "AppIcon")
        } else {
            customIcon = NSImage(named: imageName)
        }
        
        if let icon = customIcon {
            NSApplication.shared.applicationIconImage = icon
            print("Canvas App: Dynamically updated Dock icon to \(imageName) appearance based on system setting (AppleIconAppearanceTheme: \(iconTheme ?? "nil")).")
        }
    }
    
    @objc func appearanceDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.updateDockIconForAppearance()
            // Post notification to update SwiftUI views if necessary
            NotificationCenter.default.post(name: NSNotification.Name("CanvasAppearanceDidChange"), object: nil)
        }
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}

/// A specialized NSWindowDelegate proxy that intercepts window close requests for the main window
/// while cleanly forwarding all other delegate selector messages directly to SwiftUI's internal delegate.
class WindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var originalDelegate: NSWindowDelegate?
    weak var appDelegate: AppDelegate?
    
    init(originalDelegate: NSWindowDelegate?, appDelegate: AppDelegate?) {
        self.originalDelegate = originalDelegate
        self.appDelegate = appDelegate
        super.init()
    }
    
    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(windowShouldClose(_:)) {
            return true
        }
        return super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }
    
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if aSelector == #selector(windowShouldClose(_:)) {
            return nil
        }
        if let original = originalDelegate, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let appDelegate = appDelegate {
            return appDelegate.windowShouldClose(sender)
        }
        return originalDelegate?.windowShouldClose?(sender) ?? true
    }
}
