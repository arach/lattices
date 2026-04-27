import Carbon
import AppKit
import Combine

// MARK: - HotkeyGroup

enum HotkeyGroup: String, CaseIterable {
    case app
    case layers
    case tiling
}

// MARK: - HotkeyAction

enum HotkeyAction: String, CaseIterable, Codable {
    // App
    case palette
    case screenMap
    case bezel
    case cheatSheet
    case desktopInventory
    case omniSearch
    case voiceCommand
    case handsOff
    case unifiedWindow
    case hud
    case mouseFinder
    // Layers
    case layer1, layer2, layer3, layer4, layer5, layer6, layer7, layer8, layer9
    case layerNext, layerPrev, layerTag
    // Tiling
    case tileLeft, tileRight, tileMaximize, tileCenter
    case tileTopLeft, tileTopRight, tileBottomLeft, tileBottomRight
    case tileTop, tileBottom, tileDistribute
    case tileLeftThird, tileCenterThird, tileRightThird

    var label: String {
        switch self {
        case .palette:         return "Command Palette"
        case .screenMap:       return "Screen Map"
        case .bezel:           return "Window Bezel"
        case .cheatSheet:      return "Cheat Sheet"
        case .desktopInventory: return "Window Selector"
        case .omniSearch:      return "Search"
        case .voiceCommand:    return "Voice Command"
        case .handsOff:        return "Hands-Off Mode"
        case .unifiedWindow:   return "Workspace Home"
        case .hud:             return "HUD"
        case .mouseFinder:     return "Find Mouse"
        case .layer1:          return "Layer 1"
        case .layer2:          return "Layer 2"
        case .layer3:          return "Layer 3"
        case .layer4:          return "Layer 4"
        case .layer5:          return "Layer 5"
        case .layer6:          return "Layer 6"
        case .layer7:          return "Layer 7"
        case .layer8:          return "Layer 8"
        case .layer9:          return "Layer 9"
        case .layerNext:       return "Next Layer"
        case .layerPrev:       return "Previous Layer"
        case .layerTag:        return "Tag Window"
        case .tileLeft:        return "Tile Left"
        case .tileRight:       return "Tile Right"
        case .tileMaximize:    return "Maximize"
        case .tileCenter:      return "Center"
        case .tileTopLeft:     return "Top Left"
        case .tileTopRight:    return "Top Right"
        case .tileBottomLeft:  return "Bottom Left"
        case .tileBottomRight: return "Bottom Right"
        case .tileTop:         return "Top Half"
        case .tileBottom:      return "Bottom Half"
        case .tileDistribute:  return "Distribute"
        case .tileLeftThird:   return "Left Third"
        case .tileCenterThird: return "Center Third"
        case .tileRightThird:  return "Right Third"
        }
    }

    var group: HotkeyGroup {
        switch self {
        case .palette, .screenMap, .bezel, .cheatSheet, .desktopInventory, .omniSearch, .voiceCommand, .handsOff, .unifiedWindow, .hud, .mouseFinder: return .app
        case .layer1, .layer2, .layer3, .layer4, .layer5,
             .layer6, .layer7, .layer8, .layer9,
             .layerNext, .layerPrev, .layerTag: return .layers
        default: return .tiling
        }
    }

    var carbonID: UInt32 {
        switch self {
        case .palette:         return 1
        case .screenMap:       return 200
        case .bezel:           return 201
        case .cheatSheet:      return 202
        case .desktopInventory: return 203
        case .omniSearch:      return 204
        case .voiceCommand:    return 205
        case .handsOff:        return 206
        case .unifiedWindow:   return 207
        case .hud:             return 208
        case .mouseFinder:     return 209
        case .layer1:          return 101
        case .layer2:          return 102
        case .layer3:          return 103
        case .layer4:          return 104
        case .layer5:          return 105
        case .layer6:          return 106
        case .layer7:          return 107
        case .layer8:          return 108
        case .layer9:          return 109
        case .layerNext:       return 110
        case .layerPrev:       return 111
        case .layerTag:        return 112
        case .tileLeft:        return 300
        case .tileRight:       return 301
        case .tileMaximize:    return 302
        case .tileCenter:      return 303
        case .tileTopLeft:     return 304
        case .tileTopRight:    return 305
        case .tileBottomLeft:  return 306
        case .tileBottomRight: return 307
        case .tileTop:         return 308
        case .tileBottom:      return 309
        case .tileDistribute:  return 310
        case .tileLeftThird:   return 311
        case .tileCenterThird: return 312
        case .tileRightThird:  return 313
        }
    }

    static var layerActions: [HotkeyAction] {
        [.layer1, .layer2, .layer3, .layer4, .layer5, .layer6, .layer7, .layer8, .layer9]
    }
}

// MARK: - KeyBinding

struct KeyBinding: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    var displayParts: [String]

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    static func displayParts(keyCode: UInt32, carbonModifiers: UInt32) -> [String] {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("Option") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("Shift") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("Cmd") }
        parts.append(keyName(for: keyCode))
        return parts
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "Tab", 49: "Space", 50: "`", 51: "Delete",
            53: "Escape",
            65: ".", // numpad
            67: "*", // numpad
            69: "+", // numpad
            71: "Clear", // numpad
            75: "/", // numpad
            76: "Enter", // numpad
            78: "-", // numpad
            82: "0", 83: "1", 84: "2", 85: "3", 86: "4", // numpad
            87: "5", 88: "6", 89: "7", 91: "8", 92: "9", // numpad
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 114: "Help",
            115: "Home", 116: "PgUp", 117: "Del", 118: "F4",
            119: "End", 120: "F2", 121: "PgDn", 122: "F1",
            123: "\u{2190}", // left arrow
            124: "\u{2192}", // right arrow
            125: "\u{2193}", // down arrow
            126: "\u{2191}", // up arrow
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}

// MARK: - HotkeyStore

class HotkeyStore: ObservableObject {
    static let shared = HotkeyStore()

    @Published var bindings: [HotkeyAction: KeyBinding]
    private var callbacks: [HotkeyAction: () -> Void] = [:]

    private func instrumentedCallback(for action: HotkeyAction, callback: @escaping () -> Void) -> () -> Void {
        {
            let timed = DiagnosticLog.shared.startTimed("Hotkey \(action.label)")
            callback()
            DiagnosticLog.shared.finish(timed)
        }
    }

    static let defaultBindings: [HotkeyAction: KeyBinding] = {
        var d = [HotkeyAction: KeyBinding]()
        let hyper = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let cmdShift = UInt32(cmdKey | shiftKey)
        let cmdOpt = UInt32(cmdKey | optionKey)
        let ctrlOpt = UInt32(controlKey | optionKey)

        func bind(_ action: HotkeyAction, _ keyCode: UInt32, _ mods: UInt32) {
            d[action] = KeyBinding(
                keyCode: keyCode,
                carbonModifiers: mods,
                displayParts: KeyBinding.displayParts(keyCode: keyCode, carbonModifiers: mods)
            )
        }

        // App
        bind(.palette,   46, cmdShift)   // Cmd+Shift+M
        bind(.unifiedWindow, 18, hyper)  // Hyper+1 (Workspace Home)
        bind(.bezel,     19, hyper)      // Hyper+2
        bind(.hud,       20, hyper)      // Hyper+3 (HUD overlay)
        bind(.desktopInventory, 5, hyper) // Hyper+G
        bind(.voiceCommand, 21, hyper)   // Hyper+4 (moved from Hyper+3)
        let cmdCtrl = UInt32(cmdKey | controlKey)
        bind(.handsOff, 46, cmdCtrl)          // Ctrl+Cmd+M
        bind(.omniSearch, 23, hyper)       // Hyper+5
        bind(.cheatSheet, 22, hyper)       // Hyper+6
        bind(.mouseFinder, 26, hyper)      // Hyper+7

        // Layers: Cmd+Option+1-9
        let layerKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (i, action) in HotkeyAction.layerActions.enumerated() {
            bind(action, layerKeyCodes[i], cmdOpt)
        }

        // Layer cycling: Cmd+Option+Arrow / Cmd+Option+T
        bind(.layerNext, 124, cmdOpt)  // Cmd+Opt+→
        bind(.layerPrev, 123, cmdOpt)  // Cmd+Opt+←
        bind(.layerTag,   17, cmdOpt)  // Cmd+Opt+T

        // Tiling: Ctrl+Option for all
        bind(.tileLeft,        123, ctrlOpt)  // Ctrl+Opt+←
        bind(.tileRight,       124, ctrlOpt)  // Ctrl+Opt+→
        bind(.tileTop,         126, ctrlOpt)  // Ctrl+Opt+↑
        bind(.tileBottom,      125, ctrlOpt)  // Ctrl+Opt+↓
        bind(.tileMaximize,     36, ctrlOpt)  // Ctrl+Opt+Return
        bind(.tileCenter,        8, ctrlOpt)  // Ctrl+Opt+C
        bind(.tileTopLeft,      32, ctrlOpt)  // Ctrl+Opt+U
        bind(.tileTopRight,     34, ctrlOpt)  // Ctrl+Opt+I
        bind(.tileBottomLeft,   38, ctrlOpt)  // Ctrl+Opt+J
        bind(.tileBottomRight,  40, ctrlOpt)  // Ctrl+Opt+K
        bind(.tileDistribute,    2, ctrlOpt)  // Ctrl+Opt+D
        bind(.tileLeftThird,    18, ctrlOpt)  // Ctrl+Opt+1
        bind(.tileCenterThird,  19, ctrlOpt)  // Ctrl+Opt+2
        bind(.tileRightThird,   20, ctrlOpt)  // Ctrl+Opt+3

        return d
    }()

    private init() {
        // Start with defaults
        var merged = Self.defaultBindings

        // Layer 2: UserDefaults overrides
        let ud = UserDefaults.standard
        for action in HotkeyAction.allCases {
            let key = "hotkey.\(action.rawValue)"
            if let data = ud.data(forKey: key),
               let binding = try? JSONDecoder().decode(KeyBinding.self, from: data) {
                merged[action] = binding
            }
        }

        // Layer 3: ~/.lattices/hotkeys.json overrides
        let jsonPath = NSHomeDirectory() + "/.lattices/hotkeys.json"
        if let data = FileManager.default.contents(atPath: jsonPath),
           let overrides = try? JSONDecoder().decode([String: KeyBinding].self, from: data) {
            for (rawValue, binding) in overrides {
                if let action = HotkeyAction(rawValue: rawValue) {
                    merged[action] = binding
                }
            }
        }

        self.bindings = merged
    }

    // MARK: - Registration

    func register(action: HotkeyAction, callback: @escaping () -> Void) {
        callbacks[action] = callback
        guard let binding = bindings[action] else { return }
        HotkeyManager.shared.registerSingle(
            id: action.carbonID,
            keyCode: binding.keyCode,
            modifiers: binding.carbonModifiers,
            callback: instrumentedCallback(for: action, callback: callback)
        )
    }

    // MARK: - Update

    func updateBinding(for action: HotkeyAction, to binding: KeyBinding) {
        bindings[action] = binding

        // Persist to UserDefaults
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: "hotkey.\(action.rawValue)")
        }

        // Re-register if we have a callback
        if let callback = callbacks[action] {
            HotkeyManager.shared.registerSingle(
                id: action.carbonID,
                keyCode: binding.keyCode,
                modifiers: binding.carbonModifiers,
                callback: instrumentedCallback(for: action, callback: callback)
            )
        }
    }

    // MARK: - Reset

    func resetBinding(for action: HotkeyAction) {
        guard let defaultBinding = Self.defaultBindings[action] else { return }
        UserDefaults.standard.removeObject(forKey: "hotkey.\(action.rawValue)")
        bindings[action] = defaultBinding

        if let callback = callbacks[action] {
            HotkeyManager.shared.registerSingle(
                id: action.carbonID,
                keyCode: defaultBinding.keyCode,
                modifiers: defaultBinding.carbonModifiers,
                callback: instrumentedCallback(for: action, callback: callback)
            )
        }
    }

    func resetAll() {
        for action in HotkeyAction.allCases {
            UserDefaults.standard.removeObject(forKey: "hotkey.\(action.rawValue)")
        }
        bindings = Self.defaultBindings

        // Re-register all with stored callbacks
        for (action, callback) in callbacks {
            guard let binding = bindings[action] else { continue }
            HotkeyManager.shared.registerSingle(
                id: action.carbonID,
                keyCode: binding.keyCode,
                modifiers: binding.carbonModifiers,
                callback: instrumentedCallback(for: action, callback: callback)
            )
        }
    }

    // MARK: - Conflict detection

    func conflicts(for action: HotkeyAction, with binding: KeyBinding) -> HotkeyAction? {
        for (existingAction, existingBinding) in bindings {
            if existingAction != action &&
               existingBinding.keyCode == binding.keyCode &&
               existingBinding.carbonModifiers == binding.carbonModifiers {
                return existingAction
            }
        }
        return nil
    }
}
