import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A recordable global shortcut: a virtual key code plus Carbon modifier flags.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Build from an NSEvent captured while recording. Returns `nil` if the
    /// combination lacks a "strong" modifier (⌘/⌥/⌃) — a plain key would be
    /// hijacked system-wide, which we don't allow.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }

        let strong = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
        guard carbon & strong != 0 else { return nil }

        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbon
    }

    /// Human-readable form, e.g. "⌃⌥R". Modifier order follows the macOS
    /// convention: ⌃ ⌥ ⇧ ⌘.
    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += Shortcut.keyName(for: keyCode)
        return s
    }

    /// Maps a virtual key code to a display string.
    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"; case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"; case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"; case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"; case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"; case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"; case kVK_ANSI_9: return "9"
        case kVK_Space:        return "Space"
        case kVK_Return:       return "↩"
        case kVK_Tab:          return "⇥"
        case kVK_Delete:       return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape:       return "⎋"
        case kVK_LeftArrow:    return "←"
        case kVK_RightArrow:   return "→"
        case kVK_UpArrow:      return "↑"
        case kVK_DownArrow:    return "↓"
        case kVK_Home:         return "↖"
        case kVK_End:          return "↘"
        case kVK_PageUp:       return "⇞"
        case kVK_PageDown:     return "⇟"
        case kVK_ANSI_Minus:        return "-"
        case kVK_ANSI_Equal:        return "="
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash:    return "\\"
        case kVK_ANSI_Semicolon:    return ";"
        case kVK_ANSI_Quote:        return "'"
        case kVK_ANSI_Comma:        return ","
        case kVK_ANSI_Period:       return "."
        case kVK_ANSI_Slash:        return "/"
        case kVK_ANSI_Grave:        return "`"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"
        case kVK_F3: return "F3"; case kVK_F4: return "F4"
        case kVK_F5: return "F5"; case kVK_F6: return "F6"
        case kVK_F7: return "F7"; case kVK_F8: return "F8"
        case kVK_F9: return "F9"; case kVK_F10: return "F10"
        case kVK_F11: return "F11"; case kVK_F12: return "F12"
        default: return "Key \(keyCode)"
        }
    }
}

/// The user-triggerable actions that can be bound to a global hotkey.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case narrateSelection
    case narrateScreenshot
    case narrateClipboard
    case stop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .narrateSelection:  return "Narrate selection"
        case .narrateScreenshot: return "Narrate screenshot"
        case .narrateClipboard:  return "Narrate clipboard"
        case .stop:              return "Stop playback"
        }
    }

    /// The factory default, matching the app's original fixed bindings.
    var defaultShortcut: Shortcut {
        let mods = UInt32(controlKey) | UInt32(optionKey)   // ⌃⌥
        switch self {
        case .narrateSelection:  return Shortcut(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: mods)
        case .narrateScreenshot: return Shortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: mods)
        case .narrateClipboard:  return Shortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: mods)
        case .stop:              return Shortcut(keyCode: UInt32(kVK_ANSI_X), carbonModifiers: mods)
        }
    }

    var defaultsKey: String { "shortcut.\(rawValue)" }

    /// Runs the action. Called on the main actor from the hotkey handler.
    @MainActor func perform() {
        switch self {
        case .narrateSelection:  AppState.shared.narrateSelection()
        case .narrateScreenshot: AppState.shared.narrateScreenshot()
        case .narrateClipboard:  AppState.shared.narrateClipboard()
        case .stop:              AppState.shared.stop()
        }
    }
}

/// Holds the user's shortcut bindings, persists them, and (re)registers them
/// with the global `HotKeyManager`.
@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var bindings: [String: Shortcut] = [:]

    init() { load() }

    func shortcut(for action: ShortcutAction) -> Shortcut {
        bindings[action.rawValue] ?? action.defaultShortcut
    }

    /// Assigns a new shortcut. Returns an error message if it collides with
    /// another action (Carbon silently refuses to register a duplicate combo).
    @discardableResult
    func set(_ shortcut: Shortcut, for action: ShortcutAction) -> String? {
        if let clash = ShortcutAction.allCases.first(where: {
            $0 != action && self.shortcut(for: $0) == shortcut
        }) {
            return "Already used by “\(clash.title)”."
        }
        bindings[action.rawValue] = shortcut
        persist()
        applyAll()
        return nil
    }

    func reset(_ action: ShortcutAction) {
        bindings[action.rawValue] = action.defaultShortcut
        persist()
        applyAll()
    }

    /// Clears every existing hotkey and re-registers from the current bindings.
    func applyAll() {
        HotKeyManager.shared.unregisterAll()
        for action in ShortcutAction.allCases {
            let sc = shortcut(for: action)
            HotKeyManager.shared.register(keyCode: sc.keyCode, modifiers: sc.carbonModifiers) {
                Task { @MainActor in action.perform() }
            }
        }
    }

    private func load() {
        let d = UserDefaults.standard
        for action in ShortcutAction.allCases {
            if let data = d.data(forKey: action.defaultsKey),
               let sc = try? JSONDecoder().decode(Shortcut.self, from: data) {
                bindings[action.rawValue] = sc
            }
        }
    }

    private func persist() {
        let d = UserDefaults.standard
        for action in ShortcutAction.allCases {
            if let sc = bindings[action.rawValue],
               let data = try? JSONEncoder().encode(sc) {
                d.set(data, forKey: action.defaultsKey)
            }
        }
    }
}

// MARK: - UI

/// The contents of the Settings → General → "Shortcuts" section: one editable
/// row per action plus a hint.
struct ShortcutsSettingsView: View {
    var body: some View {
        ForEach(ShortcutAction.allCases) { action in
            ShortcutRow(action: action)
        }
        Text("Click a shortcut, then press the new key combination. "
             + "Global shortcuts need at least one of ⌘ ⌥ ⌃. Press ⎋ to cancel.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// A single editable shortcut row: label, a "click to record" field, and a
/// reset-to-default button.
private struct ShortcutRow: View {
    let action: ShortcutAction
    @EnvironmentObject var state: AppState

    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if let error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button(action: toggleRecording) {
                Text(recording ? "Press keys…"
                                : state.shortcutStore.shortcut(for: action).display)
                    .monospaced()
                    .frame(minWidth: 64)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)

            Button(action: { state.shortcutStore.reset(action); error = nil }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Reset to default")
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if recording { stopRecording(); return }
        recording = true
        error = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }
            if let sc = Shortcut(event: event) {
                error = state.shortcutStore.set(sc, for: action)
                stopRecording()
            } else {
                error = "Use at least one of ⌘ ⌥ ⌃."
            }
            return nil   // swallow the keystroke while recording
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
