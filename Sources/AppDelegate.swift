import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a background "agent" — no Dock icon, no app menu.
        // (Setting LSUIElement = YES in Info.plist does the same at launch;
        //  this is a belt-and-suspenders fallback.)
        NSApp.setActivationPolicy(.accessory)

        // Make the "Narrate with Narrateify" Service available in the
        // right-click → Services menu of other apps.
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()

        registerHotKeys()
        promptForAccessibilityIfNeeded()

        // If the last narration used an installed local model, bring its server
        // up now so it's ready to narrate immediately.
        Task { @MainActor in AppState.shared.autoStartLastServerIfNeeded() }

        // Quietly check GitHub for a newer release in the background.
        Task { @MainActor in await AppState.shared.updateChecker.check() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave orphaned local-server processes behind.
        MainActor.assumeIsolated { AppState.shared.shutdownServers() }
    }

    private func registerHotKeys() {
        // Bindings are user-editable (Settings → General → Shortcuts) and
        // persisted; the store registers them all with HotKeyManager.
        MainActor.assumeIsolated { AppState.shared.shortcutStore.applyAll() }
    }

    /// Triggers the system prompt to grant Accessibility access (needed to read
    /// selected text by synthesizing ⌘C). Safe to call every launch.
    private func promptForAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
