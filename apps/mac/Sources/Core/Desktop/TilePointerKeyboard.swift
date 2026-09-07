import Foundation

/// Keyboard aim targets for the Ctrl+Option tile pointer.
///
/// Numpad layout mirrors `TilePointerMatrixHUD.cells`:
/// ```
/// 7 8 9
/// 4 5 6
/// 1 2 3
/// ```
/// The number row (1–9) uses the same matrix when Ctrl+Option is held.
/// Arrow keys tile to an edge; hold two arrows (e.g. ← + ↓) for a corner.
enum TilePointerKeyboard {
    enum Arrow: UInt16, Hashable, CaseIterable {
        case left = 123
        case right = 124
        case down = 125
        case up = 126

        static func from(keyCode: UInt16) -> Arrow? {
            Arrow(rawValue: keyCode)
        }
    }

    /// Numpad and number-row keys that map to the 3×3 matrix.
    static func tilePosition(forMatrixKeyCode keyCode: UInt16) -> TilePosition? {
        switch keyCode {
        // Numpad (HIToolbox kVK_Keypad*)
        case 89: return .topLeft      // keypad 7
        case 91: return .top          // keypad 8
        case 92: return .topRight     // keypad 9
        case 86: return .left         // keypad 4
        case 87: return .maximize     // keypad 5
        case 88: return .right        // keypad 6
        case 83: return .bottomLeft   // keypad 1
        case 84: return .bottom       // keypad 2
        case 85: return .bottomRight  // keypad 3
        // Number row (kVK_ANSI_1–9)
        case 26: return .topLeft      // 7
        case 28: return .top          // 8
        case 25: return .topRight     // 9
        case 21: return .left         // 4
        case 23: return .maximize     // 5
        case 22: return .right        // 6
        case 18: return .bottomLeft   // 1
        case 19: return .bottom       // 2
        case 20: return .bottomRight  // 3
        default: return nil
        }
    }

    static func tilePosition(forArrows arrows: Set<Arrow>) -> TilePosition? {
        let left = arrows.contains(.left)
        let right = arrows.contains(.right)
        let up = arrows.contains(.up)
        let down = arrows.contains(.down)

        switch (left, right, up, down) {
        case (true, false, true, false):   return .topLeft
        case (false, true, true, false):   return .topRight
        case (true, false, false, true):  return .bottomLeft
        case (false, true, false, true):  return .bottomRight
        case (true, false, false, false): return .left
        case (false, true, false, false): return .right
        case (false, false, true, false): return .top
        case (false, false, false, true): return .bottom
        default: return nil
        }
    }
}
