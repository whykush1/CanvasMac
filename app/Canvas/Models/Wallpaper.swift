import Foundation

enum WallpaperType: String, Codable, CaseIterable {
    case video = "Video"
    case gif   = "GIF"
    case image = "Image"
}

struct Wallpaper: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    let creator: String
    let type: WallpaperType
    let url: String // Can be a local file path or a remote web URL
    var isFavorite: Bool
    let resolution: String
    
    var isLocal: Bool {
        return url.hasPrefix("/") || url.hasPrefix("file://")
    }
    
    var resolvedURL: URL? {
        if isLocal {
            // Standard path formatting
            let cleanPath = url.replacingOccurrences(of: "file://", with: "")
            return URL(fileURLWithPath: cleanPath)
        } else {
            return URL(string: url)
        }
    }
}

/// In-memory catalog database managing active wallpapers, favorites, and search indices.
class WallpaperCatalog: ObservableObject {
    
    static let shared = WallpaperCatalog()
    
    @Published var wallpapers: [Wallpaper] = []
    @Published var searchQuery: String = ""
    
    private let favoritesRegistryKey = "com.canvas.favorites.registry"
    
    private init() {
        loadCatalog()
    }
    
    private func copyDefaultWallpapersFromWorkspace() {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let wallpapersDir = appSupportDir.appendingPathComponent("Wallpapers", isDirectory: true)
        
        try? fileManager.createDirectory(at: wallpapersDir, withIntermediateDirectories: true, attributes: nil)
        
        // Locate inside the Sandboxed App Bundle Resources directly
        guard let resourceURL = Bundle.main.resourceURL else {
            print("Canvas Catalog: App Bundle Resources URL not found.")
            return
        }
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: resourceURL.path) else {
            print("Canvas Catalog: Bundle resources directory not accessible.")
            return
        }
        
        for file in files {
            if file.hasSuffix(".mp4") {
                let sourceURL = resourceURL.appendingPathComponent(file)
                let destURL = wallpapersDir.appendingPathComponent(file)
                
                if !fileManager.fileExists(atPath: destURL.path) {
                    do {
                        try fileManager.copyItem(at: sourceURL, to: destURL)
                        print("Canvas Catalog: Copied default wallpaper \(file) into Sandboxed application folder.")
                    } catch {
                        print("Canvas Catalog Error: Failed to copy \(file): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func loadCatalog() {
        var items: [Wallpaper] = []
        
        // 1. Copy default local wallpapers from the workspace if not already present in sandbox
        copyDefaultWallpapersFromWorkspace()
        
        // 2. Load custom user-ingested and copied default assets from the Sandboxed folder
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let wallpapersDir = appSupportDir.appendingPathComponent("Wallpapers", isDirectory: true)
        
        if let files = try? FileManager.default.contentsOfDirectory(at: wallpapersDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in files {
                let ext = fileURL.pathExtension.lowercased()
                let isVideo = ["mp4", "mov", "m4v"].contains(ext)
                let isGif = ext == "gif"
                
                let fileName = fileURL.deletingPathExtension().lastPathComponent
                
                // Identify default presets vs custom imports
                let defaultPresets = ["blue-particles", "cave-fireflies", "purple-galaxy", "purple-particles", "retro-cubes", "spectrum"]
                let isDefaultPreset = defaultPresets.contains(fileName)
                
                // Load custom titles if renamed by user, otherwise format default
                let customTitles = UserDefaults.standard.dictionary(forKey: "com.canvas.custom.titles") as? [String: String] ?? [:]
                let title = customTitles[fileURL.path] ?? (isDefaultPreset
                    ? fileName.replacingOccurrences(of: "-", with: " ").capitalized
                    : fileName.capitalized)
                
                let wallpaper = Wallpaper(
                    id: fileURL.path,
                    title: title,
                    creator: isDefaultPreset ? "Canvas Preset" : "Custom Import",
                    type: isVideo ? .video : (isGif ? .gif : .image),
                    url: fileURL.path,
                    isFavorite: false,
                    resolution: isVideo ? "4K Live Video" : "Static Image"
                )
                items.append(wallpaper)
            }
        }
        
        // 3. Restore Favorite Flags from Registry
        let favorites = UserDefaults.standard.stringArray(forKey: favoritesRegistryKey) ?? []
        for i in 0..<items.count {
            if favorites.contains(items[i].id) {
                items[i].isFavorite = true
            }
        }
        
        self.wallpapers = items
    }
    
    // MARK: - Search Filtering
    
    var filteredWallpapers: [Wallpaper] {
        if searchQuery.isEmpty {
            return wallpapers
        } else {
            let query = searchQuery.lowercased()
            return wallpapers.filter {
                $0.title.lowercased().contains(query) ||
                $0.creator.lowercased().contains(query) ||
                $0.type.rawValue.lowercased().contains(query)
            }
        }
    }
    
    // MARK: - Core Operations
    
    func toggleFavorite(for wallpaper: Wallpaper) {
        if let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
            wallpapers[index].isFavorite.toggle()
            
            // Sync with persistent array registry
            let favoriteIDs = wallpapers.filter { $0.isFavorite }.map { $0.id }
            UserDefaults.standard.set(favoriteIDs, forKey: favoritesRegistryKey)
        }
    }
    
    func addCustomWallpaper(at localURL: URL) {
        do {
            let storedURL = try CacheManager.shared.ingestLocalFile(at: localURL)
            loadCatalog() // Reload to catch new file
            NotificationCenter.default.post(name: .CanvasCatalogDidUpdate, object: storedURL)
        } catch {
            print("Canvas Catalog Error: Failed to ingest drop asset: \(error.localizedDescription)")
        }
    }
    
    func removeWallpaper(_ wallpaper: Wallpaper) {
        guard wallpaper.isLocal else { return }
        
        do {
            if FileManager.default.fileExists(atPath: wallpaper.url) {
                try FileManager.default.removeItem(atPath: wallpaper.url)
            }
            BookmarkManager.shared.removeBookmark(forPath: wallpaper.url)
            loadCatalog()
        } catch {
            print("Canvas Catalog Error: Failed to remove wallpaper asset: \(error.localizedDescription)")
        }
    }
    
    func renameWallpaper(_ wallpaper: Wallpaper, to newTitle: String) {
        if let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
            wallpapers[index].title = newTitle
            
            // Persist renamed custom titles in UserDefaults so they survive reloads
            var customTitles = UserDefaults.standard.dictionary(forKey: "com.canvas.custom.titles") as? [String: String] ?? [:]
            customTitles[wallpaper.id] = newTitle
            UserDefaults.standard.set(customTitles, forKey: "com.canvas.custom.titles")
            
            print("Canvas Catalog: Renamed wallpaper \(wallpaper.id) to \(newTitle)")
            
            // Trigger SwiftUI update
            objectWillChange.send()
        }
    }
}

extension Notification.Name {
    static let CanvasCatalogDidUpdate = Notification.Name("CanvasCatalogDidUpdate")
}
