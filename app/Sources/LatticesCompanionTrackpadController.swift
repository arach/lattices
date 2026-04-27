import AppKit
import DeckKit
import Foundation

final class LatticesCompanionTrackpadController {
    static let shared = LatticesCompanionTrackpadController()

    private init() {}

    func state(isEnabled: Bool) -> DeckTrackpadState {
        guard isEnabled else {
            return DeckTrackpadState(
                isEnabled: false,
                isAvailable: false,
                statusTitle: "Trackpad Off",
                statusDetail: "Enable the companion trackpad from the Mac Shortcuts settings.",
                pointerScale: 1.6,
                scrollScale: 1.0,
                supportsDragLock: true
            )
        }

        let trusted = AXIsProcessTrusted()
        return DeckTrackpadState(
            isEnabled: true,
            isAvailable: trusted,
            statusTitle: trusted ? "Trackpad Ready" : "Accessibility Needed",
            statusDetail: trusted
                ? "Move, scroll, click, and drag on your Mac from the iPad surface."
                : "Grant Accessibility permission to Lattices on your Mac to enable pointer control.",
            pointerScale: 1.6,
            scrollScale: 1.0,
            supportsDragLock: true
        )
    }

    func perform(_ request: DeckTrackpadEventRequest) -> DeckTrackpadEventResult {
        guard AXIsProcessTrusted() else {
            return DeckTrackpadEventResult(ok: false)
        }

        let ok: Bool
        switch request.event {
        case .move:
            ok = performMouseMove(dx: request.dx, dy: request.dy)
        case .click:
            ok = performMouseClick(button: .left)
        case .rightClick:
            ok = performMouseClick(button: .right)
        case .scroll:
            ok = performMouseScroll(dx: request.dx, dy: request.dy)
        case .mouseDown:
            ok = performMouseButtonState(button: .left, isDown: true)
        case .mouseUp:
            ok = performMouseButtonState(button: .left, isDown: false)
        case .drag:
            ok = performMouseDrag(dx: request.dx, dy: request.dy)
        }

        return DeckTrackpadEventResult(ok: ok)
    }
}

private extension LatticesCompanionTrackpadController {
    func currentCursorPoint() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    func clamp(delta: Double) -> CGFloat {
        CGFloat(max(-180, min(180, delta)))
    }

    func performMouseMove(dx: Double, dy: Double) -> Bool {
        let current = currentCursorPoint()
        let next = CGPoint(
            x: current.x + clamp(delta: dx),
            y: current.y + clamp(delta: dy)
        )

        // Disassociate so the synthesized warp isn't fought by the physical
        // mouse's last reported position (which was pinning Y to the bottom).
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(next)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: next,
                mouseButton: .left
              ) else {
            CGAssociateMouseAndMouseCursorPosition(1)
            return false
        }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(clamp(delta: dx)))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(clamp(delta: dy)))
        event.post(tap: .cghidEventTap)
        CGAssociateMouseAndMouseCursorPosition(1)
        return true
    }

    func performMouseClick(button: CGMouseButton) -> Bool {
        let pos = currentCursorPoint()
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(
                mouseEventSource: source,
                mouseType: downType,
                mouseCursorPosition: pos,
                mouseButton: button
              ),
              let up = CGEvent(
                mouseEventSource: source,
                mouseType: upType,
                mouseCursorPosition: pos,
                mouseButton: button
              ) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    func performMouseButtonState(button: CGMouseButton, isDown: Bool) -> Bool {
        let pos = currentCursorPoint()
        let eventType: CGEventType

        switch (button, isDown) {
        case (.left, true):
            eventType = .leftMouseDown
        case (.left, false):
            eventType = .leftMouseUp
        case (.right, true):
            eventType = .rightMouseDown
        case (.right, false):
            eventType = .rightMouseUp
        default:
            eventType = .leftMouseDown
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: eventType,
                mouseCursorPosition: pos,
                mouseButton: button
              ) else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }

    func performMouseDrag(dx: Double, dy: Double) -> Bool {
        let current = currentCursorPoint()
        let next = CGPoint(
            x: current.x + clamp(delta: dx),
            y: current.y + clamp(delta: dy)
        )

        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(next)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: next,
                mouseButton: .left
              ) else {
            CGAssociateMouseAndMouseCursorPosition(1)
            return false
        }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(clamp(delta: dx)))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(clamp(delta: dy)))
        event.post(tap: .cghidEventTap)
        CGAssociateMouseAndMouseCursorPosition(1)
        return true
    }

    func performMouseScroll(dx: Double, dy: Double) -> Bool {
        let horizontal = Int32(clamp(delta: dx).rounded())
        let vertical = Int32((-clamp(delta: dy)).rounded())

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: vertical,
                wheel2: horizontal,
                wheel3: 0
              ) else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }
}
