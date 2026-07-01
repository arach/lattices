import ApplicationServices
import AppKit
import CoreGraphics
import CryptoKit
import Foundation

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

public enum EmbeddedLatticesError: LocalizedError, Equatable, Sendable {
    case commandFailed(command: String, status: Int32, stderr: String)
    case invalidConfig(String)
    case missingTmux
    case sessionNotFound(String)
    case windowNotFound(String)
    case accessibilityUnavailable

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let status, let stderr):
            return "\(command) failed with status \(status): \(stderr)"
        case .invalidConfig(let message):
            return "Invalid Lattices config: \(message)"
        case .missingTmux:
            return "tmux is not available on PATH."
        case .sessionNotFound(let session):
            return "Lattices session not found: \(session)"
        case .windowNotFound(let target):
            return "Lattices window not found: \(target)"
        case .accessibilityUnavailable:
            return "Accessibility access is unavailable for this host app."
        }
    }
}

public final class Lattices: Sendable {
    public let tmux: EmbeddedLatticesTmux
    public let windows: EmbeddedLatticesWindows
    public let accessibility: EmbeddedLatticesAccessibility
    public let input: EmbeddedLatticesInput
    public let sessions: EmbeddedLatticesSessions
    public let permissions: LatticesPermissions

    public init() {
        let tmux = EmbeddedLatticesTmux()
        let windows = EmbeddedLatticesWindows()
        let accessibility = EmbeddedLatticesAccessibility(windows: windows)
        let input = EmbeddedLatticesInput(windows: windows)
        let permissions = LatticesPermissions()

        self.tmux = tmux
        self.windows = windows
        self.accessibility = accessibility
        self.input = input
        self.sessions = EmbeddedLatticesSessions(tmux: tmux, windows: windows)
        self.permissions = permissions
    }

    public func sessionName(for path: String) -> String {
        tmux.sessionName(for: path)
    }

    public func installedCapabilities() -> EmbeddedLatticesCapabilities {
        EmbeddedLatticesCapabilities(
            tmuxAvailable: tmux.isTmuxAvailable(),
            screenRecordingLikelyAvailable: !windows.list().isEmpty,
            accessibilityTrusted: AXIsProcessTrusted(),
            skyLightAvailable: EmbeddedSkyLight.isAvailable,
            hostBundleIdentifier: permissions.hostBundleIdentifier,
            hostDisplayName: permissions.hostDisplayName,
            permissionStatuses: permissions.statuses()
        )
    }

    public func capabilities() -> LatticesCapabilities {
        installedCapabilities()
    }

    public func readiness(
        for features: [LatticesFeature] = LatticesFeature.allCases
    ) -> LatticesPermissionReadiness {
        permissions.readiness(for: features)
    }

    public func start() -> LatticesStatus {
        LatticesStatus(
            state: .running,
            capabilities: installedCapabilities()
        )
    }

    public func stop() -> LatticesStatus {
        LatticesStatus(
            state: .stopped,
            capabilities: installedCapabilities()
        )
    }

    public func handle(_ request: LatticesRequest) -> LatticesResponse {
        do {
            let result = try dispatch(method: request.method, params: request.params)
            return LatticesResponse(id: request.id, result: result, error: nil)
        } catch {
            return LatticesResponse(id: request.id, result: nil, error: error.localizedDescription)
        }
    }

    public func dispatch(method: String, params: JSONValue? = nil) throws -> JSONValue {
        switch method {
        case "server.status", "lattices.status":
            return try JSONValue.encode(start())
        case "server.capabilities", "lattices.capabilities":
            return try JSONValue.encode(installedCapabilities())
        case "permissions.status", "tcc.status":
            if let permission = optionalPermission(params) {
                return try JSONValue.encode(permissions.status(for: permission))
            }
            return try JSONValue.encode(permissions.statuses())
        case "permissions.readiness", "tcc.readiness":
            return try JSONValue.encode(permissions.readiness(for: optionalFeatures(params)))
        case "permissions.request", "tcc.request":
            let permission = try requiredPermission(params)
            return .object(["granted": .bool(permissions.request(permission))])
        case "permissions.openSettings", "tcc.openSettings":
            let permission = try requiredPermission(params)
            return .object(["opened": .bool(permissions.openSettings(for: permission))])
        case "windows.list":
            return try JSONValue.encode(windows.list())
        case "windows.get":
            let wid = try requiredInt(params, "wid")
            guard let window = windows.resolve(.window(wid)) else {
                throw EmbeddedLatticesError.windowNotFound("wid \(wid)")
            }
            return try JSONValue.encode(window)
        case "window.resolve":
            let target = try decodeTarget(params)
            guard let window = windows.resolve(target) else {
                return .null
            }
            return try JSONValue.encode(window)
        case "window.focus":
            let target = try decodeTarget(params)
            return .object(["ok": .bool(try windows.focus(target))])
        case "window.tile":
            let target = try decodeTarget(params)
            let position = try tilePosition(params)
            return .object(["ok": .bool(try windows.tile(target, position: position))])
        case "tmux.sessions":
            return try JSONValue.encode(tmux.listSessions())
        case "session.name":
            return .string(sessionName(for: try requiredString(params, "path")))
        case "session.launch":
            let session = try sessions.launch(path: try requiredString(params, "path"))
            return .object(["ok": .bool(true), "session": .string(session)])
        case "session.kill":
            return .object(["ok": .bool(try sessions.kill(name: try requiredString(params, "name")))])
        case "session.detach":
            return .object(["ok": .bool(try sessions.detach(name: try requiredString(params, "name")))])
        case "session.restart":
            return .object([
                "ok": .bool(try sessions.restart(
                    path: try requiredString(params, "path"),
                    pane: optionalString(params, "pane")
                ))
            ])
        case "accessibility.snapshot", "computer.windowState":
            return try JSONValue.encode(accessibility.snapshot(target: try decodeTarget(params)))
        case "input.hotkey", "computer.hotkey":
            let shortcut = try requiredString(params, "shortcut")
            return .object(["ok": .bool(try input.hotkey(shortcut, target: optionalTarget(params)))])
        case "input.click", "computer.click":
            let target = try decodeTarget(params)
            let xRatio = optionalDouble(params, "xRatio") ?? 0.5
            let yRatio = optionalDouble(params, "yRatio") ?? 0.5
            return .object(["ok": .bool(try input.click(target: target, xRatio: xRatio, yRatio: yRatio))])
        case "input.pasteText", "computer.typeWindowText":
            let text = try requiredString(params, "text")
            return .object(["ok": .bool(try input.pasteText(text, target: optionalTarget(params)))])
        default:
            throw EmbeddedLatticesError.invalidConfig("Unknown embedded Lattices method: \(method)")
        }
    }

    private func decodeTarget(_ params: JSONValue?) throws -> LatticesWindowTarget {
        if let wid = optionalInt(params, "wid") {
            return .window(wid)
        }
        if let session = optionalString(params, "session") {
            return .session(session)
        }
        if let app = optionalString(params, "app") {
            return .app(app, title: optionalString(params, "title"))
        }
        if let target = params?["target"] {
            return try decodeTarget(target)
        }
        return LatticesWindowTarget()
    }

    private func optionalTarget(_ params: JSONValue?) throws -> LatticesWindowTarget? {
        guard params?["wid"] != nil || params?["session"] != nil || params?["app"] != nil || params?["target"] != nil else {
            return nil
        }
        return try decodeTarget(params)
    }

    private func tilePosition(_ params: JSONValue?) throws -> LatticesTilePosition {
        let raw = optionalString(params, "position") ?? optionalString(params, "placement") ?? "center"
        guard let position = LatticesTilePosition(rawValue: raw) else {
            throw EmbeddedLatticesError.invalidConfig("Unknown tile position: \(raw)")
        }
        return position
    }

    private func requiredString(_ params: JSONValue?, _ key: String) throws -> String {
        guard let value = optionalString(params, key), !value.isEmpty else {
            throw EmbeddedLatticesError.invalidConfig("Missing required parameter: \(key)")
        }
        return value
    }

    private func requiredInt(_ params: JSONValue?, _ key: String) throws -> Int {
        guard let value = optionalInt(params, key) else {
            throw EmbeddedLatticesError.invalidConfig("Missing required parameter: \(key)")
        }
        return value
    }

    private func optionalString(_ params: JSONValue?, _ key: String) -> String? {
        params?[key]?.stringValue
    }

    private func optionalInt(_ params: JSONValue?, _ key: String) -> Int? {
        params?[key]?.intValue
    }

    private func optionalDouble(_ params: JSONValue?, _ key: String) -> Double? {
        params?[key]?.doubleValue
    }

    private func requiredPermission(_ params: JSONValue?) throws -> LatticesPermission {
        guard let permission = optionalPermission(params) else {
            throw EmbeddedLatticesError.invalidConfig("Missing required parameter: permission")
        }
        return permission
    }

    private func optionalPermission(_ params: JSONValue?) -> LatticesPermission? {
        let raw = optionalString(params, "permission")
            ?? optionalString(params, "id")
            ?? params?.stringValue
        return raw.flatMap(LatticesPermission.parse)
    }

    private func optionalFeatures(_ params: JSONValue?) -> [LatticesFeature] {
        let values = params?["features"]?.arrayValue ?? params?.arrayValue ?? []
        let features = values.compactMap { value in
            value.stringValue.flatMap(LatticesFeature.parse)
        }
        return features.isEmpty ? LatticesFeature.allCases : features
    }
}

@available(*, deprecated, renamed: "Lattices")
public typealias LatticesServer = Lattices

@available(*, deprecated, renamed: "Lattices")
public typealias EmbeddedLatticesClient = Lattices

public struct EmbeddedLatticesCapabilities: Codable, Equatable, Sendable {
    public var tmuxAvailable: Bool
    public var screenRecordingLikelyAvailable: Bool
    public var accessibilityTrusted: Bool
    public var skyLightAvailable: Bool
    public var hostBundleIdentifier: String?
    public var hostDisplayName: String
    public var permissionStatuses: [LatticesPermissionStatus]
}

public typealias LatticesCapabilities = EmbeddedLatticesCapabilities

public enum LatticesState: String, Codable, Equatable, Sendable {
    case stopped
    case running
}

@available(*, deprecated, renamed: "LatticesState")
public typealias LatticesServerState = LatticesState

public struct LatticesStatus: Codable, Equatable, Sendable {
    public var state: LatticesState
    public var capabilities: EmbeddedLatticesCapabilities
}

@available(*, deprecated, renamed: "LatticesStatus")
public typealias LatticesServerStatus = LatticesStatus

public struct LatticesRequest: Codable, Equatable, Sendable {
    public var id: String
    public var method: String
    public var params: JSONValue?

    public init(id: String = UUID().uuidString, method: String, params: JSONValue? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

@available(*, deprecated, renamed: "LatticesRequest")
public typealias LatticesServerRequest = LatticesRequest

public struct LatticesResponse: Codable, Equatable, Sendable {
    public var id: String
    public var result: JSONValue?
    public var error: String?
}

@available(*, deprecated, renamed: "LatticesResponse")
public typealias LatticesServerResponse = LatticesResponse

public final class EmbeddedLatticesWindows: @unchecked Sendable {
    public init() {}

    public func list() -> [LatticesWindow] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var windows: [LatticesWindow] = []
        for info in list {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds, &rect),
                  rect.width >= 50,
                  rect.height >= 50
            else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false

            windows.append(
                LatticesWindow(
                    wid: Int(wid),
                    app: ownerName,
                    pid: Int(pid),
                    title: title,
                    frame: LatticesFrame(x: rect.origin.x, y: rect.origin.y, w: rect.width, h: rect.height),
                    spaceIds: EmbeddedSkyLight.spacesForWindow(wid),
                    isOnScreen: isOnScreen,
                    latticesSession: Self.extractSessionName(from: title),
                    axVerified: nil,
                    layerTag: nil
                )
            )
        }
        return windows
    }

    public func resolve(_ target: LatticesWindowTarget) -> LatticesWindow? {
        let windows = list()

        if let wid = target.wid {
            return windows.first { $0.wid == wid }
        }

        if let session = target.session {
            return windows.first {
                $0.latticesSession == session || $0.title.contains(Self.tag(for: session))
            }
        }

        if let app = target.app {
            let matches = windows.filter { window in
                guard window.app.localizedCaseInsensitiveContains(app) else { return false }
                if let title = target.title {
                    return window.title.localizedCaseInsensitiveContains(title)
                }
                return true
            }
            return matches.sorted { lhs, rhs in
                if lhs.isOnScreen != rhs.isOnScreen {
                    return lhs.isOnScreen && !rhs.isOnScreen
                }
                let lhsArea = lhs.frame.w * lhs.frame.h
                let rhsArea = rhs.frame.w * rhs.frame.h
                return lhsArea > rhsArea
            }.first
        }

        return windows.first
    }

    @discardableResult
    public func focus(_ target: LatticesWindowTarget, switchSpaces: Bool = true) throws -> Bool {
        guard let window = resolve(target) else {
            throw EmbeddedLatticesError.windowNotFound(String(describing: target))
        }
        return try focus(window, switchSpaces: switchSpaces)
    }

    @discardableResult
    public func focus(session: String, switchSpaces: Bool = true) throws -> Bool {
        try focus(.session(session), switchSpaces: switchSpaces)
    }

    @discardableResult
    public func focus(_ window: LatticesWindow, switchSpaces: Bool = true) throws -> Bool {
        if switchSpaces, let space = window.spaceIds.first {
            _ = EmbeddedSkyLight.switchToSpace(spaceId: space)
        }

        guard let axWindow = axWindow(pid: pid_t(window.pid), wid: CGWindowID(window.wid)) else {
            if let app = NSRunningApplication(processIdentifier: pid_t(window.pid)) {
                return app.activate()
            }
            throw EmbeddedLatticesError.accessibilityUnavailable
        }

        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        return NSRunningApplication(processIdentifier: pid_t(window.pid))?
            .activate() ?? true
    }

    @discardableResult
    public func tile(
        _ target: LatticesWindowTarget,
        position: LatticesTilePosition,
        screen: NSScreen? = nil
    ) throws -> Bool {
        guard let window = resolve(target) else {
            throw EmbeddedLatticesError.windowNotFound(String(describing: target))
        }
        let targetScreen = screen ?? screenContaining(window: window) ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else {
            throw EmbeddedLatticesError.windowNotFound("screen for \(window.wid)")
        }
        return try place(window: window, frame: Self.tileFrame(for: position, on: targetScreen))
    }

    @discardableResult
    public func place(window: LatticesWindow, frame: CGRect) throws -> Bool {
        guard let axWindow = axWindow(pid: pid_t(window.pid), wid: CGWindowID(window.wid)) else {
            throw EmbeddedLatticesError.accessibilityUnavailable
        }

        var size = CGSize(width: frame.width, height: frame.height)
        var point = CGPoint(x: frame.origin.x, y: frame.origin.y)

        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        }
        if let pointValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, pointValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        return true
    }

    public static func tag(for session: String) -> String {
        "[lattices:\(session)]"
    }

    public static func extractSessionName(from title: String) -> String? {
        guard let range = title.range(of: #"\[lattices:([^\]]+)\]"#, options: .regularExpression) else {
            return nil
        }
        let match = String(title[range])
        return String(match.dropFirst(10).dropLast(1))
    }

    public static func tileFrame(for position: LatticesTilePosition, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? visible.height
        let top = primaryHeight - visible.maxY
        let rect = position.fractions
        return CGRect(
            x: visible.minX + visible.width * rect.x,
            y: top + visible.height * rect.y,
            width: visible.width * rect.w,
            height: visible.height * rect.h
        )
    }

    func axWindow(pid: pid_t, wid: CGWindowID) -> AXUIElement? {
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            var candidate = CGWindowID(0)
            if _AXUIElementGetWindow(window, &candidate) == .success, candidate == wid {
                return window
            }
        }

        return nil
    }

    private func screenContaining(window: LatticesWindow) -> NSScreen? {
        let center = CGPoint(x: window.frame.x + window.frame.w / 2, y: window.frame.y + window.frame.h / 2)
        return NSScreen.screens.first { screen in
            Self.axFrame(for: screen).contains(center)
        }
    }

    private static func axFrame(for screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(
            x: screen.frame.minX,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }
}

public final class EmbeddedLatticesTmux: Sendable {
    public init() {}

    public func sessionName(for path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let basename = url.lastPathComponent.replacingOccurrences(
            of: #"[^a-zA-Z0-9_-]"#,
            with: "-",
            options: .regularExpression
        )
        let digest = SHA256.hash(data: Data(url.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(6)
        return "\(basename)-\(digest)"
    }

    public func isTmuxAvailable() -> Bool {
        (try? run(["-V"])) != nil
    }

    public func hasSession(_ name: String) -> Bool {
        (try? run(["has-session", "-t", name])) != nil
    }

    public func listSessions() throws -> [LatticesTmuxSession] {
        let raw = try run(["list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{session_attached}"])
        return raw.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            let name = parts.indices.contains(0) ? String(parts[0]) : ""
            let windowCount = parts.indices.contains(1) ? Int(parts[1]) ?? 0 : 0
            let attached = parts.indices.contains(2) ? String(parts[2]) == "1" : false
            let panes = (try? listPanes(session: name)) ?? []
            return LatticesTmuxSession(name: name, windowCount: windowCount, attached: attached, panes: panes)
        }
    }

    public func listPanes(session: String) throws -> [LatticesTmuxPane] {
        let format = "#{pane_id}\t#{window_index}\t#{window_name}\t#{pane_title}\t#{pane_current_command}\t#{pane_pid}\t#{pane_active}"
        let raw = try run(["list-panes", "-t", session, "-F", format])
        return raw.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            return LatticesTmuxPane(
                id: parts.indices.contains(0) ? String(parts[0]) : "",
                windowIndex: parts.indices.contains(1) ? Int(parts[1]) ?? 0 : 0,
                windowName: parts.indices.contains(2) ? String(parts[2]) : "",
                title: parts.indices.contains(3) ? String(parts[3]) : "",
                currentCommand: parts.indices.contains(4) ? String(parts[4]) : "",
                pid: parts.indices.contains(5) ? Int(parts[5]) ?? 0 : 0,
                isActive: parts.indices.contains(6) ? String(parts[6]) == "1" : false,
                children: nil
            )
        }
    }

    @discardableResult
    public func run(_ arguments: [String], cwd: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux"] + arguments
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw EmbeddedLatticesError.missingTmux
        }

        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw EmbeddedLatticesError.commandFailed(
                command: "tmux \(arguments.joined(separator: " "))",
                status: process.terminationStatus,
                stderr: error.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output.trimmingCharacters(in: .newlines)
    }
}

public final class EmbeddedLatticesSessions: Sendable {
    private let tmux: EmbeddedLatticesTmux
    private let windows: EmbeddedLatticesWindows

    init(tmux: EmbeddedLatticesTmux, windows: EmbeddedLatticesWindows) {
        self.tmux = tmux
        self.windows = windows
    }

    @discardableResult
    public func launch(path: String, focus: Bool = false) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let session = tmux.sessionName(for: url.path)
        if !tmux.hasSession(session) {
            try createSession(path: url.path, session: session)
        }
        if focus {
            _ = try? windows.focus(session: session)
        }
        return session
    }

    @discardableResult
    public func kill(name: String) throws -> Bool {
        try tmux.run(["kill-session", "-t", name])
        return true
    }

    @discardableResult
    public func detach(name: String) throws -> Bool {
        try tmux.run(["detach-client", "-s", name])
        return true
    }

    @discardableResult
    public func restart(path: String, pane target: String? = nil) throws -> Bool {
        let session = tmux.sessionName(for: path)
        guard tmux.hasSession(session) else {
            throw EmbeddedLatticesError.sessionNotFound(session)
        }
        let panes = try resolvedPanes(path: path)
        let tmuxPanes = try tmux.listPanes(session: session)
        let index = target.flatMap { target in
            if let int = Int(target) { return int }
            return panes.firstIndex { $0.name?.localizedCaseInsensitiveCompare(target) == .orderedSame }
        } ?? 0
        guard panes.indices.contains(index), tmuxPanes.indices.contains(index) else {
            throw EmbeddedLatticesError.invalidConfig("Pane target not found: \(target ?? "0")")
        }

        let paneId = tmuxPanes[index].id
        _ = try? tmux.run(["send-keys", "-t", paneId, "C-c"])
        usleep(500_000)
        if let command = panes[index].cmd {
            try tmux.run(["send-keys", "-t", paneId, command, "Enter"])
        }
        return true
    }

    private func createSession(path: String, session: String) throws {
        let panes = try resolvedPanes(path: path)
        try tmux.run(["new-session", "-d", "-s", session, "-c", path])

        if panes.count == 2 {
            let mainSize = panes[0].size ?? 60
            try tmux.run(["split-window", "-h", "-t", session, "-c", path, "-p", "\(100 - mainSize)"])
        } else if panes.count >= 3 {
            let mainSize = panes[0].size ?? 60
            for _ in panes.dropFirst() {
                try tmux.run(["split-window", "-t", session, "-c", path])
            }
            _ = try? tmux.run(["set-option", "-t", session, "-w", "main-pane-width", "\(mainSize)%"])
            try tmux.run(["select-layout", "-t", session, "main-vertical"])
        }

        let paneIds = try tmux.run(["list-panes", "-t", session, "-F", "#{pane_id}"])
            .split(separator: "\n")
            .map(String.init)

        for (index, pane) in panes.enumerated() where paneIds.indices.contains(index) {
            let paneId = paneIds[index]
            if let command = pane.cmd, !command.isEmpty {
                try tmux.run(["send-keys", "-t", paneId, command, "Enter"])
            }
            if let name = pane.name, !name.isEmpty {
                _ = try? tmux.run(["select-pane", "-t", paneId, "-T", name])
            }
        }

        _ = try? tmux.run(["set-option", "-t", session, "set-titles", "on"])
        _ = try? tmux.run(["set-option", "-t", session, "set-titles-string", "[lattices:\(session)] #{pane_title}"])
        _ = try? tmux.run(["rename-window", "-t", session, URL(fileURLWithPath: path).lastPathComponent])
        if let first = paneIds.first {
            _ = try? tmux.run(["select-pane", "-t", first])
        }
    }

    private func resolvedPanes(path: String) throws -> [EmbeddedPaneConfig] {
        if let config = try readConfig(path: path), let panes = config.panes, !panes.isEmpty {
            return panes
        }
        if let devCommand = detectDevCommand(path: path) {
            return [
                EmbeddedPaneConfig(name: "shell", cmd: nil, size: 60),
                EmbeddedPaneConfig(name: "server", cmd: devCommand, size: nil),
            ]
        }
        return [EmbeddedPaneConfig(name: "shell", cmd: nil, size: nil)]
    }

    private func readConfig(path: String) throws -> EmbeddedProjectConfig? {
        let configURL = URL(fileURLWithPath: path).appendingPathComponent(".lattices.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(EmbeddedProjectConfig.self, from: data)
        } catch {
            throw EmbeddedLatticesError.invalidConfig(error.localizedDescription)
        }
    }

    private func detectDevCommand(path: String) -> String? {
        let packageURL = URL(fileURLWithPath: path).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: Any]
        else { return nil }

        let manager: String
        if FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("pnpm-lock.yaml").path) {
            manager = "pnpm"
        } else if FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("bun.lock").path)
            || FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("bun.lockb").path) {
            manager = "bun"
        } else if FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("yarn.lock").path) {
            manager = "yarn"
        } else {
            manager = "npm"
        }

        for script in ["dev", "start", "serve", "watch"] where scripts[script] != nil {
            return manager == "npm" ? "npm run \(script)" : "\(manager) \(script)"
        }
        return nil
    }
}

public final class EmbeddedLatticesAccessibility: Sendable {
    private let windows: EmbeddedLatticesWindows

    init(windows: EmbeddedLatticesWindows) {
        self.windows = windows
    }

    public func snapshot(
        target: LatticesWindowTarget,
        maxDepth: Int = 8,
        maxElements: Int = 300
    ) throws -> LatticesAccessibilitySnapshot {
        guard let window = windows.resolve(target) else {
            throw EmbeddedLatticesError.windowNotFound(String(describing: target))
        }
        guard let axWindow = windows.axWindow(pid: pid_t(window.pid), wid: CGWindowID(window.wid)) else {
            throw EmbeddedLatticesError.accessibilityUnavailable
        }

        var elements: [LatticesAXElement] = []
        traverse(axWindow, path: "0", depth: 0, maxDepth: maxDepth, maxElements: maxElements, into: &elements)
        return LatticesAccessibilitySnapshot(target: window, elements: elements)
    }

    private func traverse(
        _ element: AXUIElement,
        path: String,
        depth: Int,
        maxDepth: Int,
        maxElements: Int,
        into elements: inout [LatticesAXElement]
    ) {
        guard depth <= maxDepth, elements.count < maxElements else { return }

        let item = LatticesAXElement(
            id: "e\(elements.count + 1)",
            path: path,
            depth: depth,
            role: stringAttribute(element, kAXRoleAttribute) ?? "",
            title: stringAttribute(element, kAXTitleAttribute),
            value: stringAttribute(element, kAXValueAttribute),
            label: stringAttribute(element, kAXDescriptionAttribute),
            frame: frame(element)
        )
        elements.append(item)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return }

        for (index, child) in children.enumerated() {
            traverse(
                child,
                path: "\(path).\(index)",
                depth: depth + 1,
                maxDepth: maxDepth,
                maxElements: maxElements,
                into: &elements
            )
        }
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref
        else { return nil }
        return String(describing: value)
    }

    private func frame(_ element: AXUIElement) -> LatticesFrame? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef,
              let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        let posValue = unsafeBitCast(posRef, to: AXValue.self)
        let sizeValue = unsafeBitCast(sizeRef, to: AXValue.self)
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &point)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return LatticesFrame(x: point.x, y: point.y, w: size.width, h: size.height)
    }
}

public struct LatticesAccessibilitySnapshot: Codable, Equatable, Sendable {
    public var target: LatticesWindow
    public var elements: [LatticesAXElement]
}

public struct LatticesAXElement: Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var depth: Int
    public var role: String
    public var title: String?
    public var value: String?
    public var label: String?
    public var frame: LatticesFrame?
}

public final class EmbeddedLatticesInput: Sendable {
    private let windows: EmbeddedLatticesWindows

    init(windows: EmbeddedLatticesWindows) {
        self.windows = windows
    }

    @discardableResult
    public func hotkey(_ shortcut: String, target: LatticesWindowTarget? = nil) throws -> Bool {
        if let target {
            _ = try windows.focus(target)
            usleep(80_000)
        }

        let parsed = try EmbeddedShortcut.parse(shortcut)
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: parsed.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: parsed.keyCode, keyDown: false)
        else {
            throw EmbeddedLatticesError.accessibilityUnavailable
        }
        down.flags = parsed.flags
        up.flags = parsed.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    public func click(target: LatticesWindowTarget, xRatio: Double = 0.5, yRatio: Double = 0.5) throws -> Bool {
        guard let window = windows.resolve(target) else {
            throw EmbeddedLatticesError.windowNotFound(String(describing: target))
        }
        let point = CGPoint(
            x: window.frame.x + window.frame.w * xRatio,
            y: window.frame.y + window.frame.h * yRatio
        )
        return try click(point: point)
    }

    @discardableResult
    public func click(point: CGPoint) throws -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            throw EmbeddedLatticesError.accessibilityUnavailable
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    public func pasteText(_ text: String, target: LatticesWindowTarget? = nil) throws -> Bool {
        if let target {
            _ = try windows.focus(target)
            usleep(80_000)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return try hotkey("cmd+v")
    }
}

private struct EmbeddedProjectConfig: Decodable {
    var panes: [EmbeddedPaneConfig]?
}

private struct EmbeddedPaneConfig: Decodable {
    var name: String?
    var cmd: String?
    var size: Int?
}

private enum EmbeddedSkyLight {
    typealias MainConnectionIDFunc = @convention(c) () -> Int32
    typealias GetActiveSpaceFunc = @convention(c) (Int32) -> UInt64
    typealias CopyManagedDisplaySpacesFunc = @convention(c) (Int32) -> CFArray
    typealias CopySpacesForWindowsFunc = @convention(c) (Int32, Int32, CFArray) -> CFArray
    typealias SetCurrentSpaceFunc = @convention(c) (Int32, CFString, UInt64) -> Void

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static var isAvailable: Bool {
        mainConnectionID != nil && copyManagedDisplaySpaces != nil && copySpacesForWindows != nil
    }

    private static let mainConnectionID: MainConnectionIDFunc? = {
        guard let handle, let symbol = dlsym(handle, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(symbol, to: MainConnectionIDFunc.self)
    }()

    private static let getActiveSpace: GetActiveSpaceFunc? = {
        guard let handle, let symbol = dlsym(handle, "CGSGetActiveSpace") else { return nil }
        return unsafeBitCast(symbol, to: GetActiveSpaceFunc.self)
    }()

    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFunc? = {
        guard let handle, let symbol = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyManagedDisplaySpacesFunc.self)
    }()

    private static let copySpacesForWindows: CopySpacesForWindowsFunc? = {
        guard let handle, let symbol = dlsym(handle, "SLSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesForWindowsFunc.self)
    }()

    private static let setCurrentSpace: SetCurrentSpaceFunc? = {
        guard let handle, let symbol = dlsym(handle, "SLSManagedDisplaySetCurrentSpace") else { return nil }
        return unsafeBitCast(symbol, to: SetCurrentSpaceFunc.self)
    }()

    static func spacesForWindow(_ wid: UInt32) -> [Int] {
        guard let mainConnectionID, let copySpacesForWindows else { return [] }
        let windowIds = [NSNumber(value: wid)] as CFArray
        guard let result = copySpacesForWindows(mainConnectionID(), 0x7, windowIds) as? [NSNumber] else {
            return []
        }
        return result.map(\.intValue)
    }

    static func currentSpace() -> Int {
        guard let mainConnectionID, let getActiveSpace else { return 0 }
        return Int(getActiveSpace(mainConnectionID()))
    }

    @discardableResult
    static func switchToSpace(spaceId: Int) -> Bool {
        guard let mainConnectionID, let setCurrentSpace else { return false }
        let displays = displaySpaces()
        guard let display = displays.first(where: { display in
            display.spaces.contains(spaceId)
        }) else {
            return false
        }
        if display.currentSpaceId == spaceId {
            return true
        }
        setCurrentSpace(mainConnectionID(), display.id as CFString, UInt64(spaceId))
        return true
    }

    private static func displaySpaces() -> [(id: String, currentSpaceId: Int, spaces: [Int])] {
        guard let mainConnectionID, let copyManagedDisplaySpaces,
              let managed = copyManagedDisplaySpaces(mainConnectionID()) as? [[String: Any]]
        else { return [] }

        return managed.map { display in
            let id = display["Display Identifier"] as? String ?? ""
            let current = display["Current Space"] as? [String: Any]
            let currentId = current?["id64"] as? Int ?? current?["ManagedSpaceID"] as? Int ?? 0
            let spaces = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space -> Int? in
                let type = space["type"] as? Int ?? 0
                guard type == 0 else { return nil }
                return space["id64"] as? Int ?? space["ManagedSpaceID"] as? Int
            }
            return (id: id, currentSpaceId: currentId, spaces: spaces)
        }
    }
}

private struct EmbeddedShortcut {
    var keyCode: CGKeyCode
    var flags: CGEventFlags

    static func parse(_ raw: String) throws -> EmbeddedShortcut {
        let parts = raw
            .lowercased()
            .replacingOccurrences(of: "command", with: "cmd")
            .replacingOccurrences(of: "option", with: "opt")
            .replacingOccurrences(of: "control", with: "ctrl")
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var flags: CGEventFlags = []
        var key: String?
        for part in parts {
            switch part {
            case "cmd", "meta":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "opt", "alt":
                flags.insert(.maskAlternate)
            case "ctrl":
                flags.insert(.maskControl)
            default:
                key = part
            }
        }

        guard let key, let keyCode = keyCodes[key] else {
            throw EmbeddedLatticesError.invalidConfig("Unsupported shortcut: \(raw)")
        }
        return EmbeddedShortcut(keyCode: keyCode, flags: flags)
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}

private extension LatticesTilePosition {
    var fractions: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        switch self {
        case .left:
            return (0, 0, 0.5, 1)
        case .right:
            return (0.5, 0, 0.5, 1)
        case .top:
            return (0, 0, 1, 0.5)
        case .bottom:
            return (0, 0.5, 1, 0.5)
        case .topLeft:
            return (0, 0, 0.5, 0.5)
        case .topRight:
            return (0.5, 0, 0.5, 0.5)
        case .bottomLeft:
            return (0, 0.5, 0.5, 0.5)
        case .bottomRight:
            return (0.5, 0.5, 0.5, 0.5)
        case .maximize:
            return (0, 0, 1, 1)
        case .center:
            return (0.15, 0.10, 0.70, 0.80)
        }
    }
}
