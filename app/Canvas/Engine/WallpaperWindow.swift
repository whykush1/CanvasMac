import Cocoa
import SwiftUI

/// A custom NSWindow subclass that sits directly behind desktop icons,
/// ignores user mouse interaction (allowing click-through to desktop),
/// and remains visible across all virtual spaces.
class CanvasWallpaperWindow: NSWindow {
    
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // 1. Placement: Position it exactly below desktop icons
        // Using CGWindowLevelForKey(.desktopIconWindow) - 1 guarantees it sits behind the desktop icon layer.
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        
        // 2. Spaces Behavior: Join all virtual desktops and remain stationary during swipe transitions
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        // 3. Look and Feel: Transparent background, no shadows
        self.backgroundColor = .black
        self.hasShadow = false
        self.isOpaque = true
        
        // 4. Interaction: Completely ignore mouse and keyboard events to allow clicking desktop icons
        self.ignoresMouseEvents = true
        
        // 5. Visibility: Ensure it doesn't show up in window listings, Mission Control, or Command-Tab
        self.hidesOnDeactivate = false
    }
    
    // Disable standard focusing mechanisms
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages a single wallpaper window for a specific display screen.
class WallpaperWindowController: NSWindowController {
    
    let screen: NSScreen
    private var currentEngineView: NSView?
    
    init(screen: NSScreen) {
        self.screen = screen
        let window = CanvasWallpaperWindow(screen: screen)
        super.init(window: window)
        
        // Automatically stretch to screen bounds
        window.setFrame(screen.frame, display: true)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Switches the content view of the wallpaper window with a smooth cross-fade transition.
    /// - Parameter newView: The new NSView representing the wallpaper (video or image).
    func transition(to newView: NSView, duration: TimeInterval = 0.5) {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        // Match bounds
        newView.frame = contentView.bounds
        newView.autoresizingMask = [.width, .height]
        newView.alphaValue = 0.0
        
        contentView.addSubview(newView)
        
        let oldView = self.currentEngineView
        self.currentEngineView = newView
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            // Fade in new view
            newView.animator().alphaValue = 1.0
            
            // Fade out old view if exists
            oldView?.animator().alphaValue = 0.0
        }, completionHandler: {
            // Cleanup the old view
            oldView?.removeFromSuperview()
        })
    }
    
    /// Updates the window size and frame when the display configuration changes.
    func updateFrame() {
        guard let window = self.window else { return }
        // Set frame asynchronously to prevent UI blocks during display layout locks
        DispatchQueue.main.async {
            window.setFrame(self.screen.frame, display: true)
            if let currentView = self.currentEngineView {
                currentView.frame = window.contentView?.bounds ?? self.screen.frame
            }
        }
    }
}
