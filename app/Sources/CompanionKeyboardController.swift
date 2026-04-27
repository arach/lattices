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

    func send(key rawKey: String, modifiers rawModifiers: [String]) throws -> String {
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
        down.post(tap: .cghidEventTap)
        usleep(12_000)
        up.post(tap: .cghidEventTap)

        return displayName(key: parsed.key, modifiers: parsed.modifiers)
    }
}

private extension CompanionKeyboardController {
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
