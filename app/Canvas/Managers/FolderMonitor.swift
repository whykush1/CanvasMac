import Foundation
import Combine

/// Monitors a user-selected folder in the background for new assets
/// using standard low-overhead Grand Central Dispatch file system sources.
class FolderMonitor: ObservableObject {
    
    static let shared = FolderMonitor()
    
    @Published var monitoredFolderURL: URL? {
        didSet {
            if let url = monitoredFolderURL {
                UserDefaults.standard.set(url.path, forKey: monitoredFolderRegistryKey)
                startMonitoring(url: url)
            } else {
                UserDefaults.standard.removeObject(forKey: monitoredFolderRegistryKey)
                stopMonitoring()
            }
        }
    }
    
    private let monitoredFolderRegistryKey = "com.canvas.monitored.folder.path"
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var knownFiles: Set<String> = []
    
    private init() {
        restoreMonitoredFolder()
    }
    
    private func restoreMonitoredFolder() {
        if let savedPath = UserDefaults.standard.string(forKey: monitoredFolderRegistryKey) {
            // Restore sandbox access via BookmarkManager
            if let resolvedURL = BookmarkManager.shared.resolveBookmark(forPath: savedPath) {
                print("Canvas FolderMonitor: Restored security bookmark for monitored directory: \(savedPath)")
                self.monitoredFolderURL = resolvedURL
            } else {
                print("Canvas FolderMonitor Warning: Could not resolve security bookmark for path: \(savedPath)")
            }
        }
    }
    
    /// Starts real-time grand-central-dispatch directory monitoring.
    func startMonitoring(url: URL) {
        stopMonitoring()
        
        BookmarkManager.shared.withSecurityAccess(to: url) { [weak self] securedURL in
            guard let self = self else { return }
            
            // 1. Build initial file listing state
            self.knownFiles = self.listDirectoryContents(url: securedURL)
            
            // 2. Open file descriptor for directory watching
            let descriptor = open(securedURL.path, O_EVTONLY)
            guard descriptor >= 0 else {
                print("Canvas FolderMonitor Error: Failed to open file descriptor for path: \(securedURL.path)")
                return
            }
            self.fileDescriptor = descriptor
            
            // 3. Create GCD File System Object Monitor Source
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: .write,
                queue: DispatchQueue.global(qos: .background)
            )
            
            source.setEventHandler { [weak self] in
                self?.handleDirectoryContentsChanged()
            }
            
            source.setCancelHandler {
                close(descriptor)
            }
            
            self.dispatchSource = source
            source.resume()
            print("Canvas FolderMonitor: Successfully established background watcher for \(securedURL.lastPathComponent)")
        }
    }
    
    /// Gracefully closes active directory watch descriptors and listeners.
    func stopMonitoring() {
        dispatchSource?.cancel()
        dispatchSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        knownFiles.removeAll()
    }
    
    private func handleDirectoryContentsChanged() {
        guard let url = monitoredFolderURL else { return }
        
        BookmarkManager.shared.withSecurityAccess(to: url) { [weak self] securedURL in
            guard let self = self else { return }
            
            let currentFiles = self.listDirectoryContents(url: securedURL)
            
            // Find newly added files
            let newFiles = currentFiles.subtracting(self.knownFiles)
            self.knownFiles = currentFiles
            
            for file in newFiles {
                let fileURL = securedURL.appendingPathComponent(file)
                print("Canvas FolderMonitor: Detected new file in folder -> \(file)")
                
                // Automate ingestion on main thread
                DispatchQueue.main.async {
                    do {
                        let ingestedURL = try CacheManager.shared.ingestLocalFile(at: fileURL)
                        print("Canvas FolderMonitor: Auto-ingested wallpaper successfully -> \(ingestedURL.lastPathComponent)")
                        
                        // Notify UI to refresh lists
                        NotificationCenter.default.post(name: .CanvasMonitoredFolderAssetAdded, object: ingestedURL)
                    } catch {
                        print("Canvas FolderMonitor: Failed to auto-ingest \(file): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func listDirectoryContents(url: URL) -> Set<String> {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return Set(files.filter { !$0.hasPrefix(".") }) // Exclude hidden files (.DS_Store, etc.)
        } catch {
            print("Canvas FolderMonitor Error: Failed to list directory at \(url.path): \(error.localizedDescription)")
            return []
        }
    }
    
    deinit {
        stopMonitoring()
    }
}

extension Notification.Name {
    static let CanvasMonitoredFolderAssetAdded = Notification.Name("CanvasMonitoredFolderAssetAdded")
}
