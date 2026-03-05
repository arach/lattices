import Carbon
import AppKit
import Foundation

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

    /// Register Hyper+2 (Cmd+Ctrl+Option+Shift+2) for bezel mode
    func registerBezelHotkey(callback: @escaping () -> Void) {
        ensureEventHandler()
        let id: UInt32 = 201
        hotkeyCallbacks[id] = callback
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x444D5558),  // "DMUX"
            id: id
        )
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            19,  // '2' key
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

    /// Register a single global hotkey with a given ID, key code, and Carbon modifier mask
    func registerSingle(id: UInt32, keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        ensureEventHandler()

        if let existing = hotKeyRefs[id] {
            UnregisterEventHotKey(existing)
            hotKeyRefs.removeValue(forKey: id)
        }

        hotkeyCallbacks[id] = callback

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x444D5558),  // "DMUX"
            id: id
        )

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if let ref {
            hotKeyRefs[id] = ref
        } else {
            DiagnosticLog.shared.warn("HotkeyManager: failed to register id=\(id) keyCode=\(keyCode) mods=\(modifiers) status=\(status)")
        }
    }

    /// Unregister all global hotkeys and clear callbacks
    func unregisterAll() {
        for (id, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
            hotkeyCallbacks.removeValue(forKey: id)
        }
        hotKeyRefs.removeAll()
    }

    /// Register Ctrl+Option window tiling hotkeys (Magnet-style)
    func registerTileHotkeys() {
        let mods = UInt32(controlKey | optionKey)

        // Ctrl+Option+← → left
        registerSingle(id: 300, keyCode: 123, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .left)
        }
        // Ctrl+Option+→ → right
        registerSingle(id: 301, keyCode: 124, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .right)
        }
        // Ctrl+Option+Return → maximize
        registerSingle(id: 302, keyCode: 36, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .maximize)
        }
        // Ctrl+Option+C → center
        registerSingle(id: 303, keyCode: 8, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .center)
        }
        // Ctrl+Option+U → top-left
        registerSingle(id: 304, keyCode: 32, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .topLeft)
        }
        // Ctrl+Option+I → top-right
        registerSingle(id: 305, keyCode: 34, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .topRight)
        }
        // Ctrl+Option+J → bottom-left
        registerSingle(id: 306, keyCode: 38, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .bottomLeft)
        }
        // Ctrl+Option+K → bottom-right
        registerSingle(id: 307, keyCode: 40, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .bottomRight)
        }
        // Ctrl+Option+↑ → top
        registerSingle(id: 308, keyCode: 126, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .top)
        }
        // Ctrl+Option+↓ → bottom
        registerSingle(id: 309, keyCode: 125, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .bottom)
        }
        // Ctrl+Option+D → distribute visible windows
        registerSingle(id: 310, keyCode: 2, modifiers: mods) {
            WindowTiler.distributeVisible()
        }
        // Ctrl+Option+1 → left third
        registerSingle(id: 311, keyCode: 18, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .leftThird)
        }
        // Ctrl+Option+2 → center third
        registerSingle(id: 312, keyCode: 19, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .centerThird)
        }
        // Ctrl+Option+3 → right third
        registerSingle(id: 313, keyCode: 20, modifiers: mods) {
            WindowTiler.tileFrontmostViaAX(to: .rightThird)
        }
    }
}
