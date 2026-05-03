import SwiftUI

/// Foreground machine "third monitor" overflow content. Rendered only when
/// a machine is marked `isForeground` — these are the things that don't fit
/// on the foreground Mac's own screens (agent feed, terminal tail, calendar,
/// attention queue).
///
/// Composition: 2x2 grid of tiles on iPad portrait; can adapt to 1x4 on
/// narrower widths via `.adaptive`.
///
/// Size budget: ~320-400pt for the 2x2 cluster (per tile ~140-180pt tall).
struct HomeOverflowGrid: View {
    let machine: HomeMachine?
    let agentFeed: [HomeAgentFeedEntry]
    let terminal: [HomeTerminalLine]
    let calendar: [HomeCalendarEvent]
    let attention: [HomeAttentionItem]

    var onAttention: ((HomeAttentionItem) -> Void)? = nil
    var onCalendar: ((HomeCalendarEvent) -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 520), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            if let machine {
                LazyVGrid(columns: columns, spacing: 12) {
                    AgentFeedTile(machine: machine, entries: agentFeed)
                    TerminalTile(machine: machine, lines: terminal)
                    CalendarTile(events: calendar, onTap: onCalendar)
                    AttentionTile(items: attention, onTap: onAttention)
                }
            } else {
                LatsEmptyState(
                    title: "No foreground machine",
                    subtitle: "Pair a Mac and bring it to focus to mirror its overflow here.",
                    icon: "rectangle.dashed"
                )
            }
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            LatsSectionLabel(text: "Overflow · \(machine?.name ?? "—")")
            Spacer()
            Text("third monitor · live")
                .font(LatsFont.mono(9))
                .tracking(0.6)
                .foregroundStyle(LatsPalette.textFaint)
        }
    }
}

// MARK: - Shared tile chrome

private struct OverflowTileFrame<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var tint: Color = LatsPalette.textFaint
    var washTint: Color? = nil
    var minHeight: CGFloat = 148
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(LatsFont.mono(9, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(tint)
                Spacer(minLength: 6)
                if let trailing {
                    Text(trailing)
                        .font(LatsFont.mono(9))
                        .tracking(0.6)
                        .foregroundStyle(LatsPalette.textFaint)
                        .lineLimit(1)
                }
            }
            LatsHairlineDivider()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LatsPalette.surface)
                RoundedRectangle(cornerRadius: 8)
                    .fill((washTint ?? .clear).opacity(0.05))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }
}

// MARK: - Agent feed tile

private struct AgentFeedTile: View {
    let machine: HomeMachine
    let entries: [HomeAgentFeedEntry]

    private var sourceLabel: String {
        // Pull a friendly agent name out of running task if we have one,
        // otherwise just stamp it "claude" as the canonical default.
        switch machine.agentState {
        case .running, .waiting: return "claude"
        case .idle: return "idle"
        }
    }

    var body: some View {
        OverflowTileFrame(
            title: "Agent · \(sourceLabel)",
            trailing: "\(entries.count) evt",
            tint: LatsPalette.violet.opacity(0.9),
            washTint: LatsPalette.violet
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entries.prefix(3)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.glyph)
                            .font(LatsFont.mono(11, weight: .semibold))
                            .foregroundStyle(entry.tint.color)
                            .frame(width: 12, alignment: .leading)
                        Text(entry.text)
                            .font(LatsFont.mono(11))
                            .foregroundStyle(entry.tint.color.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
                if entries.isEmpty {
                    Text("no agent activity")
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textFaint)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Terminal tile

private struct TerminalTile: View {
    let machine: HomeMachine
    let lines: [HomeTerminalLine]

    private var appLabel: String {
        machine.focusedApp == "iTerm" || machine.focusedApp == "iTerm2" ? "iTerm" : "iTerm"
    }

    var body: some View {
        OverflowTileFrame(
            title: "Terminal · \(appLabel)",
            trailing: machine.host,
            tint: LatsPalette.green.opacity(0.85),
            washTint: LatsPalette.teal
        ) {
            // Tiny terminal pane: black-ish inset, mono-only, prompt accent.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines.prefix(4)) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if line.isPrompt {
                            Text("~/")
                                .font(LatsFont.mono(10, weight: .semibold))
                                .foregroundStyle(LatsPalette.green.opacity(0.85))
                        } else {
                            Text("›")
                                .font(LatsFont.mono(10))
                                .foregroundStyle(LatsPalette.textFaint)
                        }
                        Text(line.text)
                            .font(LatsFont.mono(10))
                            .foregroundStyle(
                                line.isPrompt
                                    ? LatsPalette.textDim
                                    : LatsPalette.text.opacity(0.86)
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
                if lines.isEmpty {
                    Text("$ —")
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textFaint)
                }
                // Trailing live cursor
                HStack(spacing: 6) {
                    Text("$")
                        .font(LatsFont.mono(10, weight: .semibold))
                        .foregroundStyle(LatsPalette.green.opacity(0.7))
                    Rectangle()
                        .fill(LatsPalette.green.opacity(0.7))
                        .frame(width: 6, height: 10)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(LatsPalette.hairline, lineWidth: 1)
            )
        }
    }
}

// MARK: - Calendar tile

private struct CalendarTile: View {
    let events: [HomeCalendarEvent]
    var onTap: ((HomeCalendarEvent) -> Void)? = nil

    var body: some View {
        OverflowTileFrame(
            title: "Calendar",
            trailing: "today",
            tint: LatsPalette.blue.opacity(0.9),
            washTint: LatsPalette.blue
        ) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { pair in
                    let isNext = (pair.offset == 0)
                    Button {
                        onTap?(pair.element)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(pair.element.timeLabel)
                                .font(LatsFont.mono(11, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(
                                    isNext
                                        ? LatsPalette.blue
                                        : LatsPalette.textDim
                                )
                                .frame(width: 56, alignment: .leading)
                            Text(pair.element.title)
                                .font(LatsFont.ui(12, weight: isNext ? .semibold : .regular))
                                .foregroundStyle(
                                    isNext
                                        ? LatsPalette.text
                                        : LatsPalette.text.opacity(0.78)
                                )
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if isNext {
                                Circle()
                                    .fill(LatsPalette.blue)
                                    .frame(width: 5, height: 5)
                                    .overlay(
                                        Circle()
                                            .stroke(LatsPalette.blue.opacity(0.4), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(onTap == nil)
                }
                if events.isEmpty {
                    Text("nothing on the books")
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textFaint)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Attention tile

private struct AttentionTile: View {
    let items: [HomeAttentionItem]
    var onTap: ((HomeAttentionItem) -> Void)? = nil

    // Calm when empty, warm-but-not-alarming when items need a look.
    // Red is reserved for individual items that are genuinely critical
    // (item.tint), not the persistent tile chrome.
    private var accentTint: Color {
        items.isEmpty ? LatsPalette.green : LatsPalette.amber
    }

    var body: some View {
        OverflowTileFrame(
            title: "Attention",
            trailing: nil,
            tint: accentTint.opacity(0.9),
            washTint: accentTint
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.prefix(4)) { item in
                    Button {
                        onTap?(item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(item.tint.color)
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(item.tint.color.opacity(0.14))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(item.tint.color.opacity(0.30), lineWidth: 1)
                                )
                            Text(item.label)
                                .font(LatsFont.ui(12, weight: .medium))
                                .foregroundStyle(LatsPalette.text.opacity(0.92))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(LatsPalette.textFaint)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.025))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(LatsPalette.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(onTap == nil)
                }
                if items.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LatsPalette.green)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(LatsPalette.green.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(LatsPalette.green.opacity(0.30), lineWidth: 1)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text("all clear")
                                .font(LatsFont.ui(12, weight: .medium))
                                .foregroundStyle(LatsPalette.text.opacity(0.92))
                            Text("nothing waiting")
                                .font(LatsFont.mono(10))
                                .foregroundStyle(LatsPalette.textFaint)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !items.isEmpty {
                Text("\(items.count)")
                    .font(LatsFont.mono(9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(accentTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accentTint.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(accentTint.opacity(0.45), lineWidth: 1)
                    )
                    .padding(10)
            }
        }
    }
}

// MARK: - Previews

#Preview("Overflow — foreground machine") {
    LatsBackground {
        ScrollView {
            HomeOverflowGrid(
                machine: HomeMock.fleet.first,
                agentFeed: HomeMock.agentFeed,
                terminal: HomeMock.terminal,
                calendar: HomeMock.calendar,
                attention: HomeMock.attention
            )
            .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Overflow — no foreground") {
    LatsBackground {
        ScrollView {
            HomeOverflowGrid(
                machine: nil,
                agentFeed: [],
                terminal: [],
                calendar: [],
                attention: []
            )
            .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Overflow — narrow / 1-col") {
    LatsBackground {
        ScrollView {
            HomeOverflowGrid(
                machine: HomeMock.fleet.first,
                agentFeed: HomeMock.agentFeed,
                terminal: HomeMock.terminal,
                calendar: HomeMock.calendar,
                attention: HomeMock.attention
            )
            .padding(14)
            .frame(width: 380)
        }
    }
    .preferredColorScheme(.dark)
}
