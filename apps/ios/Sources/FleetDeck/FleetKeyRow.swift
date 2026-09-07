import DeckKit
import SwiftUI

// MARK: - Key row
//
// One physical row in five clusters: lockable modifiers, edit keys, space, the
// arrow cluster, enter. Tap a modifier to arm it (amber); the next plain key
// goes out chorded and the modifier releases — tap ⌘ then L and the Mac gets
// ⌘L. Chording is how a touch remote stays a keyboard.

struct FleetKeyRow: View {
    let onKey: (String, [String]) -> Void

    /// Modifier names currently armed for the next keystroke.
    @State private var armed: Set<String> = []

    /// Canonical order for the outgoing modifier list.
    private let modifierOrder = ["control", "option", "command", "shift"]

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 5) {
                modifierKey("⌃", name: "control")
                modifierKey("⌥", name: "option")
                modifierKey("⌘", name: "command")
                modifierKey("⇧", name: "shift")
            }
            HStack(spacing: 5) {
                key("esc") { send("escape") }
                key("tab") { send("tab") }
                key("⌘Z") { onKey("z", ["command"]) }
                key("⌘C") { onKey("c", ["command"]) }
                key("⌘V") { onKey("v", ["command"]) }
            }
            key("space", wide: true) { send("space") }
            HStack(spacing: 3) {
                symbolKey("arrow.left") { send("left") }
                symbolKey("arrow.up") { send("up") }
                symbolKey("arrow.down") { send("down") }
                symbolKey("arrow.right") { send("right") }
            }
            key("enter ⏎") { send("return") }
        }
        .padding(.horizontal, 14)
        .frame(height: FleetV6.M.keyRowHeight)
        .frame(maxWidth: .infinity)
        .background(FleetV6.wellBG)
        .clipShape(RoundedRectangle(cornerRadius: FleetV6.M.wellRadius, style: .continuous))
    }

    /// A plain key carries whatever modifiers are armed, then releases them.
    private func send(_ key: String) {
        let modifiers = modifierOrder.filter { armed.contains($0) }
        onKey(key, modifiers)
        armed.removeAll()
    }

    private func modifierKey(_ label: String, name: String) -> some View {
        let isArmed = armed.contains(name)
        return Button {
            if isArmed { armed.remove(name) } else { armed.insert(name) }
        } label: {
            Text(label)
                .font(FleetV6.mono(12))
                .foregroundStyle(isArmed ? FleetV6.amber : FleetV6.fg2)
                .frame(minWidth: 44, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isArmed ? DeckTheme.accent.opacity(0.14) : FleetV6.keycap)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isArmed ? FleetV6.amber : DeckTheme.hairline, lineWidth: 1)
                        }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle(isKey: true))
        .accessibilityLabel("\(name) modifier")
        .accessibilityValue(isArmed ? "armed" : "off")
        .accessibilityHint("Arms for the next keystroke")
    }

    private func key(_ label: String, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(FleetV6.mono(12))
                .foregroundStyle(FleetV6.fg2)
                .padding(.horizontal, 12)
                .frame(minWidth: wide ? nil : 44, maxWidth: wide ? .infinity : nil, minHeight: 44)
                .background { FleetKeycapBackground() }
                .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle(isKey: true, isAccent: wide))
        .accessibilityLabel(label)
    }

    private func symbolKey(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FleetV6.fg2)
                .frame(minWidth: 40, minHeight: 44)
                .background { FleetKeycapBackground() }
                .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle(isKey: true))
        .accessibilityLabel(symbol.replacingOccurrences(of: "arrow.", with: "") + " arrow")
    }
}
