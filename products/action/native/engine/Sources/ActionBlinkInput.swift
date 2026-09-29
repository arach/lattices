import ActionCore
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Blink acts: input borrowed for a few milliseconds and handed straight back.
///
/// A blink click saves the operator's pointer, decouples the physical mouse from it,
/// clicks, warps the pointer back and re-couples. A blink keystroke makes the target
/// frontmost, posts to it, and returns focus to whoever held it. Aimed at the agent
/// layer, the pointer leaves the operator's screens entirely for the length of the
/// click, so there is nothing on their displays to see.
///
/// By default every blink act refuses a target outside an agent-layer display: a blink
/// click on the operator's own screen would be exactly the stolen click this exists to
/// avoid. `--any-display` lifts that for tests.
enum ActionBlinkInput {
    /// A click this short is still one click to every app we've driven; the whole blink,
    /// warp to warp-back, stays under ~25ms.
    static let clickHoldMilliseconds = 8
    /// How long a click may take to activate the app it landed in before we give up waiting.
    static let activationWaitMilliseconds = 250

    // MARK: Click

    static func click(
        at point: CGPoint,
        holdMs: Int,
        accessibilityFirst: Bool,
        anyDisplay: Bool,
        pointerEventLogPath: String?
    ) throws -> String {
        if !anyDisplay {
            guard ActionAgentLayerDisplay.contains(point) else {
                throw ActionHostError.accessibilityActionFailed(
                    "blink-click refused: \(Int(point.x)),\(Int(point.y)) is not on an agent layer (open one, or pass --any-display)"
                )
            }
        }

        // The pointer is the fallback. A pressable element under the point takes AXPress,
        // which moves nothing and activates nothing.
        if accessibilityFirst, let role = pressElement(at: point) {
            return "\(Int(point.x)),\(Int(point.y)) via=ax role=\(role)"
        }

        let previous = frontmostPID().flatMap(NSRunningApplication.init(processIdentifier:))
        let target = ownerOfWindow(at: point)
        let saved = CGEvent(source: nil)?.location ?? .zero
        // A private source keeps the operator's held modifiers out of the click.
        let source = CGEventSource(stateID: .privateState)

        CGAssociateMouseAndMouseCursorPosition(0)
        let gesture: ActionPointerGesture
        do {
            gesture = try ActionPointerChannel.primaryClick(
                at: point,
                holdMs: max(1, holdMs),
                source: "blink-click",
                eventSource: source,
                log: ActionPointerEventLog.active(explicitPath: pointerEventLogPath)
            )
        } catch {
            CGWarpMouseCursorPosition(saved)
            CGAssociateMouseAndMouseCursorPosition(1)
            throw error
        }
        CGWarpMouseCursorPosition(saved)
        CGAssociateMouseAndMouseCursorPosition(1)

        let refocused = handBackFocus(to: previous, after: target)
        var detail = "\(Int(point.x)),\(Int(point.y)) via=pointer pointer=\(Int(saved.x)),\(Int(saved.y))"
        if refocused { detail += " refocused=\(previous?.bundleIdentifier ?? "pid \(previous?.processIdentifier ?? 0)")" }
        if gesture.recorded { detail += " pointerEvent=\(gesture.correlationId)" }
        return detail
    }

    /// Roles whose AXPress is the click. Containers that also advertise AXPress (groups,
    /// web areas, rows) are left to the pointer: pressing them rarely does what a click
    /// at that spot would.
    private static let pressableRoles: Set<String> = [
        kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole,
        kAXMenuButtonRole, kAXMenuItemRole, kAXDisclosureTriangleRole, "AXLink", "AXTab",
    ]

    /// Presses the pressable element at `point`, climbing a few parents from the hit
    /// element (a button's label or image is often what the hit test returns). Returns
    /// the pressed role, or nil when nothing there takes AXPress.
    private static func pressElement(at point: CGPoint) -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.5)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }

        for _ in 0..<4 {
            let role = stringAttribute(element, kAXRoleAttribute) ?? ""
            if role == kAXWindowRole || role == kAXApplicationRole { return nil }
            if pressableRoles.contains(role) {
                guard boolAttribute(element, kAXEnabledAttribute) != false,
                      actionNames(element).contains(kAXPressAction),
                      AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { return nil }
                return role
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    // MARK: Keys

    static func type(_ text: String, into app: NSRunningApplication, delayMs: Int?, anyDisplay: Bool) throws -> String {
        try borrowFocus(of: app, anyDisplay: anyDisplay) {
            try postTextToApp(app: app, text: text, delayMs: delayMs)
        }
        return "\(targetLabel(for: app)) \(text.count) chars"
    }

    static func press(_ key: String, modifiers: [String], into app: NSRunningApplication, anyDisplay: Bool) throws -> String {
        try borrowFocus(of: app, anyDisplay: anyDisplay) {
            try postKeyPressToApp(app: app, key: key, modifiers: modifiers, holdMicroseconds: 8_000)
        }
        let combo = modifiers.isEmpty ? key : "\(modifiers.joined(separator: "+"))+\(key)"
        return "\(targetLabel(for: app)) \(combo)"
    }

    /// Makes `app` frontmost, runs `body`, waits for the app to take the events, and puts
    /// the previous frontmost app back.
    private static func borrowFocus(of app: NSRunningApplication, anyDisplay: Bool, _ body: () throws -> Void) throws {
        if !anyDisplay {
            guard ActionAgentLayerDisplay.hasWindow(pid: app.processIdentifier) else {
                throw ActionHostError.accessibilityActionFailed(
                    "blink refused: \(targetLabel(for: app)) has no window on an agent layer (open one, or pass --any-display)"
                )
            }
        }

        let previous = frontmostPID().flatMap(NSRunningApplication.init(processIdentifier:))
        let alreadyFront = previous?.processIdentifier == app.processIdentifier
        if !alreadyFront {
            try ActionNativeAutomation.activateApplication(pid: app.processIdentifier)
            _ = waitForFrontmost(pid: app.processIdentifier, timeoutMs: activationWaitMilliseconds)
        }

        defer {
            if !alreadyFront {
                drain(pid: app.processIdentifier)
                if let previous, previous.processIdentifier != app.processIdentifier {
                    try? ActionNativeAutomation.activateApplication(pid: previous.processIdentifier)
                }
            }
        }
        try body()
    }

    // MARK: Focus

    /// A click on another app's window activates that app asynchronously. Wait for the
    /// switch, then switch back, so the operator's keyboard focus returns to where it was.
    private static func handBackFocus(to previous: NSRunningApplication?, after target: pid_t?) -> Bool {
        guard let previous, let target, target != previous.processIdentifier else { return false }
        guard waitForFrontmost(pid: target, timeoutMs: activationWaitMilliseconds) else { return false }
        return (try? ActionNativeAutomation.activateApplication(pid: previous.processIdentifier)) != nil
    }

    @discardableResult
    private static func waitForFrontmost(pid: pid_t, timeoutMs: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        while Date() < deadline {
            if frontmostPID() == pid { return true }
            usleep(5_000)
        }
        return frontmostPID() == pid
    }

    /// NSWorkspace only refreshes `frontmostApplication` on the main run loop, which a
    /// busy-wait never turns; the accessibility system-wide element answers live.
    private static func frontmostPID() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        var pid: pid_t = 0
        AXUIElementGetPid(value as! AXUIElement, &pid)
        return pid
    }

    /// Events posted to a pid queue behind its main run loop. One accessibility round trip
    /// is served by that same loop, so when it returns the app has caught up with the input
    /// ahead of it, and focus can move on without stranding keystrokes.
    private static func drain(pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
        usleep(10_000)
    }

    private static func ownerOfWindow(at point: CGPoint) -> pid_t? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point),
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            return pid
        }
        return nil
    }
}

/// Recognises agent-layer displays by the vendor/model the layer stamps on them, so a
/// one-shot blink process can check a point without talking to the layer process.
enum ActionAgentLayerDisplay {
    static let vendorID: UInt32 = 0x4163 // "Ac"
    static let productID: UInt32 = 0x4C59 // "LY"

    static func isAgentLayer(_ display: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(display) == vendorID && CGDisplayModelNumber(display) == productID
    }

    static func displays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter(isAgentLayer)
    }

    static func contains(_ point: CGPoint) -> Bool {
        displays().contains { CGDisplayBounds($0).contains(point) }
    }

    static func hasWindow(pid: pid_t) -> Bool {
        let layers = displays().map(CGDisplayBounds)
        guard !layers.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return info.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return layers.contains { $0.intersects(bounds) }
        }
    }
}
