import Foundation

/// Manages macOS Sandbox Security-Scoped Bookmarks to persist access permissions
/// for user-selected local wallpapers and monitored folders across app relaunches.
class BookmarkManager {
    
    static let shared = BookmarkManager()
    
    private let bookmarksKey = "com.canvas.security.bookmarks"
    
    private init() {}
    
    /// Generates and stores a security-scoped bookmark for the specified URL.
    /// - Parameter url: The file or folder URL to bookmark.
    /// - Returns: The persistent bookmark Data.
    func saveBookmark(for url: URL) -> Data? {
        // Only generate bookmarks for file-scheme URLs
        guard url.isFileURL else { return nil }
        
        do {
            // Enable access inside Sandbox
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // Save to UserDefaults registry
            var currentRegistry = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            currentRegistry[url.path] = bookmarkData
            UserDefaults.standard.set(currentRegistry, forKey: bookmarksKey)
            
            print("Canvas BookmarkManager: Successfully saved security bookmark for \(url.lastPathComponent)")
            return bookmarkData
        } catch {
            print("Canvas BookmarkManager Error: Failed to generate bookmark for \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Resolves a stored security-scoped bookmark back into a readable/writeable URL.
    /// - Parameter path: The original file path.
    /// - Returns: The resolved URL with active permissions, or nil.
    func resolveBookmark(forPath path: String) -> URL? {
        guard let registry = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data],
              let bookmarkData = registry[path] else {
            return nil
        }
        
        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            // If the bookmark is stale, regenerate it to prevent future resolve failures
            if isStale {
                print("Canvas BookmarkManager: Bookmark for \(path) is stale. Regenerating...")
                _ = saveBookmark(for: resolvedURL)
            }
            
            return resolvedURL
        } catch {
            print("Canvas BookmarkManager Error: Failed to resolve bookmark for \(path): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Safely performs a block of work requiring security-scoped access to a file/folder.
    /// - Parameters:
    ///   - url: The target security-scoped URL.
    ///   - work: A closure executing the required file operations.
    func withSecurityAccess(to url: URL, work: (URL) -> Void) {
        guard url.isFileURL else {
            // Non-file URLs (web URLs) don't need sandbox bookmarks
            work(url)
            return
        }
        
        let shouldAccess = url.startAccessingSecurityScopedResource()
        if shouldAccess {
            print("Canvas BookmarkManager: Acquired sandbox access to \(url.lastPathComponent)")
        } else {
            print("Canvas BookmarkManager Warning: Access token not acquired, attempting operation anyway.")
        }
        
        defer {
            if shouldAccess {
                url.stopAccessingSecurityScopedResource()
                print("Canvas BookmarkManager: Released sandbox access to \(url.lastPathComponent)")
            }
        }
        
        work(url)
    }
    
    /// Completely removes a stored bookmark when an asset is deleted or evicted.
    /// - Parameter path: The target file path.
    func removeBookmark(forPath path: String) {
        var registry = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        registry.removeValue(forKey: path)
        UserDefaults.standard.set(registry, forKey: bookmarksKey)
        print("Canvas BookmarkManager: Removed security bookmark for \(path)")
    }
}
