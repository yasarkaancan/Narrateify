import AppKit
import Carbon.HIToolbox

/// Registers true system-wide hotkeys via Carbon's RegisterEventHotKey.
/// Unlike NSEvent global monitors, these fire even when the app is in the
/// background and do not require the app to be focused.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    private var nextID: UInt32 = 1

    private init() {
        installHandler()
    }

    /// Register a hotkey. `keyCode` is a kVK_* virtual key; `modifiers` is a
    /// Carbon modifier mask (e.g. `UInt32(controlKey | optionKey)`).
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("NART"), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            registrations[id] = (ref, action)
        } else {
            NSLog("HotKeyManager: failed to register hotkey (status \(status))")
        }
        return id
    }

    /// Unregisters every active hotkey. Used before re-applying changed bindings.
    func unregisterAll() {
        for (_, reg) in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hkID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            manager.registrations[hkID.id]?.action()
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }
}

/// Packs a 4-character string into an OSType (FourCharCode) for the hotkey signature.
private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for ch in string.utf8.prefix(4) {
        result = (result << 8) + FourCharCode(ch)
    }
    return result
}
