import AppKit
import Foundation

enum CompanionKeyboardError: LocalizedError {
    case unknownKey(String)
    case eventSourceUnavailable

    var errorDescription: String? {
        switch self {
        case .unknownKey(let key):
            return "Unsupported key for forwarding: \(key)"
        case .eventSourceUnavailable:
            return "Unable to create a keyboard event source."
        }
    }
}

final class CompanionKeyboardController {
    static let shared = CompanionKeyboardController()

    private init() {}

    func send(key rawKey: String, modifiers rawModifiers: [String], targetPid: pid_t? = nil) throws -> String {
        let parsed = parse(key: rawKey, modifiers: rawModifiers)
        guard let keyCode = keyCode(for: parsed.key) else {
            throw CompanionKeyboardError.unknownKey(rawKey)
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw CompanionKeyboardError.eventSourceUnavailable
        }

        let flags = eventFlags(for: parsed.modifiers)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw CompanionKeyboardError.eventSourceUnavailable
        }

        down.flags = flags
        up.flags = flags
        post(down, targetPid: targetPid)
        usleep(12_000)
        post(up, targetPid: targetPid)

        return displayName(key: parsed.key, modifiers: parsed.modifiers)
    }

    func typeText(_ text: String, targetPid: pid_t? = nil, intervalMicros: useconds_t = 9_000) throws -> Int {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw CompanionKeyboardError.eventSourceUnavailable
        }

        if text.count > 1 {
            try pasteText(text, source: source, targetPid: targetPid)
            return text.count
        }

        var typed = 0
        for character in text {
            if let stroke = keystroke(for: character) {
                try postKey(
                    source: source,
                    keyCode: stroke.keyCode,
                    flags: stroke.flags,
                    targetPid: targetPid,
                    intervalMicros: intervalMicros
                )
            } else {
                try postUnicode(
                    source: source,
                    text: String(character),
                    intervalMicros: intervalMicros
                )
            }
            usleep(intervalMicros)
            typed += 1
        }
        return typed
    }
}

private extension CompanionKeyboardController {
    struct SavedPasteboardItem {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    func parse(key rawKey: String, modifiers rawModifiers: [String]) -> (key: String, modifiers: Set<String>) {
        var modifiers = Set(rawModifiers.map(normalizeModifier).filter { !$0.isEmpty })
        var key = rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let symbolModifiers: [(String, String)] = [
            ("⌘", "command"),
            ("cmd", "command"),
            ("command", "command"),
            ("⌥", "option"),
            ("option", "option"),
            ("alt", "option"),
            ("⌃", "control"),
            ("ctrl", "control"),
            ("control", "control"),
            ("⇧", "shift"),
            ("shift", "shift"),
        ]

        for (symbol, modifier) in symbolModifiers where key.contains(symbol) {
            modifiers.insert(modifier)
            key = key.replacingOccurrences(of: symbol, with: "")
        }

        key = key
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "⎋", with: "escape")
            .replacingOccurrences(of: "⇥", with: "tab")
            .replacingOccurrences(of: "↩", with: "enter")
            .replacingOccurrences(of: "⏎", with: "enter")
            .replacingOccurrences(of: "return", with: "enter")
            .replacingOccurrences(of: "←", with: "left")
            .replacingOccurrences(of: "→", with: "right")
            .replacingOccurrences(of: "↑", with: "up")
            .replacingOccurrences(of: "↓", with: "down")

        if key == "esc" {
            key = "escape"
        }

        return (key.isEmpty ? rawKey.lowercased() : key, modifiers)
    }

    func normalizeModifier(_ modifier: String) -> String {
        switch modifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cmd", "command", "meta", "⌘":
            return "command"
        case "opt", "option", "alt", "⌥":
            return "option"
        case "ctrl", "control", "⌃":
            return "control"
        case "shift", "⇧":
            return "shift"
        default:
            return ""
        }
    }

    func eventFlags(for modifiers: Set<String>) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains("command") { flags.insert(.maskCommand) }
        if modifiers.contains("option") { flags.insert(.maskAlternate) }
        if modifiers.contains("control") { flags.insert(.maskControl) }
        if modifiers.contains("shift") { flags.insert(.maskShift) }
        return flags
    }

    func keystroke(for character: Character) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        let shifted: [Character: Character] = [
            "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
            "&": "7", "*": "8", "(": "9", ")": "0", "_": "-", "+": "=",
            "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",",
            ">": ".", "?": "/", "~": "`",
        ]

        if character == " " {
            return (49, [])
        }
        if character == "\n" || character == "\r" {
            return (36, [])
        }

        let text = String(character)
        if text.count == 1, let scalar = text.unicodeScalars.first {
            let raw = Character(String(scalar))
            if let base = shifted[raw],
               let keyCode = keyCode(for: String(base)) {
                return (keyCode, [.maskShift])
            }
            let lower = text.lowercased()
            if let keyCode = keyCode(for: lower) {
                let flags: CGEventFlags = text == lower ? [] : [.maskShift]
                return (keyCode, flags)
            }
        }

        return nil
    }

    func postKey(
        source: CGEventSource,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        targetPid: pid_t? = nil,
        intervalMicros: useconds_t
    ) throws {
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw CompanionKeyboardError.eventSourceUnavailable
        }

        down.flags = flags
        up.flags = flags
        post(down, targetPid: targetPid)
        usleep(max(1_000, intervalMicros / 2))
        post(up, targetPid: targetPid)
    }

    func pasteText(_ text: String, source: CGEventSource, targetPid: pid_t?) throws {
        let pasteboard = NSPasteboard.general
        let savedItems = savePasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try postKey(
            source: source,
            keyCode: 9,
            flags: [.maskCommand],
            targetPid: targetPid,
            intervalMicros: 12_000
        )

        usleep(240_000)
        restorePasteboard(pasteboard, savedItems: savedItems)
    }

    func savePasteboard(_ pasteboard: NSPasteboard) -> [SavedPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let values = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return SavedPasteboardItem(values: values)
        }
    }

    func restorePasteboard(_ pasteboard: NSPasteboard, savedItems: [SavedPasteboardItem]) {
        pasteboard.clearContents()
        let restored = savedItems.map { saved -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for value in saved.values {
                item.setData(value.data, forType: value.type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }

    func postUnicode(
        source: CGEventSource,
        text: String,
        intervalMicros: useconds_t
    ) throws {
        var units = Array(text.utf16)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            throw CompanionKeyboardError.eventSourceUnavailable
        }

        units.withUnsafeMutableBufferPointer { buffer in
            down.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            up.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        down.post(tap: .cghidEventTap)
        usleep(max(1_000, intervalMicros / 2))
        up.post(tap: .cghidEventTap)
    }

    func post(_ event: CGEvent, targetPid: pid_t?) {
        if let targetPid {
            event.postToPid(targetPid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    func keyCode(for key: String) -> CGKeyCode? {
        let codes: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "enter": 36,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
            "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
            "`": 50, "delete": 51, "backspace": 51, "escape": 53,
            "command": 55, "cmd": 55, "shift": 56, "capslock": 57, "option": 58,
            "alt": 58, "control": 59, "left": 123, "right": 124, "down": 125,
            "up": 126,
        ]
        return codes[key]
    }

    func displayName(key: String, modifiers: Set<String>) -> String {
        let ordered = ["control", "option", "shift", "command"].filter { modifiers.contains($0) }
        return (ordered + [key]).joined(separator: "+")
    }
}
