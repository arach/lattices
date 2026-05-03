import SwiftUI

/// A single action row with shortcut badge, label, optional icon, and hotkey hint.
struct ActionRow: View {
    let label: String
    var detail: String? = nil
    var hotkeyTokens: [String] = []
    var icon: String? = nil
    var accentColor: Color = Palette.textDim
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon
                if let icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(accentColor.opacity(isHovered ? 0.18 : 0.12))
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isHovered ? Palette.text : accentColor)
                    }
                    .frame(width: 22, height: 22)
                }

                // Label
                VStack(alignment: .leading, spacing: detail == nil ? 0 : 2) {
                    Text(label)
                        .font(Typo.body(12))
                        .foregroundColor(isHovered ? Palette.text : Palette.textDim)
                        .lineLimit(1)

                    if let detail {
                        Text(detail)
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Hotkey
                if !hotkeyTokens.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(hotkeyTokens, id: \.self) { token in
                            Text(token)
                                .font(Typo.monoBold(8))
                                .foregroundColor(Palette.textMuted)
                                .padding(.horizontal, token.count > 3 ? 6 : 5)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Palette.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Palette.border, lineWidth: 0.5)
                                        )
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
