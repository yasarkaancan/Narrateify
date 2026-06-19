import AppKit

/// Exposes a macOS *Service* so "Narrate with Narrateify" appears in the
/// right-click → Services submenu (and the app menu's Services) whenever text
/// is selected in any app. This is the system-supported way to add a narrate
/// action to other apps' context menus — macOS doesn't allow injecting a
/// top-level item into another app's right-click menu.
///
/// The `@objc` method name is referenced by `NSMessage` in Info.plist.
final class ServiceProvider: NSObject {
    @objc func narrateSelection(_ pboard: NSPasteboard,
                                userData: String?,
                                error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let text = pboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            error?.pointee = "No text was provided to narrate." as NSString
            return
        }
        Task { @MainActor in AppState.shared.narrate(text) }
    }
}
