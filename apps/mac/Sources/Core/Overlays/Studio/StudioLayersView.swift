import SwiftUI

// MARK: - StudioLayersView
//
// The Studio panel for rule-backed layers. Each layer shows its name, the rule
// it resolves by, and how many live windows currently match. Clicking a row
// recalls the layer (raises the matching windows + shows the bezel). Layers are
// authored by plucking in Hyperspace; here you browse, rename, and recall them.

struct StudioLayersView: View {
    @ObservedObject private var store = StudioLayerStore.shared
    // Observed so match counts re-compute as windows open/close/retitle.
    @ObservedObject private var desktop = DesktopModel.shared

    @State private var editingId: String?
    @State private var draftName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: 0.5)

            if store.layers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.layers) { layer in
                            StudioLayerRow(
                                layer: layer,
                                matchCount: store.matchCount(layer, in: desktop),
                                isEditing: editingId == layer.id,
                                draftName: $draftName,
                                onRecall:      { store.recall(layer) },
                                onBeginRename: { draftName = layer.name; editingId = layer.id },
                                onCommitRename:{ store.rename(id: layer.id, to: draftName); editingId = nil },
                                onCancelRename:{ editingId = nil },
                                onDelete:      { store.delete(id: layer.id) }
                            )
                        }
                    }
                    .padding(10)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.border).frame(width: 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 11))
                .foregroundColor(Palette.running)
            Text("LAYERS")
                .font(Typo.geistMonoBold(10))
                .foregroundColor(Palette.textDim)
            Spacer()
            Text("\(store.layers.count)")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 22))
                .foregroundColor(Palette.textMuted)
            Text("No layers yet")
                .font(Typo.heading(12))
                .foregroundColor(Palette.textDim)
            Text("Pluck windows in Hyperspace, then save them as a layer.")
                .font(Typo.body(11))
                .foregroundColor(Palette.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - StudioLayerRow

private struct StudioLayerRow: View {
    let layer: StudioLayer
    let matchCount: Int
    let isEditing: Bool
    @Binding var draftName: String
    let onRecall: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Leading content — the recall target.
            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(Typo.heading(12))
                        .foregroundColor(Palette.text)
                        .focused($nameFocused)
                        .onSubmit(onCommitRename)
                        .onExitCommand(perform: onCancelRename)
                        .onAppear { nameFocused = true }
                } else {
                    Text(layer.name)
                        .font(Typo.heading(12))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)
                }
                ruleChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if !isEditing { onRecall() } }

            // Trailing controls — never recall.
            VStack(alignment: .trailing, spacing: 6) {
                matchBadge
                if hovering && !isEditing {
                    HStack(spacing: 8) {
                        iconButton("pencil", onBeginRename)
                        iconButton("trash", onDelete)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassCard(hovered: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }

    /// The rule, shown as one chip per clause. Clauses are OR'd, so each chip is
    /// an independent way into the layer. Reuses the survey's FlowLayout to wrap.
    @ViewBuilder
    private var ruleChips: some View {
        if layer.match.isEmpty {
            Text("no rule")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
        } else {
            FlowLayout(spacing: 4, lineSpacing: 4, alignment: .leading) {
                ForEach(Array(layer.match.enumerated()), id: \.offset) { _, clause in
                    clauseChip(clause)
                }
            }
        }
    }

    private func clauseChip(_ clause: StudioLayerClause) -> some View {
        let app = clause.app?.isEmpty == false ? clause.app : nil
        let title = clause.titleContains?.isEmpty == false ? clause.titleContains : nil
        return HStack(spacing: 4) {
            if let app {
                Image(systemName: "macwindow")
                    .font(.system(size: 8))
                    .foregroundColor(Palette.textMuted)
                Text(app)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
            }
            if let title {
                Text("~\(title)")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.detach)   // amber: a title match reads distinct from an app
            }
            if app == nil && title == nil {
                Text("any")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    private var matchBadge: some View {
        let live = matchCount > 0
        return Text("\(matchCount)")
            .font(Typo.monoBold(9))
            .foregroundColor(live ? Palette.bg : Palette.textMuted)
            .frame(minWidth: 16)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(live ? Palette.running : Palette.surfaceHov))
            .help(live ? "\(matchCount) live window\(matchCount == 1 ? "" : "s") match" : "No live windows match")
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10))
                .foregroundColor(Palette.textMuted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
