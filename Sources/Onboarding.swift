import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics

/// A short first-run wizard: what the app does, the two macOS permissions it
/// needs, and the default hotkeys. Shown once (tracked by `didOnboard`).
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()
    static let didOnboardKey = "didOnboard"

    private var window: NSWindow?

    /// Shows onboarding if it hasn't run before.
    static func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didOnboardKey) else { return }
        shared.show()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(
            rootView: OnboardingView(onFinish: { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.didOnboardKey)
                self?.close()
            })
        )
        let w = NSWindow(contentViewController: hosting)
        w.title = "Welcome to Narrateify"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setContentSize(NSSize(width: 480, height: 420))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        // If they close via the title bar, treat onboarding as seen too.
        UserDefaults.standard.set(true, forKey: Self.didOnboardKey)
        window = nil
    }
}

private struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    @State private var accessibilityOK = AXIsProcessTrusted()
    @State private var screenOK = CGPreflightScreenCaptureAccess()

    private let recheck = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private let lastStep = 2

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)

            Divider()
            footer
                .padding(16)
        }
        .frame(width: 480, height: 420)
        .onReceive(recheck) { _ in
            accessibilityOK = AXIsProcessTrusted()
            screenOK = CGPreflightScreenCaptureAccess()
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: permissions
        default: shortcuts
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
            Text("Narrateify").font(.largeTitle.bold())
            Text("Narrate any text out loud — selected text, a screen region, or "
                 + "the clipboard — from anywhere, with a global hotkey.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Label("Ready to go: the built-in Apple voice works instantly — no API "
                  + "key, no download. Add other engines anytime in Settings.",
                  systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
                .padding(.top, 4)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Two optional permissions").font(.title2.bold())
            Text("Grant these so the selection and screenshot features work. You "
                 + "can skip and do it later — Quick Narrate and the clipboard work "
                 + "without them.")
                .foregroundStyle(.secondary)
                .font(.callout)

            permissionRow(
                ok: accessibilityOK,
                title: "Accessibility",
                detail: "Lets Narrateify read selected text (it copies it for you).",
                button: "Grant…",
                action: requestAccessibility)

            permissionRow(
                ok: screenOK,
                title: "Screen Recording",
                detail: "Lets the screenshot feature capture a region to read via OCR.",
                button: "Grant…",
                action: requestScreen)

            Text("After granting, macOS may ask you to quit and reopen Narrateify.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your hotkeys").font(.title2.bold())
            Text("These work in any app. Customize them in Settings → General → "
                 + "Shortcuts.")
                .foregroundStyle(.secondary).font(.callout)

            VStack(alignment: .leading, spacing: 8) {
                shortcutRow("⌃⌥R", "Narrate selected text")
                shortcutRow("⌃⌥S", "Narrate a screen region (OCR)")
                shortcutRow("⌃⌥V", "Narrate the clipboard")
                shortcutRow("⌃⌥N", "Open Quick Narrate (type/paste)")
                shortcutRow("⌃⌥Space", "Play / pause")
                shortcutRow("⌃⌥X", "Stop")
            }
            .padding(.top, 4)
        }
    }

    // MARK: Pieces

    private func permissionRow(ok: Bool, title: String, detail: String,
                               button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if ok {
                Text("Granted").font(.caption).foregroundStyle(.green)
            } else {
                Button(button, action: action)
            }
        }
    }

    private func shortcutRow(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 80, alignment: .leading)
                .padding(.vertical, 3).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            Text(label)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            PageDots(count: lastStep + 1, current: step)
            Spacer()
            if step < lastStep {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") { onFinish() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openSettings("Privacy_Accessibility")
    }

    private func requestScreen() {
        CGRequestScreenCaptureAccess()
        openSettings("Privacy_ScreenCapture")
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
    }
}
