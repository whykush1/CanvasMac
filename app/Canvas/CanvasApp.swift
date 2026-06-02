import SwiftUI
import Cocoa
import Sparkle

@main
struct CanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("Canvas", id: "main") {
            MainView()
                .frame(minWidth: 950, minHeight: 650)
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
        
        // 8. Apply default or last active wallpaper if saved
        applyDefaultWallpaper()
        
        // 9. Observe appearance changes dynamically to update Dock icon
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new, .initial]) { [weak self] _, _ in
            self?.appearanceDidChange(Notification(name: NSNotification.Name("CanvasAppearanceDidChange")))
        }
        
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
        
        print("Canvas App: Loaded all engines successfully.")
    }
    
    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Match the main library window and bind delegate
        let title = window.title
        
        if title == "Canvas" && window.styleMask.contains(.titled) && window.delegate == nil {
            window.delegate = self
            print("Canvas App: Dynamically bound delegate to active window: \(title)")
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When Dock icon is clicked, bring window back from hidden state
        showMainWindow()
        return true
    }
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Intercept close button and hide window instead of destroying it
        sender.orderOut(nil)
        return false // Prevents the window from closing and being destroyed
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
        // Search through all windows (including hidden ones in the background)
        if let window = NSApp.windows.first(where: { $0.title == "Canvas" && $0.styleMask.contains(.titled) }) {
            if window.delegate == nil {
                window.delegate = self
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("Canvas App: Restored and focused library window.")
        } else {
            // Fallback: If completely empty, try sending re-open commands to SwiftUI
            NSApp.sendAction(Selector(("showMainWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
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
