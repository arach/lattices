import AppKit
import Foundation

/// An OS permission Lattices can ask for. The Permissions Assistant introduces
/// these and only requests the underlying grant when the user explicitly opts
/// in. Product configuration like Pi/provider auth is intentionally excluded —
/// that lives in the Chat/Pi surface, not here.
enum Capability: String, CaseIterable, Identifiable {
    case windowControl   // macOS Accessibility — tiling, focus, snap
    case screenSearch    // macOS Screen Recording — OCR / on-screen text search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowControl: return "Tiling & focus"
        case .screenSearch:  return "Screen text search"
        }
    }

    var iconName: String {
        switch self {
        case .windowControl: return "rectangle.3.group"
        case .screenSearch:  return "text.viewfinder"
        }
    }

    var requirementLabel: String {
        switch self {
        case .windowControl: return "Accessibility"
        case .screenSearch:  return "Screen & System Audio Recording"
        }
    }

    var pitch: String {
        switch self {
        case .windowControl:
            return "Move, resize, snap, and arrange windows from the menu bar, command palette, and gestures."
        case .screenSearch:
            return "Index on-screen text with OCR so the omni search can jump to any window by what it shows."
        }
    }

    var why: String {
        switch self {
        case .windowControl:
            return "macOS Accessibility lets Lattices read window titles and move or resize windows. No keystrokes are recorded."
        case .screenSearch:
            return "Screen Recording lets Lattices read pixels to OCR what is on-screen. Captures stay on this Mac."
        }
    }

    /// Optional one-liner shown when the capability is on, summarising current behavior.
    var whenGrantedDetail: String {
        switch self {
        case .windowControl: return "Lattices can move and tile windows."
        case .screenSearch:  return "OCR can index visible windows for omni search."
        }
    }

    /// Live status — read directly from the system, never cached.
    var isGranted: Bool {
        switch self {
        case .windowControl: return PermissionChecker.shared.accessibility
        case .screenSearch:  return PermissionChecker.shared.screenRecording
        }
    }

    /// All capabilities that are not yet granted.
    static var missing: [Capability] {
        Capability.allCases.filter { !$0.isGranted }
    }

    /// Capabilities that are missing AND have not been dismissed-for-now.
    static var visiblyMissing: [Capability] {
        let dismissed = Preferences.shared.dismissedCapabilities
        return missing.filter { !dismissed.contains($0.rawValue) }
    }
}
