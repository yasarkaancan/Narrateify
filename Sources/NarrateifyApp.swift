import SwiftUI

@main
struct NarrateifyApp: App {
    // Drives lifecycle + global hotkey registration.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        // The menu bar item. `.window` style lets us show a small custom panel.
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            MenuBarIcon(state: state)
        }
        .menuBarExtraStyle(.window)

        // Standard macOS Settings window (⌘, from the menu).
        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

/// The menu-bar status icon. It animates a waveform (via the symbol's variable
/// value) while synthesizing or playing, and shows a filled badge when a
/// narration is loaded but paused — giving glanceable status.
struct MenuBarIcon: View {
    @ObservedObject var state: AppState
    @State private var level = 1.0

    private let pulse = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

    private var active: Bool { state.isSynthesizing || state.audio.isPlaying }

    private var symbol: String {
        if active { return "waveform" }
        return state.audio.hasAudio ? "waveform.circle.fill" : "waveform"
    }

    var body: some View {
        Image(systemName: symbol, variableValue: active ? level : 1.0)
            .onReceive(pulse) { _ in
                guard active else { return }
                // Bias toward taller bars so it reads as "speaking".
                level = Double.random(in: 0.25...1.0)
            }
            .onChange(of: active) { _, isActive in
                if !isActive { level = 1.0 }
            }
    }
}
