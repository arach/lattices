import ApplicationServices
import AppKit
import Foundation
import IOKit.hid

public enum LatticesPermission: String, Codable, CaseIterable, Hashable, Sendable {
    case accessibility
    case screenRecording = "screen-recording"
    case inputMonitoring = "input-monitoring"

    public static func parse(_ raw: String) -> LatticesPermission? {
        switch raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        {
        case "accessibility", "ax":
            return .accessibility
        case "screen-recording", "screenrecording", "screen-capture", "screencapture", "screenshots", "screen":
            return .screenRecording
        case "input-monitoring", "inputmonitoring", "listen-event", "listenevent", "hotkeys":
            return .inputMonitoring
        default:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .screenRecording:
            return "Screen Recording"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    public var detail: String {
        switch self {
        case .accessibility:
            return "Read, focus, raise, move, and resize app windows."
        case .screenRecording:
            return "Read window titles and capture visual state for navigation."
        case .inputMonitoring:
            return "Register and observe global keyboard shortcuts."
        }
    }

    public var settingsURL: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }
}

public enum LatticesPermissionGrantState: String, Codable, Equatable, Sendable {
    case granted
    case notGranted = "not-granted"
    case denied
    case unknown
    case unsupported
}

public struct LatticesPermissionStatus: Codable, Equatable, Sendable {
    public var permission: LatticesPermission
    public var state: LatticesPermissionGrantState
    public var title: String
    public var detail: String
    public var settingsURL: String
    public var nextStep: String?

    public var isGranted: Bool {
        state == .granted
    }
}

public enum LatticesFeature: String, Codable, CaseIterable, Hashable, Sendable {
    case tmux
    case sessionNavigation = "session-navigation"
    case windowManagement = "window-management"
    case computerUse = "computer-use"
    case globalHotkeys = "global-hotkeys"

    public static func parse(_ raw: String) -> LatticesFeature? {
        switch raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        {
        case "tmux":
            return .tmux
        case "session-navigation", "sessionnavigation", "navigation", "sessions":
            return .sessionNavigation
        case "window-management", "windowmanagement", "windows", "tiling":
            return .windowManagement
        case "computer-use", "computeruse", "accessibility-tree", "computer":
            return .computerUse
        case "global-hotkeys", "globalhotkeys", "hotkeys", "shortcuts":
            return .globalHotkeys
        default:
            return nil
        }
    }

    public var requiredPermissions: [LatticesPermission] {
        switch self {
        case .tmux:
            return []
        case .sessionNavigation:
            return [.accessibility, .screenRecording]
        case .windowManagement:
            return [.accessibility]
        case .computerUse:
            return [.accessibility, .screenRecording]
        case .globalHotkeys:
            return [.inputMonitoring]
        }
    }
}

public struct LatticesPermissionReadiness: Codable, Equatable, Sendable {
    public var hostBundleIdentifier: String?
    public var hostDisplayName: String
    public var features: [LatticesFeature]
    public var permissions: [LatticesPermissionStatus]
    public var missing: [LatticesPermission]
    public var isReady: Bool
    public var nextStep: String?
}

public final class LatticesPermissions: Sendable {
    public init() {}

    public var hostBundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    public var hostDisplayName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return ProcessInfo.processInfo.processName
    }

    public func status(for permission: LatticesPermission) -> LatticesPermissionStatus {
        let state: LatticesPermissionGrantState
        switch permission {
        case .accessibility:
            state = AXIsProcessTrusted() ? .granted : .notGranted
        case .screenRecording:
            state = CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .inputMonitoring:
            state = inputMonitoringState()
        }

        return LatticesPermissionStatus(
            permission: permission,
            state: state,
            title: permission.title,
            detail: permission.detail,
            settingsURL: permission.settingsURL.absoluteString,
            nextStep: nextStep(for: permission, state: state)
        )
    }

    public func statuses(
        for permissions: [LatticesPermission] = LatticesPermission.allCases
    ) -> [LatticesPermissionStatus] {
        permissions.map(status(for:))
    }

    public func readiness(
        for features: [LatticesFeature] = LatticesFeature.allCases
    ) -> LatticesPermissionReadiness {
        let required = uniquePermissions(features.flatMap(\.requiredPermissions))
        let statuses = statuses(for: required)
        let missing = statuses
            .filter { !$0.isGranted }
            .map(\.permission)
        return LatticesPermissionReadiness(
            hostBundleIdentifier: hostBundleIdentifier,
            hostDisplayName: hostDisplayName,
            features: features,
            permissions: statuses,
            missing: missing,
            isReady: missing.isEmpty,
            nextStep: statuses.first(where: { !$0.isGranted })?.nextStep
        )
    }

    @discardableResult
    public func request(_ permission: LatticesPermission, openSettingsWhenNeeded: Bool = true) -> Bool {
        let granted: Bool
        switch permission {
        case .accessibility:
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            granted = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            granted = CGRequestScreenCaptureAccess()
        case .inputMonitoring:
            granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        if !granted && openSettingsWhenNeeded {
            openSettings(for: permission)
        }
        return granted
    }

    @discardableResult
    public func openSettings(for permission: LatticesPermission) -> Bool {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    private func inputMonitoringState() -> LatticesPermissionGrantState {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        case kIOHIDAccessTypeUnknown:
            return .unknown
        default:
            return .notGranted
        }
    }

    private func nextStep(
        for permission: LatticesPermission,
        state: LatticesPermissionGrantState
    ) -> String? {
        guard state != .granted else {
            return nil
        }
        return "Grant \(permission.title) to \(hostDisplayName), then retry the Lattices capability."
    }

    private func uniquePermissions(_ permissions: [LatticesPermission]) -> [LatticesPermission] {
        var seen = Set<LatticesPermission>()
        var ordered: [LatticesPermission] = []
        for permission in permissions where !seen.contains(permission) {
            seen.insert(permission)
            ordered.append(permission)
        }
        return ordered
    }
}
