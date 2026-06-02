import SwiftUI
import Cocoa
import AVFoundation

/// A beautiful, clutter-free menu-bar extra interface anchored to the status bar.
/// Displays the active wallpaper visual preview, playback controls (speed/volume), and quick utility actions.
struct MenuBarView: View {
    @ObservedObject var catalog = WallpaperCatalog.shared
    @ObservedObject var displayManager = DisplayManager.shared
    
    @State private var volume: Double = 0.0
    @State private var speed: Double = 1.0
    @State private var isMuted: Bool = true
    
    var activeWallpaper: Wallpaper? {
        guard let url = displayManager.currentWallpaperURL else { return nil }
        return catalog.wallpapers.first(where: { $0.resolvedURL?.path == url.path })
    }
    
    var body: some View {
        VStack(spacing: 14) {
            // Active Wallpaper Preview Card
            if let wallpaper = activeWallpaper {
                ActiveWallpaperPreviewCard(wallpaper: wallpaper)
            } else {
                // Fallback placeholder when no wallpaper is selected
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlTextColor).opacity(0.04))
                    .frame(height: 140)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.stack")
                                .font(.title)
                                .foregroundColor(.accentColor)
                            Text("No Active Wallpaper")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    )
            }
            
            // Slider Controls (Volume & Speed)
            VStack(spacing: 12) {
                // Speed Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "gauge.with.needle.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 11))
                        Text("Speed: \(String(format: "%.1f", speed))x")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                        .onChange(of: speed) { oldValue, newValue in
                            UserDefaults.standard.set(Float(newValue), forKey: "com.canvas.playback.speed")
                            DisplayManager.shared.updateSpeed(newValue)
                        }
                }
                
                // Volume Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button {
                            isMuted.toggle()
                            UserDefaults.standard.set(isMuted, forKey: "com.canvas.playback.muted")
                            DisplayManager.shared.updateMute(isMuted)
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        
                        Text("Volume")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Slider(value: $volume, in: 0.0...1.0)
                        .disabled(isMuted)
                        .onChange(of: volume) { oldValue, newValue in
                            UserDefaults.standard.set(Float(newValue), forKey: "com.canvas.playback.volume")
                            DisplayManager.shared.updateVolume(Float(newValue))
                        }
                }
            }
            .padding(.horizontal, 4)
            
            Divider()
            
            // Bottom Tactical Quick Actions Row
            HStack(spacing: 16) {
                // 1. Skip / Next Wallpaper Button
                Button {
                    playNextWallpaper()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("Next")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Cycle to next wallpaper")
                
                Spacer()
                
                // 2. Quick Ingest / "+" Import Button
                Button {
                    importWallpaper()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Import Custom Wallpaper")
                
                // 3. Open Preferences Gear
                Button {
                    openPreferences()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Preferences")
                
                // 4. Open Main Dashboard Window
                Button {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.showMainWindow()
                    }
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .padding(6)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open Main Library")
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onAppear {
            syncPlaybackSettings()
        }
    }
    
    private func playWallpaper(_ wallpaper: Wallpaper) {
        if let url = wallpaper.resolvedURL {
            displayManager.applyWallpaper(
                url: url,
                isVideo: wallpaper.type == .video,
                speed: speed,
                muted: isMuted,
                volume: Float(volume)
            )
            CacheManager.shared.recordAccess(forURL: url)
        }
    }
    
    private func playNextWallpaper() {
        let wallpapers = catalog.wallpapers
        guard !wallpapers.isEmpty else { return }
        
        let currentIndex = wallpapers.firstIndex(where: { $0.resolvedURL?.path == displayManager.currentWallpaperURL?.path }) ?? -1
        let nextIndex = (currentIndex + 1) % wallpapers.count
        let nextWallpaper = wallpapers[nextIndex]
        
        playWallpaper(nextWallpaper)
    }
    
    private func importWallpaper() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie, .gif, .png, .jpeg, .heic]
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    catalog.addCustomWallpaper(at: url)
                }
            }
        }
    }
    
    private func syncPlaybackSettings() {
        self.volume = Double(UserDefaults.standard.float(forKey: "com.canvas.playback.volume"))
        self.speed = Double(UserDefaults.standard.float(forKey: "com.canvas.playback.speed"))
        if self.speed == 0 { self.speed = 1.0 }
        self.isMuted = UserDefaults.standard.bool(forKey: "com.canvas.playback.muted")
    }
    
    private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate()
    }
}

// MARK: - Active Wallpaper Preview Card

struct ActiveWallpaperPreviewCard: View {
    let wallpaper: Wallpaper
    @State private var thumbnail: NSImage? = nil
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image = thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 268, height: 140)
                        .clipped()
                } else if isLoading {
                    ProgressView()
                        .frame(width: 268, height: 140)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlTextColor).opacity(0.04))
                        .frame(width: 268, height: 140)
                }
            }
            .frame(width: 268, height: 140)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(wallpaper.creator)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: wallpaper) { oldValue, newValue in
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        thumbnail = nil
        isLoading = true
        
        guard let url = wallpaper.resolvedURL else {
            isLoading = false
            return
        }
        
        if wallpaper.type == .video {
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                
                let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 268, height: 140))
                    DispatchQueue.main.async {
                        self.thumbnail = nsImage
                        self.isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                if url.isFileURL {
                    BookmarkManager.shared.withSecurityAccess(to: url) { securedURL in
                        if let data = try? Data(contentsOf: securedURL), let nsImage = NSImage(data: data) {
                            DispatchQueue.main.async {
                                self.thumbnail = nsImage
                                self.isLoading = false
                            }
                        } else if let nsImage = NSImage(contentsOf: securedURL) {
                            DispatchQueue.main.async {
                                self.thumbnail = nsImage
                                self.isLoading = false
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.isLoading = false
                            }
                        }
                    }
                } else {
                    if let data = try? Data(contentsOf: url), let nsImage = NSImage(data: data) {
                        DispatchQueue.main.async {
                            self.thumbnail = nsImage
                            self.isLoading = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.isLoading = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Core Visual Effect (Glassmorphism helper)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
