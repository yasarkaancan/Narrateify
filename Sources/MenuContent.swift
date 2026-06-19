import SwiftUI

/// The small panel shown when clicking the menu bar icon.
struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "waveform")
                Text("Narrateify").font(.headline)
            }
            Text(state.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if state.audio.hasAudio {
                Divider().padding(.vertical, 2)
                PlayerControls().environmentObject(state)
            }

            Divider().padding(.vertical, 2)

            Button { state.narrateSelection() } label: {
                Label("Narrate Selected Text", systemImage: "text.cursor")
            }
            .keyboardShortcut("r", modifiers: [.control, .option])

            Button { state.narrateScreenshot() } label: {
                Label("Narrate Screenshot", systemImage: "camera.viewfinder")
            }
            .keyboardShortcut("s", modifiers: [.control, .option])

            Button { state.narrateClipboard() } label: {
                Label("Narrate Clipboard Text", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v", modifiers: [.control, .option])

            Button { state.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .keyboardShortcut("x", modifiers: [.control, .option])
            .disabled(!state.audio.hasAudio)

            Divider().padding(.vertical, 2)

            // Accessory (LSUIElement) apps don't activate on their own, so the
            // Settings window would otherwise open hidden behind other apps —
            // activate alongside SettingsLink so it comes to the front.
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: 250)
    }
}

/// Transport controls for the current narration: scrub, play/pause, ±5s.
struct PlayerControls: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { state.audio.currentTime },
                    set: { state.audio.seek(to: $0) }
                ),
                in: 0...max(state.audio.duration, 0.01)
            )

            HStack {
                Text(formatDuration(state.audio.currentTime))
                Spacer()
                Text(formatDuration(state.audio.duration))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 22) {
                Button { state.audio.skip(by: -5) } label: {
                    Image(systemName: "gobackward.5")
                }
                Button { state.audio.togglePlayPause() } label: {
                    Image(systemName: state.audio.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                Button { state.audio.skip(by: 5) } label: {
                    Image(systemName: "goforward.5")
                }
            }
            .imageScale(.large)
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }
}
