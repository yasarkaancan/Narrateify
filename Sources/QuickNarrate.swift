import SwiftUI
import AppKit

/// A small standalone window for typing or pasting text and narrating it
/// directly — so you don't have to select text in another app first. Opened
/// from the menu or the Quick Narrate hotkey.
@MainActor
final class QuickNarrateWindow: NSObject, NSWindowDelegate {
    static let shared = QuickNarrateWindow()
    private var window: NSWindow?

    func show() {
        // Accessory apps don't activate on their own; bring us forward so the
        // text field can take focus and keystrokes.
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: QuickNarrateView(onClose: { [weak self] in self?.close() })
                .environmentObject(AppState.shared)
        )
        let w = NSWindow(contentViewController: hosting)
        w.title = "Quick Narrate"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setContentSize(NSSize(width: 440, height: 250))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        // Drop the window so the next open starts with a fresh, empty editor.
        window = nil
    }
}

/// The Quick Narrate panel contents.
private struct QuickNarrateView: View {
    @EnvironmentObject var state: AppState
    @State private var text = ""
    @FocusState private var focused: Bool
    let onClose: () -> Void

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Quick Narrate", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Text(state.provider.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 120)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25)))
                if text.isEmpty {
                    Text("Type or paste text to narrate…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 14).padding(.leading, 12)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) { text = s }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                if !trimmed.isEmpty {
                    Text("\(trimmed.count) characters")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard !trimmed.isEmpty else { return }
                    state.readAloudHighlighted(trimmed)
                    onClose()
                } label: {
                    Label("Read", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .help("Read aloud with word highlighting (Apple voice)")
                .disabled(trimmed.isEmpty)
                Button("Narrate") { narrate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear { focused = true }
    }

    private func narrate() {
        guard !trimmed.isEmpty else { return }
        state.narrate(trimmed)
        onClose()
    }
}
