import SwiftUI

// MARK: - Focus pane
//
// `.pv` — the focus layout's left column: one Mac's agent log at full size,
// tailing. The channel strip collapses to a rail above it, so the deck goes from
// "watch four" to "watch one" without changing where anything lives.

struct FleetFocusPane: View {
    let channel: FleetChannel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            caption
            screen
        }
    }

    // `.pv-cap`
    private var caption: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                FleetDot(color: FleetV6.green, size: 4)
                Text("LIVE")
            }
            Text(channel.deviceName).foregroundStyle(FleetV6.fg3)
            Text("·").foregroundStyle(Color.white.opacity(0.14))
            Text(channel.appName)
            Text("·").foregroundStyle(Color.white.opacity(0.14))
            Text(channel.state.label).foregroundStyle(stateColor)
            Spacer(minLength: 8)
            Text("\(channel.logLineCount.formatted()) lines")
                .monospacedDigit()
        }
        .font(FleetV6.mono(9, .medium))
        .tracking(1.44)
        .foregroundStyle(FleetV6.fg4)
        .lineLimit(1)
        .padding(.horizontal, 3)
        .padding(.bottom, 8)
    }

    private var stateColor: Color {
        switch channel.state {
        case .run:  return FleetV6.fg3
        case .attn: return FleetV6.amber
        case .idle: return FleetV6.fg4
        case .down: return FleetV6.red
        }
    }

    // `.pv-screen`
    private var screen: some View {
        VStack(spacing: 0) {
            logHead
            logBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FleetV6.wellBG)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(FleetV6.brk2, lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // `.lg-head`
    private var logHead: some View {
        HStack(spacing: 12) {
            Text(channel.appName).foregroundStyle(FleetV6.fg3)
            Text(channel.logSource)
                .font(FleetV6.mono(9.5, .medium))
                .tracking(0.38)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 8)
            Text("FOLLOW · TAIL")
        }
        .font(FleetV6.mono(9, .medium))
        .tracking(1.26)
        .foregroundStyle(FleetV6.fg4)
        .padding(.horizontal, 12)
        .frame(height: 22)
        .overlay(alignment: .bottom) { Rectangle().fill(FleetV6.brk2).frame(height: 1) }
    }

    // `.lg-body` — pinned to the bottom, newest line last, with the top of the
    // scrollback fading out.
    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(channel.logLines) { line in
                        FleetLogRow(line: line)
                    }
                    HStack(spacing: 12) {
                        Color.clear.frame(width: 56, height: 1)
                        Color.clear.frame(width: 66, height: 1)
                        FleetCaret()
                        Spacer(minLength: 0)
                    }
                    .id(Self.tailID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .onChange(of: channel.logLines.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.tailID, anchor: .bottom) }
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private static let tailID = "fleet-log-tail"
}

/// `.lg-row` — timestamp, source tag, message.
private struct FleetLogRow: View {
    let line: FleetLogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(line.time)
                .font(FleetV6.mono(10, weight))
                .monospacedDigit()
                .foregroundStyle(line.style == .warn ? FleetV6.amber : FleetV6.fg4)
                .frame(width: 56, alignment: .leading)

            Text(line.tag)
                .font(FleetV6.mono(9.5, weight))
                .tracking(0.95)
                .foregroundStyle(line.style == .warn ? FleetV6.amber : FleetV6.fg4)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 66, alignment: .leading)

            Text(line.message)
                .font(FleetV6.mono(11, weight))
                .foregroundStyle(messageColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1.5)
    }

    private var weight: Font.Weight {
        switch line.style {
        case .dim:       return .light
        case .highlight: return .medium
        default:         return .regular
        }
    }

    private var messageColor: Color {
        switch line.style {
        case .normal:    return FleetV6.fg3
        case .dim:       return FleetV6.fg4
        case .highlight: return FleetV6.fg
        case .warn:      return FleetV6.amber
        }
    }
}
