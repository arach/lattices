import DeckKit
import SwiftUI

// MARK: - Markup-driven tactile bindings
//
// Usage:
//   Button("Approve") { ... }
//     .deckTactile(.deckDecisionApproved)
//
//   KeyView(...)
//     .deckTactile(.deckKeyAccent, params: ["id": .int(3)])
//
//   Button { ... } label: { ... }
//     .buttonStyle(FleetPressStyle(event: .deckButton))

private struct DeckTactileModifier: ViewModifier {
    let event: DeckTactileEventID
    let params: [String: DeckTactileParamValue]
    let trigger: DeckTactileTrigger

    enum DeckTactileTrigger {
        case onTap
    }

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                DeckTactileFeedback.shared.play(event, params: params)
            }
        )
    }
}

public extension View {
    /// Fire a catalog tactile event when the view is tapped.
    func deckTactile(
        _ event: DeckTactileEventID,
        params: [String: DeckTactileParamValue] = [:]
    ) -> some View {
        modifier(DeckTactileModifier(event: event, params: params, trigger: .onTap))
    }

    /// Fire a catalog tactile event by string id (for markup / remote config).
    func deckTactile(
        eventID: String,
        params: [String: DeckTactileParamValue] = [:]
    ) -> some View {
        self.onTapGesture {
            DeckTactileFeedback.shared.play(eventID: eventID, params: params)
        }
    }
}

/// `:active { transform: translateY(1px) }` — every pressable face sinks by a point
/// and plays a catalog-defined tactile event on press-down.
public struct FleetPressStyle: ButtonStyle {
    public var event: DeckTactileEventID
    public var params: [String: DeckTactileParamValue]

    public init(
        event: DeckTactileEventID = .deckButton,
        params: [String: DeckTactileParamValue] = [:]
    ) {
        self.event = event
        self.params = params
    }

    /// Back-compat: mechanical keys vs micro buttons.
    public init(isKey: Bool = true, isAccent: Bool = false, id: Int = 0) {
        if isKey {
            self.event = isAccent ? .deckKeyAccent : .deckKey
            self.params = ["id": .int(id)]
        } else {
            self.event = .deckButton
            self.params = [:]
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    DeckTactileFeedback.shared.play(event, params: params)
                }
            }
    }
}
