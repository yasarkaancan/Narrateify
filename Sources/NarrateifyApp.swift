import SwiftUI

@main
struct NarrateifyApp: App {
    // Drives lifecycle + global hotkey registration.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        // The menu bar item. `.window` style lets us show a small custom panel.
        MenuBarExtra("Narrateify", systemImage: state.audio.isPlaying ? "waveform.circle.fill" : "waveform") {
            MenuContent()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        // Standard macOS Settings window (⌘, from the menu).
        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
