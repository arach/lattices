import AppKit
import ApplicationServices
import HudsonObservability

/// Reads the text selected in the frontmost app, for the reader layer.
///
/// Accessibility's `kAXSelectedTextAttribute` is tried first because it leaves
/// the clipboard alone. Most terminals (Ghostty, kitty, Alacritty) don't expose
/// their selection that way, so the fallback asks the app to copy: wait for the
/// hotkey's modifiers to lift, post ⌘C, read the pasteboard once it changes,
/// then put every original pasteboard item back. Both paths need Accessibility
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
        if let text = await copySelection() {
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

    private static func copySelection() async -> String? {
        // A ⌘C posted while Hyper is still held arrives as ⌃⌥⇧⌘C.
        await waitForModifierRelease()

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount

        postCommandC()

        var text: String?
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(10))
            if pasteboard.changeCount != before {
                text = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before {
            restore(saved, to: pasteboard)
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.info("[BLINK] reader: copy produced no text")
            return nil
        }
        return text
    }

    private static func waitForModifierRelease() async {
        let held: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        for _ in 0..<50 where !NSEvent.modifierFlags.intersection(held).isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
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
