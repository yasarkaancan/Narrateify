import AppKit
import Carbon.HIToolbox

/// Captures the user's current text selection from *any* application by
/// synthesizing a ⌘C keystroke and reading the general pasteboard.
///
/// This is the most reliable cross-app technique on macOS. It requires
/// Accessibility permission (to post keyboard events to other apps).
enum TextCapture {

    static func selectedText(completion: @escaping (String?) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(nil)
            return
        }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount

        // Small delay lets the physically-held hotkey modifiers (⌃⌥) release
        // before we post the synthetic ⌘C, avoiding modifier interference.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            simulateCommandC()

            // Give the frontmost app a moment to write to the pasteboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if pasteboard.changeCount != previousChangeCount {
                    completion(pasteboard.string(forType: .string))
                } else {
                    completion(nil) // nothing was copied (no selection)
                }
            }
        }
    }

    private static func simulateCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey = CGKeyCode(kVK_ANSI_C)

        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
