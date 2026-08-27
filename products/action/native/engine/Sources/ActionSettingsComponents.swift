import AppKit
import SwiftUI

// MARK: - Product links

enum ActionDocs {
    static let siteURL = URL(string: "https://arach.github.io/action/")!
    static let siteHostLabel = "arach.github.io/action"
}

extension Notification.Name {
    static let actionShowKeyboardCheatSheet = Notification.Name("Action.ShowKeyboardCheatSheet")
}

// MARK: - Settings primitives
// Inspired by HudsonUI HudSettings + Scout settings rows:
// calm static rows, section labels, surface cards — not dense list chrome.

struct ActionSettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(ActionType.uiCaptionStrong)
            .tracking(0.6)
            .foregroundStyle(StageHUDTheme.textMuted)
    }
}

struct ActionSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActionSettingsSectionLabel(title: title)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(StageHUDTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct ActionSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(StageHUDTheme.cardBorder)
            .frame(height: 1)
            .padding(.leading, 52)
    }
}

struct ActionSettingsLeadingIcon: View {
    let systemName: String
    var color: Color = StageHUDTheme.textMuted

    var body: some View {
        Image(systemName: systemName)
            .font(ActionIcon.medium)
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
    }
}

/// Informational or tappable settings row: icon · title/subtitle · trailing badge.
struct ActionSettingsRow<Badge: View>: View {
    let icon: String
    var iconColor: Color = StageHUDTheme.textMuted
    let title: String
    var subtitle: String? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder var badge: () -> Badge

    var body: some View {
        let row = HStack(spacing: 12) {
            ActionSettingsLeadingIcon(systemName: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ActionType.uiBodyStrong)
                    .foregroundStyle(StageHUDTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(ActionType.uiCaption)
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            badge()

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(ActionIcon.small)
                    .foregroundStyle(StageHUDTheme.textMuted.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }
}

extension ActionSettingsRow where Badge == EmptyView {
    init(
        icon: String,
        iconColor: Color = StageHUDTheme.textMuted,
        title: String,
        subtitle: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            onTap: onTap,
            badge: { EmptyView() }
        )
    }
}

/// Title/subtitle on the left, control on the right.
struct ActionSettingsControlRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconColor: Color = StageHUDTheme.textMuted
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                ActionSettingsLeadingIcon(systemName: icon, color: iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ActionType.uiBodyStrong)
                    .foregroundStyle(StageHUDTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(ActionType.uiCaption)
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ActionSettingsStatusBadge: View {
    enum Kind {
        case ok
        case warning
        case neutral
        case offline
    }

    let text: String
    var kind: Kind = .neutral

    private var color: Color {
        switch kind {
        case .ok:
            return StageHUDTheme.runOk
        case .warning:
            return StageHUDTheme.hudAmber
        case .offline:
            return StageHUDTheme.runFailed.opacity(0.85)
        case .neutral:
            return StageHUDTheme.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(ActionType.uiCaptionStrong)
                .foregroundStyle(StageHUDTheme.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(StageHUDTheme.buttonSecondaryHover.opacity(0.85))
        )
    }
}

/// Permission row patterned after Lattices: status + detail + action.
struct ActionSettingsPermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var statusLabel: String? = nil
    let primaryActionTitle: String
    let onPrimary: () -> Void
    var onOpenSettings: (() -> Void)? = nil

    private var resolvedStatus: String {
        statusLabel ?? (granted ? "Granted" : "Needed")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ActionSettingsLeadingIcon(
                systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                color: granted ? StageHUDTheme.runOk : StageHUDTheme.hudAmber
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(ActionType.uiBodyStrong)
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    ActionSettingsStatusBadge(
                        text: resolvedStatus,
                        kind: granted ? .ok : .warning
                    )
                }
                Text(detail)
                    .font(ActionType.uiCaption)
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if !granted {
                Button(primaryActionTitle, action: onPrimary)
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
            }

            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(ActionIcon.medium)
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open System Settings")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ActionSettingsPillButtonStyle: ButtonStyle {
    var primary: Bool = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if primary {
            ActionQuietButtonLabel(configuration: configuration)
        } else {
            secondary(configuration)
        }
    }

    private func secondary(_ configuration: Configuration) -> some View {
        configuration.label
            .font(ActionType.uiBodyStrong)
            .foregroundStyle(primary ? StageHUDTheme.buttonPrimaryText : StageHUDTheme.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(primary
                        ? (configuration.isPressed ? StageHUDTheme.buttonPrimaryBottom : StageHUDTheme.buttonPrimaryTop)
                        : (configuration.isPressed ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.buttonSecondary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(primary ? Color.clear : StageHUDTheme.cardBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// The quiet primary.
///
/// A filled black pill is the loudest object on a page that has nothing else
/// on it, and it makes the one thing you can do here look like a warning. This
/// says the same thing with a hairline: ink label, hairline border, paper
/// inside. It gains weight only under the pointer — the border darkens and the
/// ground picks up a hint of ink — and commits to solid ink on press, so the
/// emphasis arrives at the moment of the click rather than sitting on the page
/// waiting for it.
///
/// No accent. A page whose only colour is the one the operator is about to
/// touch does not need a second one to point at it.
struct ActionQuietButtonStyle: ButtonStyle {
    /// Trailing hint, set in mono, for the key that does the same thing.
    var shortcut: String?

    func makeBody(configuration: Configuration) -> some View {
        ActionQuietButtonLabel(configuration: configuration, shortcut: shortcut)
    }
}

/// The quiet primary's drawing, shared so that the launcher's header button,
/// the settings pill and `ActionQuietButtonStyle` are one object rather than
/// three that happen to look alike. The app had two primary treatments four
/// inches apart on the same page.
struct ActionQuietButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    var shortcut: String?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
                .font(ActionType.uiBodyStrong)
            if let shortcut {
                Text(shortcut)
                    .font(ActionType.monoCaption)
                    .opacity(0.55)
            }
        }
        .foregroundStyle(configuration.isPressed ? StageHUDTheme.buttonPrimaryText : StageHUDTheme.textPrimary)
        .padding(.horizontal, 15)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(border, lineWidth: StageHUDTheme.hairline)
        )
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovered = $0 && isEnabled }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var fill: Color {
        if configuration.isPressed { return StageHUDTheme.buttonPrimaryTop }
        return hovered ? StageHUDTheme.textPrimary.opacity(0.05) : .clear
    }

    private var border: Color {
        if configuration.isPressed { return .clear }
        return StageHUDTheme.textPrimary.opacity(hovered ? 0.5 : 0.24)
    }
}

/// A ruled column header: one word, mono, tracked, over a hairline.
///
/// Used where a list is really a table. The header is what makes a right-hand
/// column read as a column rather than as a stray value that drifted away from
/// its row.
struct ActionColumnHeader: View {
    let title: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        Text(title)
            .font(ActionType.label)
            .tracking(ActionType.labelTracking)
            .foregroundStyle(StageHUDTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

/// A rule at the theme's hairline weight.
struct ActionRule: View {
    var opacity: Double = 1

    var body: some View {
        Rectangle()
            .fill(StageHUDTheme.cardBorder.opacity(opacity))
            .frame(height: StageHUDTheme.hairline)
    }
}

/// A settings pane's heading.
///
/// Same three lines as every other page. The pane's glyph is gone: it already
/// sits beside the pane's name in the sub-nav two inches to the left, and
/// repeating it here — tinted, alone on its own line, at a size that matched
/// nothing around it — read as a stray mark rather than as a heading.
/// "SETTINGS" takes the eyebrow because the launcher's own header is not
/// drawn over this shell, so it is the only line that says where you are.
struct ActionSettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        ActionPageHeading(eyebrow: "SETTINGS", title: title, subtitle: subtitle)
    }
}

// MARK: - Keyboard cheat sheet

struct ActionKeyboardCheatSheetView: View {
    var onOpenDocs: () -> Void = {
        NSWorkspace.shared.open(ActionDocs.siteURL)
    }
    var onClose: (() -> Void)?

    private let groups: [(title: String, rows: [(keys: String, action: String)])] = [
        (
            "App",
            [
                ("⌘1", "Home"),
                ("⌘2", "Scenarios"),
                ("⌘3", "Runs"),
                ("⌘4", "Library"),
                ("⌘5", "Settings"),
                ("⌘,", "Settings window"),
                ("⌘/", "This cheat sheet"),
                ("?", "This cheat sheet"),
            ]
        ),
        (
            "Scenarios",
            [
                ("New scenario", "Draft a Calculator plan"),
                ("Run", "Capture from the plan"),
                ("Plan / Last take", "Toggle when a take exists"),
            ]
        ),
        (
            "Library",
            [
                ("Click", "Open take"),
                ("Hover", "Quick actions"),
                ("Right-click", "Replay, Finder, Delete…"),
            ]
        ),
        (
            "Review (media notes)",
            [
                ("N", "Open note composer"),
                ("1 / 2 / 3 / 4", "Point · Range · Region · Draw"),
                ("Space", "Play / pause"),
                ("Esc", "Cancel selection / close composer"),
                ("⌘↩", "Save note"),
                ("[ / ]", "Previous / next note"),
            ]
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard")
                        .font(ActionType.uiTitle)
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Quick navigation for Action.")
                        .font(ActionType.uiBody)
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
                Spacer()
                if let onClose {
                    Button("Done", action: onClose)
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                }
            }

            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title.uppercased())
                        .font(ActionType.uiCaptionStrong)
                        .tracking(0.5)
                        .foregroundStyle(StageHUDTheme.textMuted)

                    VStack(spacing: 0) {
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { index, row in
                            HStack {
                                Text(row.keys)
                                    .font(ActionType.mono(12, weight: .semibold))
                                    .foregroundStyle(StageHUDTheme.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(StageHUDTheme.buttonSecondaryHover)
                                    )
                                Spacer(minLength: 12)
                                Text(row.action)
                                    .font(ActionType.uiBody)
                                    .foregroundStyle(StageHUDTheme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)

                            if index < group.rows.count - 1 {
                                Rectangle()
                                    .fill(StageHUDTheme.cardBorder)
                                    .frame(height: 1)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(StageHUDTheme.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 10) {
                Button {
                    onOpenDocs()
                } label: {
                    Label("Documentation", systemImage: "book")
                }
                .buttonStyle(ActionSettingsPillButtonStyle())

                Text(ActionDocs.siteHostLabel)
                    .font(ActionType.monoCaption)
                    .foregroundStyle(StageHUDTheme.textMuted)

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(StageHUDTheme.appBackground)
    }
}

// MARK: - Theme picker

/// One theme, drawn rather than named.
///
/// The card is the app in miniature and in the same order: the rail band across
/// the top, the page beneath it, a card on the page, two weights of ink on the
/// card, the accent as a rule down the side. Nothing here is decorative — every
/// element is a token the theme actually sets, so a palette that gets the
/// panel-to-page separation wrong looks wrong at 130 points, which is the whole
/// point of showing it.
struct ActionThemeSwatch: View {
    let entry: ActionThemeCatalogEntry
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var preview: ActionThemePreview { entry.preview }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                specimen
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                    )

                HStack(spacing: 5) {
                    Text(entry.name)
                        .font(ActionType.uiBody)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .lineLimit(1)

                    if entry.issues.contains(where: { $0.severity == .error }) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(ActionIcon.micro)
                            .foregroundStyle(StageHUDTheme.runFailed)
                            .help("This theme has an error and is not installed.")
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        // Ink. Every card in this grid is a colour sample, so a
                        // coral ring and a coral tick meant the selection mark
                        // was competing with the very thing being sampled — and
                        // coral is the app's signal for a live drive, not for
                        // "this one is picked".
                        Image(systemName: "checkmark.circle.fill")
                            .font(ActionIcon.small)
                            .foregroundStyle(StageHUDTheme.textPrimary)
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? StageHUDTheme.runSelection : (isHovering ? StageHUDTheme.buttonSecondaryHover : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? StageHUDTheme.textPrimary.opacity(0.55) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(entry.summary ?? entry.name)
        .accessibilityLabel("\(entry.name) theme")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var specimen: some View {
        VStack(spacing: 0) {
            // The rail band, with the traffic-light cluster that sits on it.
            HStack(spacing: 2.5) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(preview.inkSecondary.opacity(0.30))
                        .frame(width: 3.5, height: 3.5)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 13)
            .frame(maxWidth: .infinity)
            .background(preview.band)

            // The page, and a card laid on it.
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(preview.accent)
                    .frame(width: 3)
                    .padding(.vertical, 7)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(preview.ink)
                            .frame(width: 30, height: 4)
                        Spacer(minLength: 0)
                        // The accent, at the size it is actually used. A theme's
                        // accent is the fastest thing to tell two palettes apart
                        // by and the easiest to get wrong, so the specimen has to
                        // show enough of it to judge.
                        Capsule()
                            .fill(preview.accent)
                            .frame(width: 16, height: 6)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(preview.accent)
                                .frame(width: 4, height: 4)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(preview.ink.opacity(0.75))
                                .frame(width: 42, height: 3)
                        }
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(preview.inkSecondary)
                            .frame(width: 32, height: 3)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(preview.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(preview.edge, lineWidth: 1)
                            )
                    )

                    // The dark block: the command well, which stays dark in
                    // both appearances and is the fastest tell that a theme
                    // understood the recess.
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(preview.deep)
                        .frame(height: 9)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(preview.canvas)
        }
    }
}

// MARK: - Page heading

/// The heading every page in the launcher wears.
///
/// Before this existed there were three of them: Home set a 34pt editorial
/// title under a tracked eyebrow, Scenarios/Runs/Library set a 22pt sans title
/// over a subtitle, and each Settings pane set a stray tinted glyph over the
/// same 22pt title. Three sizes, three structures, and a header that changed
/// height as you moved between pages.
///
/// One shape now. The eyebrow says what the page is *for* and is the only line
/// that carries colour; the title names it; the subtitle carries whatever is
/// live — a count, a filter, the selected scenario. Static above, changing
/// below, so the eye learns where to look for news.
struct ActionPageHeading: View {
    let eyebrow: String
    let title: String
    /// Optional: a page whose state is the page itself has nothing to put here,
    /// and an invented line of description is worse than no line.
    let subtitle: String?
    /// Home sits on the field canvas and the rest of the app on chrome; the two
    /// surfaces have separate ink ramps, so the caller says which one it is on.
    var ink: Color = StageHUDTheme.textPrimary
    var inkSecondary: Color = StageHUDTheme.textSecondary
    var inkMuted: Color = StageHUDTheme.textMuted

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Ink, not accent. Action spends colour on state — coral for a Mac
            // being driven, blue for what is selected — and an eyebrow is
            // neither. Tinting it made the page label read as a live signal,
            // and made the same line coral on Home and blue everywhere else.
            // Small tracked mono caps carry themselves without help; this is
            // the treatment the panel eyebrows inside Home already use.
            Text(eyebrow)
                .font(ActionType.label)
                .tracking(ActionType.eyebrowTracking)
                .foregroundStyle(inkSecondary)
            Text(title)
                .font(ActionType.uiTitle)
                .tracking(ActionType.titleTracking)
                .foregroundStyle(ink)
            if let subtitle {
                Text(subtitle)
                    .font(ActionType.uiBody)
                    .foregroundStyle(inkMuted)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Segmented control

/// A segmented picker in the app's own colours.
///
/// SwiftUI's `.pickerStyle(.segmented)` paints its selected segment in the
/// macOS *system* accent — the blue in System Settings, or whatever the
/// operator has chosen there. On a paper-and-graphite surface that is the one
/// colour on screen the theme did not pick, and it lands on the Appearance
/// page, which is precisely where the app is claiming to control how it looks.
///
/// Same geometry as the Library's layout toggle, so the app has one segmented
/// shape rather than two.
struct ActionSegmentedControl<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(ActionType.uiCaption)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(
                            selected ? StageHUDTheme.textPrimary : StageHUDTheme.textMuted
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? StageHUDTheme.buttonSecondaryHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(StageHUDTheme.buttonSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Empty state

/// The one shape a page wears when it has nothing to show.
///
/// There were three: Scenarios, Library, and Library's no-results, each a
/// full-width card pinned to the top of the page with its own spacing and its
/// own idea of how much padding an empty page deserves. On a tall window that
/// put a small box at the top and six hundred points of nothing under it, which
/// reads as a page that failed to load rather than a page with nothing in it.
///
/// Centred in whatever space it is given, in a column narrow enough to read as
/// a deliberate composition. No card: a box floating in the middle of an empty
/// canvas is more chrome than the situation calls for.
struct ActionEmptyState<Content: View>: View {
    let icon: String
    let title: String
    let message: String
    /// Extra controls — a field to fill in, a second choice — under the message.
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Small, not a 22pt watermark. An oversized soft glyph is the
            // house style of an empty state that has nothing to say; at row
            // size it reads as the mark for this kind of thing and lets the
            // title be the largest object.
            Image(systemName: icon)
                .font(ActionIcon.medium)
                .foregroundStyle(StageHUDTheme.textMuted)

            Text(title)
                .font(ActionType.uiTitle)
                .tracking(ActionType.titleTracking)
                .foregroundStyle(StageHUDTheme.textPrimary)

            Text(message)
                .font(ActionType.uiRow)
                .foregroundStyle(StageHUDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .frame(maxWidth: 420, alignment: .leading)
        // On the content margin and near the top, on the same vertical as the
        // page heading above it. Centring it — horizontally or vertically — gave
        // the page a second alignment logic competing with the header's, and a
        // block that moved every time the window was resized.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

extension ActionEmptyState where Content == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message, content: { EmptyView() })
    }
}
