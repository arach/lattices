import AppKit
import SwiftUI

// MARK: - StudioLayersView
//
// The Studio panel for rule-backed layers. Each layer shows its name, the rule
// it resolves by, and how many live windows currently match. Clicking a row
// inspects that layer; the explicit focus action recalls matching windows.
// Layers are authored by plucking in Hyperspace; here you browse, rename,
// inspect, discuss, and recall them.

struct StudioLayersView: View {
    @ObservedObject private var store = StudioLayerStore.shared
    // Observed so match counts re-compute as windows open/close/retitle.
    @ObservedObject private var desktop = DesktopModel.shared
    @Binding private var selectedLayerId: String?

    @State private var editingId: String?
    @State private var draftName: String = ""

    init(selectedLayerId: Binding<String?> = .constant(nil)) {
        self._selectedLayerId = selectedLayerId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: 0.5)

            if store.layers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        allDesktopRow
                        ForEach(store.layers) { layer in
                            let matches = store.resolve(layer, in: desktop)
                            StudioLayerRow(
                                layer: layer,
                                matches: matches,
                                isSelected: selectedLayerId == layer.id,
                                isEditing: editingId == layer.id,
                                draftName: $draftName,
                                onSelect:      { selectedLayerId = layer.id },
                                onRecall:      { selectedLayerId = layer.id; store.recall(layer) },
                                onBeginRename: { draftName = layer.name; editingId = layer.id },
                                onCommitRename:{ store.rename(id: layer.id, to: draftName); editingId = nil },
                                onCancelRename:{ editingId = nil },
                                onCopySpec:    { copyLayerSpec(layer, matches: matches) },
                                onAskAssistant:{ askAssistantAboutLayer(layer, matches: matches) },
                                onDelete:      {
                                    if selectedLayerId == layer.id { selectedLayerId = nil }
                                    store.delete(id: layer.id)
                                }
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
        .overlay(alignment: .trailing) {
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
            Text("Select windows in Hyperspace, then save them as a layer.")
                .font(Typo.body(11))
                .foregroundColor(Palette.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var allDesktopRow: some View {
        let count = desktop.allWindows().filter(\.isOnScreen).count
        let isSelected = selectedLayerId == nil
        return HStack(spacing: 8) {
            Image(systemName: "display")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? Palette.running : Palette.textMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("All Desktop")
                    .font(Typo.heading(12))
                    .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                Text("whole visible desktop")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
            }
            Spacer()
            Text("\(count)")
                .font(Typo.monoBold(9))
                .foregroundColor(isSelected ? Palette.bg : Palette.textMuted)
                .frame(minWidth: 16)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(isSelected ? Palette.running : Palette.surfaceHov))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Palette.running.opacity(0.12) : Palette.surface.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? Palette.running.opacity(0.45) : Palette.border, lineWidth: 0.75)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedLayerId = nil }
        .help("Show the whole desktop")
    }

    private func copyLayerSpec(_ layer: StudioLayer, matches: [WindowEntry]) {
        let text = store.layerContextJSON(layer, matches: matches)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DiagnosticLog.shared.success("Copied layer spec for '\(layer.name)' (\(text.count) chars)")
    }

    private func askAssistantAboutLayer(_ layer: StudioLayer, matches: [WindowEntry]) {
        let spec = store.layerContextJSON(layer, matches: matches)
        let prompt = """
        Help me reason about this Lattices Studio layer. Explain what the rules mean, what live windows currently match, and suggest a cleaner rule if the layer is too broad or too narrow.

        \(spec)
        """
        ScreenMapWindowController.shared.showAssistant()
        PiChatSession.shared.draft = prompt
        PiChatSession.shared.sendDraft()
    }
}

// MARK: - StudioLayerRow

private struct StudioLayerRow: View {
    let layer: StudioLayer
    let matches: [WindowEntry]
    let isSelected: Bool
    let isEditing: Bool
    @Binding var draftName: String
    let onSelect: () -> Void
    let onRecall: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onCopySpec: () -> Void
    let onAskAssistant: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
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
                        HStack(spacing: 6) {
                            Text(layer.name)
                                .font(Typo.heading(12))
                                .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                                .lineLimit(1)
                            if isSelected {
                                Text("viewing")
                                    .font(Typo.monoBold(7))
                                    .foregroundColor(Palette.running)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(Palette.running.opacity(0.12)))
                            }
                        }
                    }
                    ruleChips
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if !isEditing { onSelect() } }

                VStack(alignment: .trailing, spacing: 6) {
                    matchBadge
                    if (hovering || isSelected) && !isEditing {
                        HStack(spacing: 8) {
                            iconButton("arrow.up.forward.square", onRecall, help: "Focus matching windows")
                            iconButton("pencil", onBeginRename, help: "Rename layer")
                            iconButton("doc.on.doc", onCopySpec, help: "Copy layer spec")
                            iconButton("sparkles", onAskAssistant, help: "Ask assistant about this layer")
                            iconButton("trash", onDelete, help: "Delete layer")
                        }
                    }
                }
            }

            if isSelected && !isEditing {
                selectedDetails
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Palette.running.opacity(0.10) : (hovering ? Palette.surfaceHov : Palette.surface.opacity(0.65)))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? Palette.running.opacity(0.45) : Palette.border, lineWidth: isSelected ? 0.9 : 0.5)
                )
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
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
        return HStack(spacing: 4) {
            Image(systemName: clause.not?.isEmpty == false ? "line.3.horizontal.decrease.circle" : "scope")
                .font(.system(size: 8))
                .foregroundColor(Palette.textMuted)
            Text(clause.summary)
                .font(Typo.mono(10))
                .foregroundColor(clause.not?.isEmpty == false ? Palette.detach : Palette.textDim)
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
        let live = !matches.isEmpty
        return Text("\(matches.count)")
            .font(Typo.monoBold(9))
            .foregroundColor(live ? Palette.bg : Palette.textMuted)
            .frame(minWidth: 16)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(live ? Palette.running : Palette.surfaceHov))
            .help(live ? "\(matches.count) live window\(matches.count == 1 ? "" : "s") match" : "No live windows match")
    }

    private var selectedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            specPanel

            HStack(spacing: 6) {
                Text("WINDOWS")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted)
                Text("\(matches.count)")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
                Spacer()
            }
            if matches.isEmpty {
                Text("No live windows match these rules.")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
            } else {
                VStack(spacing: 3) {
                    ForEach(matches.prefix(8), id: \.wid) { win in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Palette.running.opacity(0.7))
                                .frame(width: 4, height: 4)
                            Text(win.app)
                                .font(Typo.monoBold(8))
                                .foregroundColor(Palette.textDim)
                                .lineLimit(1)
                                .frame(width: 58, alignment: .leading)
                            Text(win.title.isEmpty ? "—" : win.title)
                                .font(Typo.mono(8))
                                .foregroundColor(Palette.textMuted)
                                .lineLimit(1)
                        }
                    }
                    if matches.count > 8 {
                        Text("+\(matches.count - 8) more")
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    private var specPanel: some View {
        let spec = StudioLayerStore.shared.layerContextJSON(layer, matches: matches)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("SPEC")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted)
                Text("lattices.studio-layer.v1")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(1)
                Spacer()
                compactAction("doc.on.doc", onCopySpec, help: "Copy layer spec")
                compactAction("sparkles", onAskAssistant, help: "Ask assistant about this layer")
            }

            ScrollView([.vertical, .horizontal]) {
                Text(spec)
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textDim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(7)
            }
            .frame(maxHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.border, lineWidth: 0.5))
            )
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10))
                .foregroundColor(Palette.textMuted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func compactAction(_ name: String, _ action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Palette.textMuted)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
