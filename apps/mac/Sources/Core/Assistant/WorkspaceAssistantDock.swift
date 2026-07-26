import SwiftUI

struct WorkspaceAssistantDock: View {
    @ObservedObject var session: WorkspaceAssistantSession
    @FocusState private var composerFocused: Bool
    @State private var resizeStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            topHandle

            WorkspaceAssistantTranscript(session: session, style: .dock)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            WorkspaceAssistantComposer(session: session, style: .dock, focus: $composerFocused)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            footerBar
        }
        .frame(maxWidth: .infinity)
        .frame(height: session.dockHeight)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.96),
                    Color(red: 0.02, green: 0.05, blue: 0.03),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .onAppear {
            session.prepareForDisplay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                composerFocused = true
            }
        }
    }

    private var topHandle: some View {
        HStack {
            Spacer()

            Capsule()
                .fill(Palette.borderLit)
                .frame(width: 64, height: 4)

            Spacer()

            Button {
                session.isVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Palette.textMuted)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.03))
                            .overlay(
                                Circle()
                                    .strokeBorder(Palette.border, lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if resizeStartHeight == nil {
                        resizeStartHeight = session.dockHeight
                    }
                    let start = resizeStartHeight ?? session.dockHeight
                    session.dockHeight = start - value.translation.height
                }
                .onEnded { _ in
                    resizeStartHeight = nil
                }
        )
    }

    private var legacyTranscriptPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(session.messages) { message in
                    Text(message.text)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                        .padding(10)
                }
            }
            .padding(10)
        }
        .background(Color.black.opacity(0.35))
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.isScoutAvailable == false ? Palette.detach : Palette.running)
                .frame(width: 6, height: 6)

            Text("ASSISTANT")
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.text)

            Text(footerStatusText)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)

            Spacer()

            if session.hasConversationHistory {
                footerIconButton(systemName: "doc.on.doc", help: "Copy chat") {
                    session.copyConversationToClipboard()
                }
            }

            footerIconButton(systemName: "gearshape", help: "Assistant settings") {
                SettingsWindowController.shared.showAssistant()
            }

            footerButton("reset") {
                session.clearConversation()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.015))
    }

    private var footerStatusText: String {
        if session.statusText == "idle" {
            return session.setupStatusSummary
        }
        return "Scout · \(session.statusText)"
    }

    private func footerButton(_ label: String, tint: Color = Palette.textMuted, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(Typo.geistMonoBold(9))
            .foregroundColor(disabled ? Palette.textMuted : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        Capsule()
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
            .opacity(disabled ? 0.65 : 1)
            .disabled(disabled)
    }

    private func footerIconButton(systemName: String, tint: Color = Palette.textMuted, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24, height: 22)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.03))
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

}
