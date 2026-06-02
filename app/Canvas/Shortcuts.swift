import AppIntents
import Foundation

@available(macOS 13.0, *)
struct PlayWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Wallpaper"
    static var description = IntentDescription("Resumes playback of active Canvas desktop wallpapers.")
    
    static var parameterSummary: some ParameterSummary {
        Summary("Resumes active wallpaper playback")
    }
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            DisplayManager.shared.play()
        }
        return .result()
    }
}

@available(macOS 13.0, *)
struct PauseWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Wallpaper"
    static var description = IntentDescription("Pauses playback of active Canvas desktop wallpapers.")
    
    static var parameterSummary: some ParameterSummary {
        Summary("Pauses active wallpaper playback")
    }
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            DisplayManager.shared.pause()
        }
        return .result()
    }
}

@available(macOS 13.0, *)
struct MuteWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Mute Wallpaper"
    static var description = IntentDescription("Toggles muting of active Canvas desktop wallpapers.")
    
    static var parameterSummary: some ParameterSummary {
        Summary("Toggles wallpaper muting status")
    }
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            let currentMute = UserDefaults.standard.bool(forKey: "com.canvas.playback.muted")
            let newMute = !currentMute
            UserDefaults.standard.set(newMute, forKey: "com.canvas.playback.muted")
            DisplayManager.shared.updateMute(newMute)
        }
        return .result()
    }
}

/// Exposes all intents to the native macOS Shortcuts system registry.
@available(macOS 13.0, *)
struct CanvasShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: PlayWallpaperIntent(),
                phrases: [
                    "Play \(.applicationName) Wallpaper",
                    "Resume \(.applicationName)"
                ],
                shortTitle: "Play Wallpaper",
                systemImageName: "play.fill"
            ),
            AppShortcut(
                intent: PauseWallpaperIntent(),
                phrases: [
                    "Pause \(.applicationName) Wallpaper",
                    "Stop \(.applicationName)"
                ],
                shortTitle: "Pause Wallpaper",
                systemImageName: "pause.fill"
            ),
            AppShortcut(
                intent: MuteWallpaperIntent(),
                phrases: [
                    "Mute \(.applicationName) Wallpaper",
                    "Silence \(.applicationName)"
                ],
                shortTitle: "Mute Wallpaper",
                systemImageName: "speaker.slash.fill"
            )
        ]
    }
}
