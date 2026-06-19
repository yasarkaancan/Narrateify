import SwiftUI
import AppKit

/// A floating, draggable HUD. It starts as a "converting to speech" indicator
/// and morphs into a compact media player once playback begins. It lives in a
/// borderless, non-activating panel above all apps, so it's usable whether
/// narration was triggered by a global hotkey or from the menu — without
/// stealing focus from whatever app the user is in.
@MainActor
final class SynthesisOverlay: NSObject, NSWindowDelegate {
    static let shared = SynthesisOverlay()

    private var panel: OverlayPanel?

    private let originXKey = "overlayOriginX"
    private let originYKey = "overlayOriginY"

    func show() {
        let panel = ensurePanel()
        guard !panel.isVisible else { return }   // already up; content self-updates

        position(panel)
        let target = panel.frame
        var start = target
        start.origin.y -= 16

        panel.alphaValue = 0
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// Forget the saved position and recenter (used by Settings).
    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: originXKey)
        UserDefaults.standard.removeObject(forKey: originYKey)
        if let panel, panel.isVisible {
            position(panel, ignoringSaved: true)
        }
    }

    // MARK: Panel plumbing

    private func ensurePanel() -> OverlayPanel {
        if let panel { return panel }

        let hosting = NSHostingView(rootView: OverlayContent(state: .shared))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let panel = OverlayPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false                  // SwiftUI draws the shadow
        panel.isMovableByWindowBackground = true // drag the blob anywhere
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        self.panel = panel
        return panel
    }

    /// Size to fit and place at the saved origin, or default to bottom-center.
    private func position(_ panel: OverlayPanel, ignoringSaved: Bool = false) {
        guard let hosting = panel.contentView else { return }
        let size = hosting.fittingSize
        panel.setContentSize(size)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vis = screen.visibleFrame

        let defaults = UserDefaults.standard
        if !ignoringSaved,
           defaults.object(forKey: originXKey) != nil,
           defaults.object(forKey: originYKey) != nil {
            // Restore, but clamp so it can't end up off-screen.
            let x = min(max(defaults.double(forKey: originXKey), vis.minX),
                        vis.maxX - size.width)
            let y = min(max(defaults.double(forKey: originYKey), vis.minY),
                        vis.maxY - size.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.setFrameOrigin(NSPoint(x: vis.midX - size.width / 2,
                                         y: vis.minY + 120))
        }
    }

    // MARK: NSWindowDelegate — persist the dragged position

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        UserDefaults.standard.set(panel.frame.origin.x, forKey: originXKey)
        UserDefaults.standard.set(panel.frame.origin.y, forKey: originYKey)
    }
}

/// Borderless panel that can still become key, so the embedded controls work
/// without activating the whole app.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Overlay content

/// Switches between the "converting" indicator and the floating media player.
private struct OverlayContent: View {
    @ObservedObject var state: AppState

    private var isPlayer: Bool { state.audio.hasAudio && !state.isSynthesizing }

    var body: some View {
        HStack(spacing: 14) {
            EqualizerBars(active: state.isSynthesizing || state.audio.isPlaying)
                .frame(width: 30, height: 24)

            Group {
                if isPlayer {
                    playerBody
                } else {
                    synthesizingBody
                }
            }
            .frame(width: 232, alignment: .leading)
        }
        .frame(height: 56)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { closeButton }
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        .padding(24)   // breathing room so the shadow isn't clipped
    }

    // "Converting to speech" phase.
    private var synthesizingBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Converting to speech").font(.headline)
            Text("Narrateify").font(.caption).foregroundStyle(.secondary)
        }
    }

    // Floating media-player phase.
    private var playerBody: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text(formatDuration(state.audio.currentTime))
                Slider(
                    value: Binding(
                        get: { state.audio.currentTime },
                        set: { state.audio.seek(to: $0) }
                    ),
                    in: 0...max(state.audio.duration, 0.01)
                )
                Text(formatDuration(state.audio.duration))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            HStack(spacing: 20) {
                Button { state.audio.skip(by: -5) } label: {
                    Image(systemName: "gobackward.5")
                }
                Button { state.audio.togglePlayPause() } label: {
                    Image(systemName: state.audio.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 16)
                }
                Button { state.audio.skip(by: 5) } label: {
                    Image(systemName: "goforward.5")
                }
                Button { state.endNarration() } label: {
                    Image(systemName: "stop.fill")
                }
            }
            .imageScale(.medium)
            .buttonStyle(.borderless)
        }
    }

    private var closeButton: some View {
        Button { state.closeOverlay() } label: {
            Image(systemName: "xmark.circle.fill")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .background(Circle().fill(.background).scaleEffect(0.7))
        }
        .buttonStyle(.borderless)
        .help("Hide the overlay")
        .padding(10)
    }
}

/// A continuously animating equalizer — five bars bouncing out of phase.
/// Freezes when `active` is false (e.g. while paused).
private struct EqualizerBars: View {
    var active: Bool
    private let bars = 5
    @State private var animating = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .scaleEffect(x: 1, y: animating ? 1.0 : 0.28, anchor: .center)
                    .animation(
                        active
                            ? .easeInOut(duration: 0.55).repeatForever().delay(Double(i) * 0.11)
                            : .easeOut(duration: 0.2),
                        value: animating
                    )
            }
        }
        .onAppear { animating = active }
        .onChange(of: active) { _, newValue in animating = newValue }
    }
}
