import AppKit
import Foundation

/// An OS permission Lattices can ask for. The Permissions Assistant introduces
/// these and only requests the underlying grant when the user explicitly opts
/// in. Product configuration like Pi/provider auth is intentionally excluded —
/// that lives in the Chat/Pi surface, not here.
enum Capability: String, CaseIterable, Identifiable {
    case windowControl   // macOS Accessibility — tiling, focus, snap
    case screenSearch    // macOS Screen Recording — OCR / on-screen text search
    case voiceCapture    // macOS Microphone — dictation / voice commands

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowControl: return "Tiling & focus"
        case .screenSearch:  return "Screen text search"
        case .voiceCapture:  return "Voice capture"
        }
    }

    var iconName: String {
        switch self {
        case .windowControl: return "rectangle.3.group"
        case .screenSearch:  return "text.viewfinder"
        case .voiceCapture:  return "waveform"
        }
    }

    var requirementLabel: String {
        switch self {
        case .windowControl: return "Accessibility"
        case .screenSearch:  return "Screen & System Audio Recording"
        case .voiceCapture:  return "Microphone"
        }
    }

    var pitch: String {
        switch self {
        case .windowControl:
            return "Move, resize, snap, and arrange windows from the menu bar, command palette, and gestures."
        case .screenSearch:
            return "Index on-screen text with OCR so the omni search can jump to any window by what it shows."
        case .voiceCapture:
            return "Use local dictation and voice commands through the embedded voice engine hosted by Lattices."
        }
    }

    var why: String {
        switch self {
        case .windowControl:
            return "macOS Accessibility lets Lattices read window titles and move or resize windows. No keystrokes are recorded."
        case .screenSearch:
            return "Screen Recording lets Lattices read pixels to OCR what is on-screen. Captures stay on this Mac."
        case .voiceCapture:
            return "macOS Microphone access lets Lattices capture audio only when you start dictation or a voice command."
        }
    }

    /// Optional one-liner shown when the capability is on, summarising current behavior.
    var whenGrantedDetail: String {
        switch self {
        case .windowControl: return "Lattices can move and tile windows."
        case .screenSearch:  return "OCR can index visible windows for omni search."
        case .voiceCapture:  return "Lattices can listen when you start dictation or a voice command."
        }
    }

    /// Live status — read directly from the system, never cached.
    var isGranted: Bool {
        switch self {
        case .windowControl: return PermissionChecker.shared.accessibility
        case .screenSearch:  return PermissionChecker.shared.screenRecording
        case .voiceCapture:  return PermissionChecker.shared.microphoneGranted
        }
    }

    var usesDragRepair: Bool {
        switch self {
        case .windowControl, .screenSearch:
            return true
        case .voiceCapture:
            return false
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
