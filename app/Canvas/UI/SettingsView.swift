import SwiftUI
import ServiceManagement
import Sparkle

/// Standard preferences manager managing launch-at-login registries.
class LaunchAtLoginHelper: ObservableObject {
    @Published var isEnabled: Bool = false {
        didSet {
            toggleLaunchAtLogin(enabled: isEnabled)
        }
    }
    
    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
    
    private func toggleLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                    print("Canvas Launch: Registered login service.")
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                    print("Canvas Launch: Unregistered login service.")
                }
            }
        } catch {
            print("Canvas Launch Error: Failed to toggle Service: \(error.localizedDescription)")
        }
    }
}

/// The premium, Tabbed preferences panel for the Canvas Application.
struct SettingsView: View {
    @StateObject private var launchHelper = LaunchAtLoginHelper()
    @ObservedObject private var displayManager = DisplayManager.shared
    @ObservedObject private var folderMonitor = FolderMonitor.shared
    @ObservedObject private var cacheManager = CacheManager.shared
    
    @State private var cacheLimitGB: Double = 5.0
    @State private var feedbackText = ""
    @State private var emailAddress = ""
    @State private var feedbackSubmitted = false
    
    // Rate limiting: enforce minimum 60s between submissions to protect webhook from spam
    private let feedbackCooldownSeconds: TimeInterval = 60
    private let lastFeedbackTimestampKey = "com.canvas.feedback.lastSubmit"
    
    private var isOnCooldown: Bool {
        let last = UserDefaults.standard.double(forKey: lastFeedbackTimestampKey)
        return Date().timeIntervalSince1970 - last < feedbackCooldownSeconds
    }
    
    var body: some View {
        TabView {
            // General Settings Tab
            Form {
                Section(header: Text("Layout & Connections").font(.headline)) {
                    Picker("Monitor Arrangement", selection: $displayManager.layoutMode) {
                        Text("Independent (Individual Wallpapers)").tag(WallpaperLayoutMode.independent)
                        Text("Stretched (Single Canvas Split)").tag(WallpaperLayoutMode.stretched)
                    }
                    .pickerStyle(.radioGroup)
                    .help("Choose how wallpaper assets are spread across multiple active displays.")
                    
                    Toggle("Launch Canvas at Login", isOn: $launchHelper.isEnabled)
                        .toggleStyle(.checkbox)
                        .padding(.top, 4)
                }
                
                Divider().padding(.vertical, 10)
                
                Section(header: Text("Monitored Folder Sync").font(.headline)) {
                    HStack {
                        if let url = folderMonitor.monitoredFolderURL {
                            Text(url.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(.primary)
                        } else {
                            Text("No folder selected")
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Choose...") {
                            selectFolder()
                        }
                        
                        if folderMonitor.monitoredFolderURL != nil {
                            Button("Clear") {
                                folderMonitor.monitoredFolderURL = nil
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(6)
                    
                    Text("Canvas watches this folder in real-time. Any MP4, GIF, or photo added will sync to the wallpaper catalog automatically.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .padding(20)
            .frame(width: 450, height: 320)
            
            // Performance & Caching Tab
            Form {
                Section(header: Text("Cache Architecture allocation").font(.headline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Cache Limit: \(Int(cacheLimitGB)) GB")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        Slider(value: $cacheLimitGB, in: 2.0...30.0, step: 1.0)
                            .onChange(of: cacheLimitGB) { newValue in
                                cacheManager.cacheLimit = Int64(newValue * 1024 * 1024 * 1024)
                                UserDefaults.standard.set(newValue, forKey: "com.canvas.cache.limit.gb")
                            }
                        
                        Text("When disk space usage exceeds this limit, Canvas will automatically schedule eviction of oldest unused wallpaper files (LRU eviction).")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider().padding(.vertical, 10)
                
                Section(header: Text("Updates & Sparkle").font(.headline)) {
                    HStack {
                        Text("Automatic Background Update Checking is enabled.")
                            .font(.subheadline)
                        Spacer()
                        Button("Check for Updates...") {
                            triggerSparkleUpdateCheck()
                        }
                    }
                }
            }
            .tabItem {
                Label("Performance & Storage", systemImage: "bolt.fill")
            }
            .padding(20)
            .frame(width: 450, height: 380)
            
            // Support & Feedback Tab
            VStack(alignment: .leading, spacing: 12) {
                Text("Send Feedback or Bug Reports").font(.headline)
                
                if feedbackSubmitted {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("Thank you! Feedback received.")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextField("Your Email (optional)", text: $emailAddress)
                        .textFieldStyle(.roundedBorder)
                    
                    TextEditor(text: $feedbackText)
                        .frame(height: 120)
                        .border(Color.secondary.opacity(0.2), width: 1)
                        .cornerRadius(4)
                    
                    HStack {
                        Button(isOnCooldown ? "Please wait 60s..." : "Submit Feedback") {
                            submitFeedback()
                        }
                        .disabled(feedbackText.isEmpty || isOnCooldown)
                        
                        Spacer()
                        
                        Link("Documentation & Support", destination: URL(string: "https://github.com/kushhooda/CanvasMac")!)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .tabItem {
                Label("Feedback & Support", systemImage: "envelope.fill")
            }
            .padding(20)
            .frame(width: 450, height: 380)
        }
        .onAppear {
            let savedLimit = UserDefaults.standard.double(forKey: "com.canvas.cache.limit.gb")
            if savedLimit > 0 {
                self.cacheLimitGB = savedLimit
            }
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                // Generate Sandbox Bookmark for folder monitoring
                if BookmarkManager.shared.saveBookmark(for: selectedURL) != nil {
                    DispatchQueue.main.async {
                        folderMonitor.monitoredFolderURL = selectedURL
                    }
                }
            }
        }
    }
    
    private func triggerSparkleUpdateCheck() {
        // Safe access helper to delegate Sparkle updater check
        if let appDelegate = NSApp.delegate as? AppDelegate,
           let controller = appDelegate.updaterController {
            controller.updater.checkForUpdates()
        }
    }
    
    private func submitFeedback() {
        guard !feedbackText.isEmpty else { return }
        
        // Rate limiting: reject if submitted within the last 60 seconds
        let lastSubmit = UserDefaults.standard.double(forKey: lastFeedbackTimestampKey)
        let now = Date().timeIntervalSince1970
        if now - lastSubmit < feedbackCooldownSeconds {
            return // Silently drop — button should already be disabled, this is a safety net
        }
        UserDefaults.standard.set(now, forKey: lastFeedbackTimestampKey)
        
        let enteredText = feedbackText
        let contactEmail = emailAddress
        
        // Trigger immediate visual success confirmation in Settings UI
        withAnimation {
            feedbackSubmitted = true
        }
        
        // Clear input fields immediately for snappy UI feel
        feedbackText = ""
        emailAddress = ""
        
        // Gather rich system diagnostics
        let processInfo = ProcessInfo.processInfo
        let macOSVersion = processInfo.operatingSystemVersionString
        let deviceName = Host.current().localizedName ?? "Unknown Mac"
        let hostname = Host.current().name ?? "unknown"
        let cpuCount = processInfo.processorCount
        let physicalMemoryGB = String(format: "%.1f GB", Double(processInfo.physicalMemory) / 1_073_741_824)
        let locale = Locale.current.identifier
        let timezone = TimeZone.current.identifier
        
        // Screen info
        let screens = NSScreen.screens
        let screenCount = screens.count
        let primaryScreenRes = screens.first.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "Unknown"
        
        // Disk info
        var diskFreeStr = "Unknown"
        var diskTotalStr = "Unknown"
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            if let free = attrs[.systemFreeSize] as? Int64 {
                diskFreeStr = String(format: "%.1f GB", Double(free) / 1_073_741_824)
            }
            if let total = attrs[.systemSize] as? Int64 {
                diskTotalStr = String(format: "%.1f GB", Double(total) / 1_073_741_824)
            }
        }
        
        // App version
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        // Active wallpaper info
        let activeWallpaperURL = DisplayManager.shared.currentWallpaperURL
        let activeWallpaperName = activeWallpaperURL?.deletingPathExtension().lastPathComponent ?? "None"
        
        // Wallpaper catalog count
        let catalogCount = WallpaperCatalog.shared.wallpapers.count
        let favoriteCount = WallpaperCatalog.shared.wallpapers.filter { $0.isFavorite }.count
        let importCount = WallpaperCatalog.shared.wallpapers.filter { $0.creator == "Custom Import" }.count
        
        // Direct delivery to the hardcoded Discord webhook URL
        let discordWebhookURL = "https://discord.com/api/webhooks/1505811813810569387/HYpBxGMiEx1PUfg69leTOhCmOIMTB-hXzCDW9UcAUrMmYswt04PRmsRVii0wbiZ5S9tD"
        if let url = URL(string: discordWebhookURL) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Rich, fully-detailed Discord embed payload
            let payload: [String: Any] = [
                "username": "Canvas Feedback Bot",
                "avatar_url": "https://raw.githubusercontent.com/kushhooda/CanvasMac/main/app/Canvas/Assets.xcassets/AppIcon.appiconset/icon_256x256.png",
                "embeds": [
                    [
                        "title": "✨ New Canvas App Feedback",
                        "description": enteredText,
                        "color": 3066993, // Emerald green
                        "fields": [
                            // Contact
                            [
                                "name": "✉️ Reply Contact",
                                "value": contactEmail.isEmpty ? "*Not Provided*" : contactEmail,
                                "inline": true
                            ],
                            // Blank spacer
                            [
                                "name": " ",
                                "value": " ",
                                "inline": true
                            ],
                            // App version
                            [
                                "name": "📦 Canvas Version",
                                "value": "v\(appVersion) (build \(buildNumber))",
                                "inline": true
                            ],
                            // Device
                            [
                                "name": "🖥️ Device",
                                "value": deviceName,
                                "inline": true
                            ],
                            [
                                "name": "🔗 Hostname",
                                "value": hostname,
                                "inline": true
                            ],
                            // macOS
                            [
                                "name": "🍎 macOS",
                                "value": macOSVersion,
                                "inline": true
                            ],
                            // Hardware
                            [
                                "name": "⚙️ CPU Cores",
                                "value": "\(cpuCount) cores",
                                "inline": true
                            ],
                            [
                                "name": "🧠 RAM",
                                "value": physicalMemoryGB,
                                "inline": true
                            ],
                            // Disk
                            [
                                "name": "💾 Disk Free / Total",
                                "value": "\(diskFreeStr) / \(diskTotalStr)",
                                "inline": true
                            ],
                            // Screens
                            [
                                "name": "🖥️ Screens",
                                "value": "\(screenCount) display(s) — Primary: \(primaryScreenRes)",
                                "inline": true
                            ],
                            // Locale
                            [
                                "name": "🌍 Locale",
                                "value": "\(locale) (\(timezone))",
                                "inline": true
                            ],
                            // Active wallpaper
                            [
                                "name": "🎞️ Active Wallpaper",
                                "value": activeWallpaperName,
                                "inline": true
                            ],
                            // Catalog stats
                            [
                                "name": "📚 Catalog",
                                "value": "\(catalogCount) total · \(favoriteCount) ❤️ · \(importCount) 📥 imports",
                                "inline": true
                            ]
                        ],
                        "footer": [
                            "text": "Canvas macOS · \(deviceName)"
                        ],
                        "timestamp": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) {
                request.httpBody = jsonData
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("Canvas Feedback Error: Failed to post to Discord: \(error.localizedDescription)")
                    } else {
                        print("Canvas Feedback: Successfully posted feedback to Discord Webhook.")
                    }
                }.resume()
            }
        }
        
        // Reset checkmark success indicator after 3.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            feedbackSubmitted = false
        }
    }
}
