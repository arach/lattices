import AppKit
import ApplicationServices
import HudsonObservability

/// Reads the text selected in the frontmost app, for the reader layer.
///
/// Accessibility's `kAXSelectedTextAttribute` is tried first because it leaves
/// the clipboard alone. Most terminals (Ghostty, kitty, Alacritty) don't expose
/// their selection that way, so the fallback asks the app to copy — by pressing
/// its ⌘C menu item through Accessibility, or, for apps without one, by posting
/// ⌘C once the hotkey's modifiers lift — reads the pasteboard once it changes,
/// then puts every original pasteboard item back. A menu Copy that leaves the
/// pasteboard untouched means the selection is already on it (copy-on-select). Both paths need Accessibility
/// trust; without it the grabber prompts once and reads the clipboard as is.
@MainActor
enum SelectionGrabber {
    enum Source: String {
        case accessibility
        case copy
        case clipboard
    }

    struct Selection {
        let text: String
        let source: Source
        /// The app the text came from.
        let app: NSRunningApplication?
    }

    private static let log = HudLogger(category: "blink.reader")

    static func grab() async -> Selection? {
        let app = NSWorkspace.shared.frontmostApplication
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard AXIsProcessTrusted() else {
            // The constant's value, spelled out: the imported var is not concurrency-safe.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            log.info("[BLINK] reader: accessibility not trusted, reading clipboard")
            return clipboardText().map { Selection(text: $0, source: .clipboard, app: app) }
        }

        if let app, app.processIdentifier != ownPID,
           let text = accessibilitySelection(pid: app.processIdentifier) {
            return Selection(text: text, source: .accessibility, app: app)
        }
        if let text = await copySelection(from: app) {
            return Selection(text: text, source: .copy, app: app)
        }
        return nil
    }

    // MARK: - Accessibility

    private static func accessibilitySelection(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected
        ) == .success,
            let text = selected as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    // MARK: - Synthesized copy

    private static func copySelection(from app: NSRunningApplication?) async -> String? {
        let menuCopy = app.flatMap { copyMenuItem(pid: $0.processIdentifier) }
        if menuCopy == nil, !(await waitForModifierRelease()) {
            // A ⌘C posted while Hyper is still held can arrive as ⌃⌥⇧⌘C.
            log.info("[BLINK] reader: modifiers still held, copying anyway")
        }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount

        var pressedCopy = false
        if let menuCopy {
            pressedCopy = AXUIElementPerformAction(menuCopy, kAXPressAction as CFString) == .success
        } else {
            postCommandC()
        }

        // AX presses run synchronously in the app, so a menu copy has usually
        // landed already; a posted ⌘C still has to travel the event queue.
        let polls = menuCopy == nil ? 50 : 12
        var text: String?
        for _ in 0..<polls {
            try? await Task.sleep(for: .milliseconds(10))
            if pasteboard.changeCount != before {
                text = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before {
            restore(saved, to: pasteboard)
        } else if pressedCopy {
            // An enabled Copy that writes nothing found the selection already
            // there: Ghostty's copy-on-select put it on the clipboard, and it
            // skips re-copying identical text.
            text = clipboardText()
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.info("[BLINK] reader: copy produced no text")
            return nil
        }
        return text
    }

    /// True once no modifier is held; false if they are still down after ~1.5s.
    /// The enabled menu item bound to plain ⌘C (Edit ▸ Copy in any language).
    /// Pressing it copies exactly as the user would, with no synthesized keys.
    private static func copyMenuItem(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let menuBar = element(appElement, kAXMenuBarAttribute) else { return nil }
        // Skip the Apple menu; the app's own menus follow it.
        for barItem in children(menuBar).dropFirst() {
            for menu in children(barItem) {
                for item in children(menu) {
                    guard string(item, kAXMenuItemCmdCharAttribute)?.uppercased() == "C",
                          number(item, kAXMenuItemCmdModifiersAttribute) == 0,  // ⌘ alone
                          number(item, kAXEnabledAttribute) == 1
                    else { continue }
                    return item
                }
            }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func number(_ element: AXUIElement, _ name: String) -> Int? {
        (attribute(element, name) as? NSNumber)?.intValue
    }

    private static func waitForModifierRelease() async -> Bool {
        let held: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        for _ in 0..<150 {
            if NSEvent.modifierFlags.intersection(held).isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private static func postCommandC() {
        // A private source carries only the flags set here, not the keyboard's
        // live modifier state.
        let source = CGEventSource(stateID: .privateState)
        let keyC: CGKeyCode = 8
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func clipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    // MARK: - Pasteboard save/restore

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
