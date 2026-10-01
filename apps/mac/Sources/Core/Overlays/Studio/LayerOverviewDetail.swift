import SwiftUI

/// A ⌘⌥ layer in Studio's inspector: its entries, the windows each one
/// matched and where each window is, with its key, which switches to it.
struct LayerOverviewDetail: View {
    let overview: LayerOverview
    /// The windows on the canvas, which a tap selects.
    var onCanvas: Set<UInt32> = []
    var selected: Set<UInt32> = []
    var onSelect: (UInt32) -> Void = { _ in }
    var onSwitch: () -> Void = {}

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
            if entry.windows.isEmpty {
                Text(entry.missing?.note ?? "No window")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
                    .padding(.leading, 10)
                    .padding(.vertical, 2)
            }
            ForEach(entry.windows) { window in
                windowRow(window)
            }
        }
    }

    private func windowRow(_ window: LayerOverview.Window) -> some View {
        let showing = window.spot.isShowing
        let isSelected = selected.contains(window.wid)
        return Button {
            if onCanvas.contains(window.wid) { onSelect(window.wid) }
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
                Text(window.title)
                    .font(Typo.mono(8))
                    .foregroundColor(showing ? Palette.textDim : Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if let note = window.spot.note {
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
