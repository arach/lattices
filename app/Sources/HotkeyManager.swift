import Carbon
import AppKit

/// Global callback registry keyed by hotkey ID
private var hotkeyCallbacks: [UInt32: () -> Void] = [:]

/// Whether the global Carbon event handler has been installed
private var eventHandlerInstalled = false

class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]

    private func ensureEventHandler() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                hotkeyCallbacks[hotkeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    /// Register Cmd+Shift+M as the global hotkey (palette toggle)
    func register(callback: @escaping () -> Void) {
        ensureEventHandler()

        let id: UInt32 = 1
        hotkeyCallbacks[id] = callback

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x444D5558),  // "DMUX"
            id: id
        )

        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            46,  // 'M'
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if let ref { hotKeyRefs[id] = ref }
    }

    /// Register Hyper+1 (Cmd+Ctrl+Option+Shift+1) for command mode
    func registerCommandMode(callback: @escaping () -> Void) {
        ensureEventHandler()
        let id: UInt32 = 200
        hotkeyCallbacks[id] = callback
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x444D5558),  // "DMUX"
            id: id
        )
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            18,  // '1' key
            UInt32(cmdKey | controlKey | optionKey | shiftKey),  // Hyper
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if let ref { hotKeyRefs[id] = ref }
    }

    /// Register Cmd+Option+1/2/3... hotkeys for layer switching
    func registerLayerHotkeys(count: Int, callback: @escaping (Int) -> Void) {
        ensureEventHandler()

        // Key codes for number keys 1-9
        let keyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let limit = min(count, keyCodes.count)

        for i in 0..<limit {
            let id: UInt32 = 101 + UInt32(i)

            // Unregister existing if re-registering
            if let existing = hotKeyRefs[id] {
                UnregisterEventHotKey(existing)
                hotKeyRefs.removeValue(forKey: id)
            }

            let layerIndex = i
            hotkeyCallbacks[id] = { callback(layerIndex) }

            let hotKeyID = EventHotKeyID(
                signature: OSType(0x444D5558),  // "DMUX"
                id: id
            )

            var ref: EventHotKeyRef?
            RegisterEventHotKey(
                keyCodes[i],
                UInt32(cmdKey | optionKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if let ref { hotKeyRefs[id] = ref }
        }
    }
}
