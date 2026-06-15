import SwiftUI

/// The command bar UI: one input that filters commands (and placements) for the
/// captured frontmost window. Arrow keys / Enter / Tab are handled by
/// `CommandBarWindow`'s key monitor; clicking a row commits it.
struct CommandBarView: View {
    @ObservedObject var state: CommandBarState
    let appName: String
    var onCommit: () -> Void
    var onDismiss: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputRow

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            if state.suggestions.isEmpty {
                emptyState
            } else {
                suggestionList
            }
        }
        .frame(width: 560)
        .background(PanelBackground())
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .foregroundColor(Palette.textMuted)
                .font(.system(size: 13))

            if let ctx = state.contextLabel {
                Text(ctx)
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Palette.surfaceHov))
            }

            TextField(placeholder, text: $state.query)
                .textFieldStyle(.plain)
                .font(Typo.mono(14))
                .foregroundColor(Palette.text)
                .focused($focused)
                .onSubmit { onCommit() }

            if !state.query.isEmpty {
                Button { state.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Palette.textMuted)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Palette.surface)
    }

    private var placeholder: String {
        state.contextLabel == nil
            ? "Place or command \(appName)…  right · display 2 · hide · focus safari"
            : "Pick a value…"
    }

    private var suggestionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { idx, s in
                        row(s, index: idx).id(s.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 300)
            .onChange(of: state.selectedIndex) { newVal in
                guard newVal >= 0, newVal < state.suggestions.count else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(state.suggestions[newVal].id, anchor: .center)
                }
            }
        }
    }

    private func row(_ s: CommandSuggestion, index: Int) -> some View {
        let selected = index == state.selectedIndex
        return Button {
            state.selectedIndex = index
            onCommit()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: s.glyph)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(selected ? Palette.text : Palette.textDim)
                    .frame(width: 16)

                Text(s.label)
                    .font(Typo.mono(12))
                    .foregroundColor(selected ? Palette.text : Palette.textDim)
                    .lineLimit(1)

                Spacer()

                if s.isFill {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                } else {
                    Text(s.detail)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Palette.surfaceHov : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "command")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Palette.textMuted)
            Text("No match for \"\(state.query)\"")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textDim)
            Spacer()
        }
        .frame(height: 120)
    }
}
