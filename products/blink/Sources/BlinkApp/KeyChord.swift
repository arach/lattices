import AppKit
import Carbon

/// A keyboard chord parsed from a config string like `"hyper+n"`,
/// `"cmd+shift+p"`, or `"cmd+."` — one representation that serves both Carbon
/// global hotkey registration (keycode + carbon modifiers) and local
/// `performKeyEquivalent` matching (NSEvent flags + character).
///
/// Grammar: modifier tokens joined by `+`, ending in exactly one key token.
/// Modifiers: `hyper` (⌃⌥⇧⌘), `cmd`/`command`, `ctrl`/`control`,
/// `alt`/`opt`/`option`, `shift`. Keys: a–z, 0–9, common punctuation, and the
/// named keys `space`, `return`, `tab`, `escape`, `delete`. Case-insensitive;
/// spaces around tokens are tolerated.
struct KeyChord: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let eventModifiers: NSEvent.ModifierFlags
    /// What `charactersIgnoringModifiers` reports for this key.
    let matchCharacter: String
    /// Human form for settings rows and help text, e.g. "⌃⌥⇧⌘N".
    let display: String

    static func parse(_ raw: String) -> KeyChord? {
        let tokens = raw.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyToken = tokens.last, !keyToken.isEmpty else { return nil }

        var carbon: UInt32 = 0
        var flags: NSEvent.ModifierFlags = []
        for token in tokens.dropLast() {
            switch token {
            case "hyper":
                carbon |= UInt32(controlKey | optionKey | shiftKey | cmdKey)
                flags.insert([.control, .option, .shift, .command])
            case "cmd", "command", "meta":
                carbon |= UInt32(cmdKey)
                flags.insert(.command)
            case "ctrl", "control":
                carbon |= UInt32(controlKey)
                flags.insert(.control)
            case "alt", "opt", "option":
                carbon |= UInt32(optionKey)
                flags.insert(.option)
            case "shift":
                carbon |= UInt32(shiftKey)
                flags.insert(.shift)
            default:
                return nil
            }
        }

        guard let key = keyTable[keyToken] else { return nil }
        return KeyChord(
            keyCode: key.code,
            carbonModifiers: carbon,
            eventModifiers: flags,
            matchCharacter: key.match,
            display: displayModifiers(flags) + key.display
        )
    }

    /// True when a key event is this chord (for `performKeyEquivalent`).
    func matches(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        guard event.modifierFlags.intersection(relevant) == eventModifiers.intersection(relevant)
        else { return false }
        return (event.charactersIgnoringModifiers?.lowercased() ?? "") == matchCharacter
    }

    private static func displayModifiers(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    private struct Key {
        let code: UInt32
        let match: String
        let display: String
        init(_ code: UInt32, _ match: String, _ display: String? = nil) {
            self.code = code
            self.match = match
            self.display = display ?? match.uppercased()
        }
    }

    /// ANSI-layout keycodes from HIToolbox/Events.h.
    private static let keyTable: [String: Key] = {
        var t: [String: Key] = [
            "a": Key(0, "a"), "b": Key(11, "b"), "c": Key(8, "c"), "d": Key(2, "d"),
            "e": Key(14, "e"), "f": Key(3, "f"), "g": Key(5, "g"), "h": Key(4, "h"),
            "i": Key(34, "i"), "j": Key(38, "j"), "k": Key(40, "k"), "l": Key(37, "l"),
            "m": Key(46, "m"), "n": Key(45, "n"), "o": Key(31, "o"), "p": Key(35, "p"),
            "q": Key(12, "q"), "r": Key(15, "r"), "s": Key(1, "s"), "t": Key(17, "t"),
            "u": Key(32, "u"), "v": Key(9, "v"), "w": Key(13, "w"), "x": Key(7, "x"),
            "y": Key(16, "y"), "z": Key(6, "z"),
            "0": Key(29, "0"), "1": Key(18, "1"), "2": Key(19, "2"), "3": Key(20, "3"),
            "4": Key(21, "4"), "5": Key(23, "5"), "6": Key(22, "6"), "7": Key(26, "7"),
            "8": Key(28, "8"), "9": Key(25, "9"),
            ".": Key(47, "."), ",": Key(43, ","), "/": Key(44, "/"), ";": Key(41, ";"),
            "'": Key(39, "'"), "[": Key(33, "["), "]": Key(30, "]"), "\\": Key(42, "\\"),
            "-": Key(27, "-"), "=": Key(24, "="), "`": Key(50, "`"),
            "space": Key(49, " ", "Space"),
            "return": Key(36, "\r", "↩"),
            "tab": Key(48, "\t", "⇥"),
            "escape": Key(53, "\u{1b}", "⎋"),
            "delete": Key(51, "\u{7f}", "⌫"),
        ]
        t["period"] = t["."]; t["comma"] = t[","]; t["slash"] = t["/"]
        t["enter"] = t["return"]; t["esc"] = t["escape"]
        return t
    }()
}
