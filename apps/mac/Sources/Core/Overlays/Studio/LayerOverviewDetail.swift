import SwiftUI

/// A ⌘⌥ layer in Studio's inspector: its entries, the windows each one
/// matched and where each window is, with its key, which switches to it.
struct LayerOverviewDetail: View {
    let overview: LayerOverview
    var selected: Set<UInt32> = []
    /// Windows the layer tucks away, and windows on its Space it doesn't
    /// claim. Overview fills these; Studio leaves them empty.
    var tucked: [OverviewRow] = []
    var unclaimed: [OverviewRow] = []
    var onSelect: (UInt32) -> Void = { _ in }
    /// The chord button's switch. Nil hides the button.
    var onSwitch: (() -> Void)? = nil

    @State private var hoveringKey = false

    static func icon(for overview: LayerOverview) -> String {
        guard let slot = overview.slot else { return "square.stack.3d.up" }
        return overview.isActive ? "\(slot).square.fill" : "\(slot).square"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(overview.entries) { entry in
                entryView(entry)
            }
            section("Tucked", tucked)
            section("Unclaimed", unclaimed)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: Self.icon(for: overview))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(overview.isActive ? Palette.text : Palette.textDim)
            Text(overview.label)
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let onSwitch {
                Button(action: onSwitch) {
                    Text(overview.slot.map { "⌘⌥\($0)" } ?? "Switch")
                        .font(Typo.monoBold(8))
                        .foregroundColor(hoveringKey ? Palette.text : Palette.textDim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(hoveringKey ? Palette.surfaceHov : Palette.surface)
                                .overlay(Capsule().strokeBorder(Palette.borderLit, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveringKey = $0 }
                .help(overview.isActive ? "Gather \(overview.label)'s windows again" : "Switch to \(overview.label)")
            }
        }
    }

    private func entryView(_ entry: LayerOverview.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(entry.name)
                    .font(Typo.monoBold(9))
                    .foregroundColor(Palette.textDim)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let pattern = entry.pattern {
                    Text(pattern)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if entry.windows.isEmpty, entry.unknown.isEmpty {
                Text(entry.missing?.note ?? "No window")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
                    .padding(.leading, 10)
                    .padding(.vertical, 2)
            }
            ForEach(entry.windows) { window in
                windowRow(window)
            }
            ForEach(entry.unknown) { member in
                row(wid: member.wid, title: member.title, filled: false,
                    note: [Self.tierLabel(member.tier), "minimized or closed"].compactMap { $0 }.joined(separator: " · "))
            }
        }
    }

    /// How a member is held: by its pin, or by a rule (match, group, path, app).
    static func tierLabel(_ tier: LayerMembership.Tier?) -> String? {
        switch tier {
        case .pin?: return "pin"
        case .match?, .group?, .path?, .app?: return "rule"
        case nil: return nil
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [OverviewRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.monoBold(9))
                    .foregroundColor(Palette.textDim)
                ForEach(rows) { item in
                    row(wid: item.wid, title: item.title.isEmpty ? item.app : item.title,
                        filled: item.state == .showing, note: item.state == .showing ? nil : item.state.label.lowercased())
                }
            }
        }
    }

    private func windowRow(_ window: LayerOverview.Window) -> some View {
        row(wid: window.wid, title: window.title, filled: window.spot.isShowing,
            note: [window.spot.note, Self.tierLabel(window.tier)].compactMap { $0 }.joined(separator: " · "))
    }

    /// Any row selects its window, on the canvas or not: the selection is
    /// one set, and actions decide what they can reach.
    private func row(wid: UInt32, title: String, filled showing: Bool, note: String?) -> some View {
        let isSelected = selected.contains(wid)
        let note = note?.isEmpty == true ? nil : note
        return Button {
            onSelect(wid)
        } label: {
            HStack(spacing: 6) {
                Group {
                    if showing {
                        Circle().fill(Palette.textDim)
                    } else {
                        Circle().strokeBorder(Palette.textMuted, lineWidth: 0.75)
                    }
                }
                .frame(width: 5, height: 5)
                Text(title)
                    .font(Typo.mono(8))
                    .foregroundColor(showing ? Palette.textDim : Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if let note {
                    Text(note)
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isSelected ? Palette.surface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
