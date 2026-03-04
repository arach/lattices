import SwiftUI

/// A single action row with shortcut badge, label, optional icon, and hotkey hint.
struct ActionRow: View {
    let shortcut: String
    let label: String
    var hotkey: String? = nil
    var icon: String? = nil
    var accentColor: Color = Palette.textDim
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Shortcut badge
                Text(shortcut)
                    .font(Typo.monoBold(10))
                    .foregroundColor(accentColor)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accentColor.opacity(0.12))
                    )

                // Icon
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isHovered ? Palette.text : Palette.textDim)
                        .frame(width: 14)
                }

                // Label
                Text(label)
                    .font(Typo.mono(12))
                    .foregroundColor(isHovered ? Palette.text : Palette.textDim)
                    .lineLimit(1)

                Spacer()

                // Hotkey
                if let hotkey {
                    Text(hotkey)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Palette.surfaceHov : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
