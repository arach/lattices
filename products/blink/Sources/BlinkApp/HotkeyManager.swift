import AppKit
import Carbon
import Foundation

// Minimal Carbon hotkey wrapper, transplanted from Scout
// (openscout/apps/macos/Sources/ScoutHUD/HotkeyManager.swift), which itself
// is modeled on lattices' HotkeyManager. RegisterEventHotKey needs no
// accessibility permission — unlike v1's event-tap approach.

@MainActor private var hotkeyCallbacks: [UInt32: () -> Void] = [:]
@MainActor private var eventHandlerInstalled = false

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]

    private init() {}

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
                // Carbon hotkey events are delivered on the main thread;
                // hop to MainActor to satisfy strict concurrency checking.
                let id = hotkeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        hotkeyCallbacks[id]?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    @discardableResult
    public func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        callback: @escaping () -> Void
    ) -> Bool {
        ensureEventHandler()

        if let existing = hotKeyRefs[id] {
            UnregisterEventHotKey(existing)
            hotKeyRefs.removeValue(forKey: id)
        }

        hotkeyCallbacks[id] = callback

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x424C_4E4B),  // "BLNK"
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
        if let ref, status == noErr {
            hotKeyRefs[id] = ref
            return true
        }
        return false
    }

    public func unregister(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
            hotkeyCallbacks.removeValue(forKey: id)
        }
    }

    public func unregisterAll() {
        for (id, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
            hotkeyCallbacks.removeValue(forKey: id)
            _ = id
        }
        hotKeyRefs.removeAll()
    }
}

// Convenience: Hyper = ⌃⌥⇧⌘
public enum CarbonModifier {
    public static let hyper: UInt32 = UInt32(controlKey | optionKey | shiftKey | cmdKey)
}

// Common keyCodes. Source: HIToolbox/Events.h.
public enum CarbonKeyCode {
    public static let n: UInt32 = 45
    public static let k: UInt32 = 40
    public static let b: UInt32 = 11
}
