import SwiftUI

// MARK: - Background

/// Standard Lats screen background. Use as the outermost container.
struct LatsBackground<Content: View>: View {
    var grid: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            LatsPalette.bgEdge.ignoresSafeArea()
            if grid {
                LatsGridBackground().opacity(0.7).ignoresSafeArea()
            }
            content()
        }
    }
}

// MARK: - Top bar

struct LatsTopBar: View {
    var product: String = "LATS"
    var section: String? = nil
    var trailing: AnyView? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(product)
                    .font(LatsFont.mono(11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(LatsPalette.text)
                if let section {
                    Text("·").foregroundStyle(LatsPalette.textFaint)
                    Text(section)
                        .font(LatsFont.mono(11))
                        .tracking(1)
                        .foregroundStyle(LatsPalette.textDim)
                }
            }

            Spacer()

            if let trailing { trailing }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LatsPalette.textDim)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }
}

// MARK: - Card containers

/// Standard Lats surface card with hairline border.
struct LatsCard<Content: View>: View {
    var padding: CGFloat = 14
    var radius: CGFloat = 8
    var fill: Color = LatsPalette.surface
    var stroke: Color = LatsPalette.hairline2
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: 1)
            )
    }
}

/// Inset row inside a LatsCard — slightly darker, hairline border.
struct LatsInset<Content: View>: View {
    var padding: CGFloat = 12
    var radius: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(LatsPalette.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Section label

struct LatsSectionLabel: View {
    let text: String
    // Source design uses amber (~#d9a05b) for all section headers — gives the
    // surface its tactical-HUD feel and visually anchors each section above
    // the dim mono subtitles that sit alongside.
    var tint: Color = LatsPalette.amber
    var body: some View {
        Text(text.uppercased())
            .font(LatsFont.mono(9, weight: .bold))
            .tracking(2.0)
            .foregroundStyle(tint)
    }
}

// MARK: - Hairline

struct LatsHairlineDivider: View {
    var color: Color = LatsPalette.hairline
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

// MARK: - Buttons

enum LatsButtonStyle {
    case primary(LatsTint)
    case secondary
    case ghost
}

struct LatsButton: View {
    let title: String
    var icon: String? = nil
    var style: LatsButtonStyle = .secondary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(LatsFont.mono(12, weight: .semibold)).tracking(0.5)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary(let tint): return tint.color
        case .secondary: return LatsPalette.text
        case .ghost: return LatsPalette.textDim
        }
    }

    private var background: Color {
        switch style {
        case .primary(let tint): return tint.color.opacity(0.18)
        case .secondary: return Color.white.opacity(0.05)
        case .ghost: return .clear
        }
    }

    private var border: Color {
        switch style {
        case .primary(let tint): return tint.color.opacity(0.5)
        case .secondary: return LatsPalette.hairline2
        case .ghost: return LatsPalette.hairline
        }
    }
}

// MARK: - Text field

struct LatsField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalize: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(autocapitalize ? .sentences : .never)
            .autocorrectionDisabled()
            .font(LatsFont.mono(12))
            .foregroundStyle(LatsPalette.text)
            .tint(LatsPalette.green)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LatsPalette.hairline2, lineWidth: 1)
            )
    }
}

// MARK: - Badge / pill

struct LatsBadge: View {
    let text: String
    var tint: Color = LatsPalette.textDim
    var dot: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if dot { Circle().fill(tint).frame(width: 5, height: 5) }
            Text(text)
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3).stroke(tint.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - List row

struct LatsListRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconTint: LatsTint = .blue
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconTint.color)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(iconTint.color.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(iconTint.color.opacity(0.28), lineWidth: 1)
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LatsFont.ui(13, weight: .medium))
                        .foregroundStyle(LatsPalette.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(LatsFont.mono(10))
                            .foregroundStyle(LatsPalette.textDim)
                    }
                }
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? iconTint.color.opacity(0.10) : Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? iconTint.color.opacity(0.45) : LatsPalette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

extension LatsListRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconTint: LatsTint = .blue,
        isSelected: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = iconTint
        self.isSelected = isSelected
        self.onTap = onTap
        self.trailing = { EmptyView() }
    }
}

// MARK: - Empty state

struct LatsEmptyState: View {
    let title: String
    var subtitle: String? = nil
    var icon: String = "tray"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(LatsPalette.textFaint)
            Text(title)
                .font(LatsFont.mono(11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(LatsPalette.textDim)
            if let subtitle {
                Text(subtitle)
                    .font(LatsFont.mono(10))
                    .foregroundStyle(LatsPalette.textFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LatsPalette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Tab strip (horizontal pages)

struct LatsTabStrip<T: Hashable>: View {
    let items: [(T, String, String?)]    // id, title, optional icon
    @Binding var selected: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { item in
                    let isActive = item.0 == selected
                    Button { selected = item.0 } label: {
                        HStack(spacing: 6) {
                            if let icon = item.2 {
                                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                            }
                            Text(item.1)
                                .font(LatsFont.mono(11, weight: isActive ? .semibold : .regular))
                                .tracking(0.5)
                        }
                        .foregroundStyle(isActive ? LatsPalette.text : LatsPalette.textDim)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isActive ? Color.white.opacity(0.06) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(isActive ? LatsPalette.hairline2 : LatsPalette.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - KV row

struct LatsKVRow: View {
    let key: String
    let value: String
    var valueColor: Color = LatsPalette.text

    var body: some View {
        HStack {
            Text(key.uppercased())
                .font(LatsFont.mono(9))
                .tracking(0.8)
                .foregroundStyle(LatsPalette.textFaint)
            Spacer()
            Text(value)
                .font(LatsFont.mono(11))
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Container helpers

extension View {
    /// Apply a hairline border with rounded corners.
    func latsHairlineBorder(radius: CGFloat = 6, color: Color = LatsPalette.hairline) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(color, lineWidth: 1)
        )
    }
}
