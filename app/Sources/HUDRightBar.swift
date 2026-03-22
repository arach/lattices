import SwiftUI

// MARK: - HUDRightBar (inspector + conversation)

struct HUDRightBar: View {
    @ObservedObject var state: HUDState
    @ObservedObject private var handsOff = HandsOffSession.shared
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top half: inspector
            inspectorPane
                .frame(maxHeight: .infinity)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Bottom half: conversation
            conversationPane
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Inspector (top half)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @ViewBuilder
    private var inspectorPane: some View {
        if let item = state.selectedItem {
            detailView(for: item)
        } else {
            inspectorEmpty
        }
    }

    private var inspectorEmpty: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 22))
                .foregroundColor(Palette.textMuted.opacity(0.3))
            Text("Select an item")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
            Spacer()
        }
    }

    @ViewBuilder
    private func detailView(for item: HUDItem) -> some View {
        switch item {
        case .project(let p): projectDetail(p)
        case .window(let w):  windowDetail(w)
        }
    }

    private func projectDetail(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(project.isRunning ? Palette.running : Palette.textMuted.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(Typo.monoBold(13))
                    .foregroundColor(Palette.text)
                Spacer()
                if project.isRunning {
                    Text("running")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Palette.running.opacity(0.10)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    metaRow("Path", value: project.path)
                    metaRow("Session", value: project.sessionName)
                    if !project.paneSummary.isEmpty { metaRow("Summary", value: project.paneSummary) }
                    if let dev = project.devCommand { metaRow("Dev", value: dev) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            HStack(spacing: 8) {
                actionButton(project.isRunning ? "Focus" : "Launch",
                             icon: project.isRunning ? "eye" : "play.fill") {
                    SessionManager.launch(project: project)
                    onDismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func windowDetail(_ window: WindowEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(window.title)
                    .font(Typo.monoBold(12))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                Text(window.app)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    metaRow("WID", value: "\(window.wid)")
                    metaRow("Frame", value: "\(Int(window.frame.x)),\(Int(window.frame.y)) \(Int(window.frame.w))×\(Int(window.frame.h))")
                    if let session = window.latticesSession { metaRow("Session", value: session) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            HStack(spacing: 8) {
                actionButton("Focus", icon: "eye") {
                    _ = WindowTiler.focusWindow(wid: window.wid, pid: window.pid)
                    onDismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Conversation (bottom half)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var conversationPane: some View {
        VStack(spacing: 0) {
            // Header with voice state
            conversationHeader

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Messages
            if handsOff.conversationHistory.isEmpty {
                conversationEmpty
            } else {
                conversationMessages
            }
        }
    }

    private var conversationHeader: some View {
        HStack(spacing: 8) {
            // Voice indicator
            voiceIndicator

            Text("Voice")
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)

            Spacer()

            // State badge
            if state.voiceActive {
                stateBadge
            }

            // V toggle hint
            Text("V")
                .font(Typo.geistMonoBold(9))
                .foregroundColor(state.voiceActive ? Palette.text : Palette.textMuted)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(state.voiceActive ? Palette.running.opacity(0.2) : Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(state.voiceActive ? Palette.running.opacity(0.4) : Palette.border, lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var voiceIndicator: some View {
        Circle()
            .fill(voiceColor)
            .frame(width: 8, height: 8)
            .overlay(
                // Pulse animation when listening
                Circle()
                    .stroke(voiceColor.opacity(0.4), lineWidth: 1.5)
                    .scaleEffect(handsOff.state == .listening ? 1.8 : 1.0)
                    .opacity(handsOff.state == .listening ? 0 : 1)
                    .animation(
                        handsOff.state == .listening
                            ? .easeOut(duration: 1.0).repeatForever(autoreverses: false)
                            : .default,
                        value: handsOff.state
                    )
            )
    }

    private var voiceColor: Color {
        switch handsOff.state {
        case .idle:       return state.voiceActive ? Palette.running : Palette.textMuted.opacity(0.3)
        case .connecting: return Palette.detach
        case .listening:  return Palette.running
        case .thinking:   return Palette.detach
        }
    }

    private var stateBadge: some View {
        let label: String = {
            switch handsOff.state {
            case .idle:       return "ready"
            case .connecting: return "connecting"
            case .listening:  return "listening"
            case .thinking:   return "thinking"
            }
        }()

        return Text(label)
            .font(Typo.mono(9))
            .foregroundColor(voiceColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(voiceColor.opacity(0.10))
            )
    }

    private var conversationEmpty: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundColor(Palette.textMuted.opacity(0.3))
            Text(state.voiceActive ? "Listening..." : "Press V to talk")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
            Spacer()
        }
    }

    private var conversationMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(handsOff.conversationHistory.enumerated()), id: \.offset) { index, msg in
                        messageBubble(msg, index: index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: handsOff.conversationHistory.count) { _ in
                // Auto-scroll to bottom
                if let last = handsOff.conversationHistory.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func messageBubble(_ msg: [String: String], index: Int) -> some View {
        let role = msg["role"] ?? "unknown"
        let content = msg["content"] ?? ""
        let isUser = role == "user"

        return HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                Text(isUser ? "you" : "lattices")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted)
                    .textCase(.uppercase)

                Text(content)
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isUser ? Palette.surfaceHov : Palette.surface)
                    )
                    .textSelection(.enabled)
            }
            .id(index)

            if !isUser { Spacer(minLength: 40) }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shared helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func metaRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typo.monoBold(9))
                .foregroundColor(Palette.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(Typo.mono(11))
                .foregroundColor(Palette.text)
                .textSelection(.enabled)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(Typo.monoBold(10))
            }
            .foregroundColor(Palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
