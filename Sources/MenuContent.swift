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

            Button { state.showQuickNarrate() } label: {
                Label("Quick Narrate…", systemImage: "text.bubble")
            }
            .keyboardShortcut("n", modifiers: [.control, .option])

            Button { state.readClipboardHighlighted() } label: {
                Label("Read Clipboard (Highlighted)", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button { state.narrateFile() } label: {
                Label("Narrate File…", systemImage: "doc.text")
            }

            if !state.queue.isEmpty {
                HStack {
                    Label("Queue: \(state.queue.count) waiting", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { state.clearQueue() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }

            Button { state.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .keyboardShortcut("x", modifiers: [.control, .option])
            .disabled(!state.audio.hasAudio)

            Divider().padding(.vertical, 2)

            // Accessory (LSUIElement) apps don't activate on their own, so the
            // Settings window would otherwise open hidden behind other apps —
            // activate alongside SettingsLink so it comes to the front. When the
            // window is already open, highlight the row and point back to it.
            SettingsLink {
                Label(state.settingsWindowOpen ? "Settings (open)" : "Settings…",
                      systemImage: state.settingsWindowOpen ? "gearshape.fill" : "gearshape")
            }
            .buttonStyle(MenuRowButtonStyle(highlighted: state.settingsWindowOpen))
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })
            .animation(.snappy, value: state.settingsWindowOpen)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(MenuRowButtonStyle(destructive: true))
            .keyboardShortcut("q")
        }
        .buttonStyle(MenuRowButtonStyle())
        .padding(12)
        .frame(width: 250)
    }
}

/// A menu-row button that highlights on hover (and can stay highlighted, e.g.
/// to indicate the Settings window is already open). Gives the otherwise-static
/// menu-bar panel some life.
struct MenuRowButtonStyle: ButtonStyle {
    var highlighted = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration, highlighted: highlighted, destructive: destructive)
    }

    private struct MenuRow: View {
        let configuration: Configuration
        let highlighted: Bool
        let destructive: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let tint: Color = destructive ? .red : .accentColor
            let fill = hovering ? 0.22 : (highlighted ? 0.13 : 0.0)
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(destructive && hovering ? Color.red : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(isEnabled ? fill : 0))
                )
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { if isEnabled { hovering = $0 } }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
        }
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
                Spacer()
                SpeedMenu().environmentObject(state)
            }
            .imageScale(.large)
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }
}

/// A compact menu to pick playback speed (0.75×–2×). Applies live to the player.
struct SpeedMenu: View {
    @EnvironmentObject var state: AppState
    private let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        Menu {
            ForEach(rates, id: \.self) { r in
                Button {
                    state.audio.rate = r
                } label: {
                    Label(format(r), systemImage: state.audio.rate == r ? "checkmark" : "")
                }
            }
        } label: {
            Text(format(state.audio.rate))
                .font(.caption.monospacedDigit())
                .frame(minWidth: 34)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Playback speed")
    }

    private func format(_ r: Float) -> String {
        (r == r.rounded() ? String(format: "%.0f×", r) : String(format: "%.2g×", r))
    }
}
