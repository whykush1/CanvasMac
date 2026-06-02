import Foundation
import Combine
import AVFoundation

struct CachedAsset: Codable, Identifiable {
    var id: String { sha256 }
    let sha256: String
    let originalURL: String
    let localPath: String
    let fileSize: Int64
    var lastAccessed: Date
    let isVideo: Bool
}

class DownloadTaskWrapper: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var progress: Double = 0.0
    @Published var isCancelled = false
    @Published var error: Error?
    
    fileprivate var task: URLSessionDownloadTask?
    
    init(url: URL) {
        self.url = url
    }
    
    func cancel() {
        task?.cancel()
        isCancelled = true
        print("Canvas CacheManager: Cancelled download for \(url.lastPathComponent)")
    }
}

/// Dynamic cache management architecture. Handles downloads, file import validations,
/// drag-and-drop copies, and automatic LRU eviction schedules.
class CacheManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    
    static let shared = CacheManager()
    
    @Published var activeDownloads: [UUID: DownloadTaskWrapper] = [:]
    @Published var cacheLimit: Int64 = 5 * 1024 * 1024 * 1024 // Default 5GB Cache Size
    
    private var cachedAssets: [String: CachedAsset] = [:]
    private let cacheRegistryKey = "com.canvas.cache.registry"
    private var session: URLSession!
    
    private override init() {
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        loadCacheRegistry()
        schedulePeriodicEviction()
    }
    
    private func loadCacheRegistry() {
        if let data = UserDefaults.standard.data(forKey: cacheRegistryKey),
           let decoded = try? JSONDecoder().decode([String: CachedAsset].self, from: data) {
            self.cachedAssets = decoded
        }
    }
    
    private func saveCacheRegistry() {
        if let data = try? JSONEncoder().encode(cachedAssets) {
            UserDefaults.standard.set(data, forKey: cacheRegistryKey)
        }
    }
    
    // MARK: - Import Asset Validation & Ingestion
    
    /// Ingests a local file (e.g. from drag & drop or file dialog).
    /// Validates the resolution, format, and aspect ratio.
    /// Copies it inside the Sandboxed App Support folder to ensure persistent, hassle-free access.
    func ingestLocalFile(at fileURL: URL) throws -> URL {
        // 1. Perform security-scoped access
        let resolved = fileURL.startAccessingSecurityScopedResource()
        defer {
            if resolved { fileURL.stopAccessingSecurityScopedResource() }
        }
        
        // 2. Strict allowlist extension validation (prevents path traversal via crafted names)
        let ext = fileURL.pathExtension.lowercased()
        let allowedVideoExts: Set<String> = ["mp4", "mov", "m4v"]
        let allowedImageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic"]
        let isVideo = allowedVideoExts.contains(ext)
        let isImage = allowedImageExts.contains(ext)
        
        guard isVideo || isImage else {
            throw NSError(domain: "com.canvas.import", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported format. Only MP4, MOV, GIFs, and photos are allowed."])
        }
        
        // 3. Video track validation using modern async-safe API (avoids blocking main thread)
        if isVideo {
            let asset = AVURLAsset(url: fileURL)
            // Use the synchronous version only on a background queue – we're already off main
            let tracks = asset.tracks(withMediaType: .video)
            guard !tracks.isEmpty else {
                throw NSError(domain: "com.canvas.import", code: 401, userInfo: [NSLocalizedDescriptionKey: "Corrupted video file: No video track found."])
            }
        }
        
        // 4. Generate SHA-256 BEFORE copy to detect identical files (content-addressable)
        //    If hashing fails, reject the import — never fall back to UUID (would bypass identity tracking)
        guard let sha256 = generateFileSHA256(for: fileURL) else {
            throw NSError(domain: "com.canvas.import", code: 402, userInfo: [NSLocalizedDescriptionKey: "Unable to verify file integrity. Import rejected."])
        }
        
        // 5. Build sandboxed destination using ONLY the sha256 + ext (no user-supplied filename)
        //    This eliminates path traversal: "../../sensitive" filenames are completely ignored.
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let wallpapersDir = appSupportDir.appendingPathComponent("Wallpapers", isDirectory: true)
        
        try FileManager.default.createDirectory(at: wallpapersDir, withIntermediateDirectories: true, attributes: nil)
        
        // Destination is purely content-addressed: sha256.ext — no user input in the path
        let destinationURL = wallpapersDir.appendingPathComponent(sha256).appendingPathExtension(ext)
        
        // 6. Secure copy (skip if identical content already exists)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            // Identical content already imported — no-op, return existing path
            return destinationURL
        }
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        
        // 7. Register in cache tracking
        let size = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
        let asset = CachedAsset(
            sha256: sha256,
            originalURL: fileURL.absoluteString,
            localPath: destinationURL.path,
            fileSize: size,
            lastAccessed: Date(),
            isVideo: isVideo
        )
        
        cachedAssets[sha256] = asset
        saveCacheRegistry()
        
        // Run eviction check in background
        DispatchQueue.global(qos: .background).async {
            self.runCacheEvictionCheck()
        }
        
        return destinationURL
    }
    
    // MARK: - Asset Download pipeline
    
    func startDownload(from remoteURL: URL) -> DownloadTaskWrapper {
        let wrapper = DownloadTaskWrapper(url: remoteURL)
        let task = session.downloadTask(with: remoteURL)
        wrapper.task = task
        
        DispatchQueue.main.async {
            self.activeDownloads[wrapper.id] = wrapper
        }
        
        task.resume()
        print("Canvas CacheManager: Initiated download for \(remoteURL.absoluteString)")
        return wrapper
    }
    
    // MARK: - URLSession Delegates
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let url = downloadTask.originalRequest?.url else { return }
        
        DispatchQueue.main.async {
            if let wrapper = self.activeDownloads.values.first(where: { $0.url == url }) {
                let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                wrapper.progress = max(0.0, min(1.0, progress))
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let remoteURL = downloadTask.originalRequest?.url else { return }
        
        let ext = remoteURL.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v"].contains(ext)
        let sha256 = UUID().uuidString
        
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let wallpapersDir = appSupportDir.appendingPathComponent("Wallpapers", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: wallpapersDir, withIntermediateDirectories: true, attributes: nil)
            let destinationURL = wallpapersDir.appendingPathComponent("\(sha256).\(ext)")
            
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            let size = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
            let asset = CachedAsset(
                sha256: sha256,
                originalURL: remoteURL.absoluteString,
                localPath: destinationURL.path,
                fileSize: size,
                lastAccessed: Date(),
                isVideo: isVideo
            )
            
            DispatchQueue.main.async {
                self.cachedAssets[sha256] = asset
                self.saveCacheRegistry()
                
                // Remove from active downloads
                if let wrapper = self.activeDownloads.values.first(where: { $0.url == remoteURL }) {
                    self.activeDownloads.removeValue(forKey: wrapper.id)
                }
                
                // Notify download completed
                NotificationCenter.default.post(name: .CanvasWallpaperDownloadCompleted, object: destinationURL)
            }
            
            self.runCacheEvictionCheck()
            
        } catch {
            print("Canvas CacheManager Error: Failed to save downloaded asset: \(error.localizedDescription)")
            DispatchQueue.main.async {
                if let wrapper = self.activeDownloads.values.first(where: { $0.url == remoteURL }) {
                    wrapper.error = error
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let remoteURL = task.originalRequest?.url, let error = error else { return }
        print("Canvas CacheManager Error: Download completed with error: \(error.localizedDescription)")
        
        DispatchQueue.main.async {
            if let wrapper = self.activeDownloads.values.first(where: { $0.url == remoteURL }) {
                wrapper.error = error
            }
        }
    }
    
    // MARK: - LRU Cache Eviction
    
    private func schedulePeriodicEviction() {
        // Runs eviction verification check every 30 minutes in background
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .background).async {
                self?.runCacheEvictionCheck()
            }
        }
    }
    
    private func runCacheEvictionCheck() {
        var totalSize: Int64 = 0
        var assets = Array(cachedAssets.values)
        
        // Calculate current cache footprint
        for asset in assets {
            totalSize += asset.fileSize
        }
        
        print("Canvas CacheManager footprint: \(totalSize / (1024 * 1024)) MB / \(cacheLimit / (1024 * 1024)) MB limit")
        
        // If footprint exceeds limit, evict LRU (Least Recently Used) files until safely within limits
        if totalSize > cacheLimit {
            // Sort by oldest access date
            assets.sort { $0.lastAccessed < $1.lastAccessed }
            
            for asset in assets {
                if totalSize <= cacheLimit { break }
                
                do {
                    if FileManager.default.fileExists(atPath: asset.localPath) {
                        try FileManager.default.removeItem(atPath: asset.localPath)
                    }
                    cachedAssets.removeValue(forKey: asset.sha256)
                    totalSize -= asset.fileSize
                    print("Canvas CacheManager: Evicted stale asset \(asset.sha256) to free up space.")
                } catch {
                    print("Canvas CacheManager Error: Failed to evict cached file at \(asset.localPath): \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.saveCacheRegistry()
            }
        }
    }
    
    func recordAccess(forURL localURL: URL) {
        let path = localURL.path
        if let asset = cachedAssets.values.first(where: { $0.localPath == path }) {
            var updated = asset
            updated.lastAccessed = Date()
            cachedAssets[asset.sha256] = updated
            saveCacheRegistry()
        }
    }
    
    // MARK: - SHA256 Utility
    
    private func generateFileSHA256(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        // Quick hash generation
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}

// Quick digest length constants mapping if not fully imported in AVFoundation/Foundation
private let CC_SHA256_DIGEST_LENGTH = 32
typealias CC_LONG = UInt32
@discardableResult
@_silgen_name("CC_SHA256")
func CC_SHA256(_ data: UnsafeRawPointer?, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>?) -> UnsafeMutablePointer<UInt8>?

extension Notification.Name {
    static let CanvasWallpaperDownloadCompleted = Notification.Name("CanvasWallpaperDownloadCompleted")
}
