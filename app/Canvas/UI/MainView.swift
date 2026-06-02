import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import AVFoundation

enum WallpaperTypeFilter: String, CaseIterable {
    case all = "All"
    case video = "Live Videos"
    case gif = "Animated GIFs"
    case image = "Static Photos"
    case imports = "Custom Imports"
    case favorites = "Favorites"
    
    var symbol: String {
        switch self {
        case .all: return "photo.stack.fill"
        case .video: return "video.fill"
        case .gif: return "arrow.counterclockwise.circle.fill"
        case .image: return "photo.fill"
        case .imports: return "square.and.arrow.down.fill"
        case .favorites: return "heart.fill"
        }
    }
}

/// The premium, clutter-free main library window for Canvas.
/// Built as an elegant, native, high-performance single-page grid catalog.
struct MainView: View {
    @StateObject private var catalog = WallpaperCatalog.shared
    @ObservedObject private var displayManager = DisplayManager.shared
    @ObservedObject private var cacheManager = CacheManager.shared
    
    @State private var selectedFilter: WallpaperTypeFilter = .all
    @State private var hoverAssetId: String? = nil
    
    @State private var volume: Double = 0.0
    @State private var speed: Double = 1.0
    @State private var isMuted: Bool = true
    
    @State private var showOnboarding = false
    @State private var showAppPreferences = false
    @State private var dockIconUpdateTrigger = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Elegant modern header panel
            HStack(spacing: 16) {
                // App Logo Title
                HStack(spacing: 8) {
                    if let appIcon = NSApplication.shared.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .cornerRadius(8)
                            .id(dockIconUpdateTrigger)
                    } else {
                        Image(systemName: "photo.stack.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    
                    Text("Canvas")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Inline Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search presets, imports...", text: $catalog.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                    
                    if !catalog.searchQuery.isEmpty {
                        Button {
                            catalog.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .frame(maxWidth: 240)
                
                // "+" Import Button
                Button {
                    importWallpaper()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Import")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Preferences Gear Button
                Button {
                    showAppPreferences = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Category navigation pill selectors (horizontal bar)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(WallpaperTypeFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: filter.symbol)
                                    .font(.system(size: 11))
                                Text(filter.rawValue)
                                    .font(.system(size: 12, weight: selectedFilter == filter ? .bold : .regular, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedFilter == filter ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.6))
                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                            .cornerRadius(18)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            
            Divider()
            
            // Grid of wallpaper cards
            if filteredList.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No wallpapers found")
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 20)], spacing: 24) {
                        ForEach(filteredList) { wallpaper in
                            LibraryGridItem(
                                wallpaper: wallpaper,
                                isHovered: hoverAssetId == wallpaper.id,
                                volume: $volume,
                                speed: $speed,
                                isMuted: $isMuted,
                                onApply: {
                                    applyWallpaper(wallpaper)
                                },
                                onDelete: {
                                    catalog.removeWallpaper(wallpaper)
                                }
                            )
                            .onHover { isHovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    hoverAssetId = isHovering ? wallpaper.id : nil
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(minWidth: 850, minHeight: 580)
        .sheet(isPresented: $showAppPreferences) {
            // Sleek sheet preferences modal
            VStack(spacing: 0) {
                HStack {
                    Text("Preferences")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button("Done") {
                        showAppPreferences = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(20)
                
                Divider()
                
                ScrollView {
                    SettingsView()
                        .padding(20)
                }
            }
            .frame(width: 480, height: 450)
        }
        .onAppear {
            syncPlaybackSettings()
            
            // Check first launch onboarding state
            let completed = UserDefaults.standard.bool(forKey: "com.canvas.onboarding.completed")
            if !completed {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingFlow(isPresented: $showOnboarding)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CanvasAppearanceDidChange"))) { _ in
            dockIconUpdateTrigger.toggle()
        }
    }
    
    private var filteredList: [Wallpaper] {
        let baseList = catalog.filteredWallpapers
        switch selectedFilter {
        case .all:
            return baseList
        case .video:
            return baseList.filter { $0.type == .video }
        case .gif:
            return baseList.filter { $0.type == .gif }
        case .image:
            return baseList.filter { $0.type == .image }
        case .imports:
            return baseList.filter { $0.isLocal }
        case .favorites:
            return baseList.filter { $0.isFavorite }
        }
    }
    
    private func applyWallpaper(_ wallpaper: Wallpaper) {
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
    
    private func syncPlaybackSettings() {
        self.volume = Double(UserDefaults.standard.float(forKey: "com.canvas.playback.volume"))
        self.speed = Double(UserDefaults.standard.float(forKey: "com.canvas.playback.speed"))
        if self.speed == 0 { self.speed = 1.0 }
        self.isMuted = UserDefaults.standard.bool(forKey: "com.canvas.playback.muted")
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
}

// MARK: - Premium Library Grid Item

struct LibraryGridItem: View {
    let wallpaper: Wallpaper
    let isHovered: Bool
    
    @Binding var volume: Double
    @Binding var speed: Double
    @Binding var isMuted: Bool
    
    let onApply: () -> Void
    let onDelete: () -> Void
    
    @State private var thumbnail: NSImage? = nil
    @State private var isLoading = false
    @State private var showAdjustmentPopover = false
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                // Card Background (Thumbnail or Loader or Placeholder)
                Group {
                    if let image = thumbnail {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                    } else if isLoading {
                        ProgressView()
                            .frame(height: 120)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlTextColor).opacity(0.04))
                            .frame(height: 120)
                            .overlay(
                                Image(systemName: wallpaper.type == .video ? "video.circle.fill" : (wallpaper.type == .gif ? "arrow.counterclockwise.circle.fill" : "photo.fill"))
                                    .font(.title)
                                    .foregroundColor(.accentColor)
                            )
                    }
                }
                .frame(height: 120)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                )
                
                // Hover Control Overlay
                if isHovered || showAdjustmentPopover {
                    ZStack {
                        // Blurred visual backdrop overlay
                        Color.black.opacity(0.35)
                            .cornerRadius(10)
                        
                        // Centered Apply Action Button
                        Button {
                            onApply()
                        } label: {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .buttonStyle(.plain)
                        
                        // Corner Actions
                        VStack {
                            HStack {
                                // Favorite Toggle
                                Button {
                                    WallpaperCatalog.shared.toggleFavorite(for: wallpaper)
                                } label: {
                                    Image(systemName: wallpaper.isFavorite ? "heart.fill" : "heart")
                                        .foregroundColor(wallpaper.isFavorite ? .red : .white)
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(6)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                                
                                // Settings Gear button for adjustment popover
                                Button {
                                    showAdjustmentPopover = true
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundColor(.white)
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(6)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showAdjustmentPopover, arrowEdge: .trailing) {
                                    PopoverAdjustmentsView(
                                        wallpaper: wallpaper,
                                        volume: $volume,
                                        speed: $speed,
                                        isMuted: $isMuted
                                    )
                                }
                            }
                            .padding(6)
                            
                            Spacer()
                            
                            HStack {
                                Spacer()
                                
                                // Delete trash icon for custom wallpapers
                                if wallpaper.isLocal {
                                    Button {
                                        onDelete()
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .foregroundColor(.red)
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(6)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 120)
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 6 : 2, x: 0, y: isHovered ? 3 : 1)
            
            // Metadata below the card (clean title & type badge)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(wallpaper.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Simple small type badge
                    Text(wallpaper.type.rawValue)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(3)
                }
                
                Text(wallpaper.creator)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .scaleEffect(isHovered ? 1.03 : 1.0)
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
            // Asynchronously extract frame using AVAssetImageGenerator
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                
                // Get frame at 1.0 seconds
                let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 320, height: 180))
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
            // Load static image or GIF
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

// MARK: - Floating Adjustments Popover View

struct PopoverAdjustmentsView: View {
    let wallpaper: Wallpaper
    @Binding var volume: Double
    @Binding var speed: Double
    @Binding var isMuted: Bool
    
    @State private var customTitle: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if wallpaper.creator == "Custom Import" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rename Wallpaper")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        TextField("Enter name...", text: $customTitle)
                            .textFieldStyle(.plain)
                            .padding(6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .onSubmit {
                                saveTitle()
                            }
                        
                        Button {
                            saveTitle()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onAppear {
                    customTitle = wallpaper.title
                }
                
                Divider()
            }
            
            Text("Adjust Playback")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.bottom, 2)
            
            // Speed Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speed: \(String(format: "%.1f", speed))x")
                        .font(.system(size: 11))
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
                        .font(.system(size: 11))
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
        .padding(16)
        .frame(width: 220)
    }
    
    private func saveTitle() {
        let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            WallpaperCatalog.shared.renameWallpaper(wallpaper, to: trimmed)
        }
    }
}
