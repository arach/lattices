import AppKit
import HudsonUI
import SwiftUI

/// Blink's settings are a view over the agent-first config file. Every mutable
/// control round-trips through `BlinkConfigStore.update`; external edits remain
/// authoritative and repaint this surface through the observed store.
struct SettingsView: View {
    @ObservedObject var store: BlinkConfigStore
    let notesDirectory: URL

    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: SettingsSection = .general

    private var settingsTheme: HudTheme {
        switch store.config.appearance.lowercased() {
        case "light": return .lightDraft
        case "dark": return .default
        default: return colorScheme == .light ? .lightDraft : .default
        }
    }

    private var tildePath: String {
        notesDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var restoreSession: Binding<Bool> {
        Binding(
            get: { store.config.behavior.restoreSession },
            set: { value in store.update { $0.behavior.restoreSession = value } }
        )
    }

    private var defaultMode: Binding<String> {
        Binding(
            get: { store.config.behavior.defaultMode },
            set: { value in store.update { $0.behavior.defaultMode = value } }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { store.config.behavior.launchAtLogin },
            set: { value in store.update { $0.behavior.launchAtLogin = value } }
        )
    }

    private var defaultSheet: Binding<String> {
        Binding(
            get: { store.config.panel.sheet },
            set: { value in store.update { $0.panel.sheet = value } }
        )
    }

    private var panelShadow: Binding<Bool> {
        Binding(
            get: { store.config.panel.shadow },
            set: { value in store.update { $0.panel.shadow = value } }
        )
    }

    private var panelSize: Binding<PanelSizePreset> {
        Binding(
            get: {
                PanelSizePreset.matching(
                    width: store.config.panel.defaultWidth,
                    height: store.config.panel.defaultHeight
                )
            },
            set: { preset in
                guard let size = preset.size else { return }
                store.update {
                    $0.panel.defaultWidth = size.width
                    $0.panel.defaultHeight = size.height
                }
            }
        )
    }

    private var appearance: Binding<String> {
        Binding(
            get: {
                let value = store.config.appearance.lowercased()
                return ["auto", "light", "dark"].contains(value) ? value : "auto"
            },
            set: { value in store.update { $0.appearance = value } }
        )
    }

    private var backgroundLevel: Binding<BackgroundLevel> {
        Binding(
            get: {
                guard store.config.drape.enabled else { return .off }
                return store.config.drape.opacity <= 0.7 ? .light : .full
            },
            set: { level in
                store.update {
                    switch level {
                    case .off:
                        $0.drape.enabled = false
                    case .light:
                        $0.drape.enabled = true
                        $0.drape.opacity = 0.4
                    case .full:
                        $0.drape.enabled = true
                        $0.drape.opacity = 1
                    }
                }
            }
        )
    }

    private var suppressSoloDrape: Binding<Bool> {
        Binding(
            get: { store.config.drape.soloSuppressed },
            set: { value in store.update { $0.drape.soloSuppressed = value } }
        )
    }

    private var focusDim: Binding<Double> {
        Binding(
            get: { store.config.focus.dim },
            set: { value in store.update { $0.focus.dim = value } }
        )
    }

    private var motionEnabled: Binding<Bool> {
        Binding(
            get: { store.config.motion.enabled },
            set: { value in store.update { $0.motion.enabled = value } }
        )
    }

    private var entrance: Binding<String> {
        Binding(
            get: { store.config.motion.entrance },
            set: { value in store.update { $0.motion.entrance = value } }
        )
    }

    private var flingEnabled: Binding<Bool> {
        Binding(
            get: { store.config.physics.flingEnabled },
            set: { value in store.update { $0.physics.flingEnabled = value } }
        )
    }

    private var shakeEnabled: Binding<Bool> {
        Binding(
            get: { store.config.physics.shakeEnabled },
            set: { value in store.update { $0.physics.shakeEnabled = value } }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(settingsTheme.hairline.standard)
                .frame(width: HudStrokeWidth.thin)
                .accessibilityHidden(true)

            content
        }
        .frame(
            minWidth: HudLayout.dialogWidth + HudLayout.rowHeightRegular,
            idealWidth: HudLayout.readableWidth + HudSpacing.xxxl,
            minHeight: HudLayout.dialogWidth - HudSpacing.xxxl,
            idealHeight: HudLayout.readableWidth - HudSpacing.huge
        )
        .background(settingsTheme.palette.bg)
        .hudTheme(settingsTheme)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: HudSpacing.xl) {
            Text("Settings")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(settingsTheme.palette.ink)
                .padding(.horizontal, HudSpacing.xxl)
                .padding(.top, HudSpacing.xxxl)

            VStack(spacing: HudSpacing.xs) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: HudSpacing.lg) {
                            Image(systemName: section.icon)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: HudIconSize.small, height: HudIconSize.small)

                            Text(section.title)
                                .font(.system(size: 13, weight: .medium))

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(
                            selection == section
                                ? settingsTheme.palette.ink
                                : settingsTheme.palette.muted
                        )
                        .padding(.horizontal, HudSpacing.xl)
                        .frame(height: HudLayout.rowHeightCompact)
                        .background(
                            RoundedRectangle(cornerRadius: settingsTheme.radius.standard)
                                .fill(
                                    selection == section
                                        ? settingsTheme.palette.accentSoft
                                        : Color.clear
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(section.title) settings")
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, HudSpacing.md)

            Spacer(minLength: HudSpacing.xxxl)

            HStack(alignment: .top, spacing: HudSpacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.top, HudSpacing.xxs)

                Text("Changes sync with config.json")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(settingsTheme.palette.dim)
            .padding(.horizontal, HudSpacing.xxl)
            .padding(.bottom, HudSpacing.xxl)
        }
        .frame(width: HudLayout.popoverWidthCompact / 2)
        .background(settingsTheme.palette.chrome)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HudSpacing.xs) {
                Text(selection.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(settingsTheme.palette.ink)

                Text(selection.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(settingsTheme.palette.muted)
            }
            .padding(.horizontal, HudSpacing.huge)
            .padding(.top, HudSpacing.xxxl)
            .padding(.bottom, HudSpacing.xxl)

            ScrollView {
                selectedPage
                    .frame(maxWidth: HudLayout.readableWidth, alignment: .leading)
                    .padding(.horizontal, HudSpacing.huge)
                    .padding(.bottom, HudSpacing.huge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selection {
        case .general: generalPage
        case .notes: notesPage
        case .desktop: desktopPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: HudSpacing.xl) {
            HudSettingsSection("Files", labelTint: settingsTheme.palette.muted) {
                HudSettingsRow(
                    icon: "folder",
                    title: "Notes folder",
                    subtitle: tildePath,
                    badge: {
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([notesDirectory])
                        }
                        .controlSize(.small)
                        .accessibilityHint("Shows the Blink notes folder in Finder")
                    }
                )
                SettingsDivider()
                HudSettingsRow(
                    icon: "curlybraces",
                    title: "Config file",
                    subtitle: store.displayPath,
                    badge: {
                        Button("Open") { openConfig() }
                            .controlSize(.small)
                            .accessibilityHint("Opens Blink's JSON configuration file")
                    }
                )
            }

            HudSettingsSection("Startup", labelTint: settingsTheme.palette.muted) {
                HudSettingsControlRow(
                    title: "Restore panels at launch",
                    subtitle: "Reopen notes where you left them",
                    icon: "macwindow.on.rectangle"
                ) {
                    Toggle("Restore panels at launch", isOn: restoreSession)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Restore panels at launch")
                }
                SettingsDivider()
                HudSettingsControlRow(
                    title: "Launch at login",
                    subtitle: "Start Blink when you sign in",
                    icon: "power"
                ) {
                    Toggle("Launch at login", isOn: launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Launch Blink at login")
                }
            }
        }
    }

    private var notesPage: some View {
        VStack(alignment: .leading, spacing: HudSpacing.xl) {
            HudSettingsSection("Defaults", labelTint: settingsTheme.palette.muted) {
                HudSettingsControlRow(
                    title: "Open notes in",
                    subtitle: "New notes can open ready to read or write",
                    icon: "book"
                ) {
                    Picker("Open notes in", selection: defaultMode) {
                        Text("Read").tag("read")
                        Text("Edit").tag("edit")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: HudLayout.popoverWidthCompact / 2.6)
                    .accessibilityLabel("Default note mode")
                }
                SettingsDivider()
                HudSettingsPickerRow(
                    title: "Default sheet",
                    subtitle: "The starting look for notes without an override",
                    icon: "rectangle.on.rectangle",
                    selection: defaultSheet
                ) {
                    Text("Glass").tag("glass")
                    Text("Card").tag("card")
                    Text("Dotted").tag("dotted")
                    Text("Bracket").tag("bracket")
                    Text("Marginalia").tag("marginalia")
                }
                SettingsDivider()
                HudSettingsControlRow(
                    title: "Default panel size",
                    subtitle: panelSize.wrappedValue.description,
                    icon: "arrow.up.left.and.arrow.down.right"
                ) {
                    Picker("Default panel size", selection: panelSize) {
                        Text("Compact").tag(PanelSizePreset.compact)
                        Text("Standard").tag(PanelSizePreset.standard)
                        Text("Large").tag(PanelSizePreset.large)
                        if panelSize.wrappedValue == .custom {
                            Text("Custom").tag(PanelSizePreset.custom)
                        }
                    }
                    .labelsHidden()
                    .frame(width: HudLayout.popoverWidthCompact / 2)
                    .accessibilityLabel("Default panel size")
                }
                SettingsDivider()
                HudSettingsControlRow(
                    title: "Panel shadow",
                    subtitle: "Add depth to glass and card sheets",
                    icon: "square.3.layers.3d.down.right"
                ) {
                    Toggle("Panel shadow", isOn: panelShadow)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Show panel shadows")
                }
            }

            HudSettingsSection("Advanced", labelTint: settingsTheme.palette.muted) {
                HudSettingsRow(
                    icon: "paintpalette",
                    title: "Appearance, typography, styles & workspaces",
                    subtitle: "Tune fonts, colors, glass, spacing and named styles in config.json",
                    onTap: openConfig
                )
                .accessibilityHint("Opens Blink's JSON configuration file")
            }
        }
    }

    private var desktopPage: some View {
        VStack(alignment: .leading, spacing: HudSpacing.xl) {
            HudSettingsSection("Appearance", labelTint: settingsTheme.palette.muted) {
                HudSettingsControlRow(
                    title: "Appearance",
                    subtitle: "Utilities only; notes may differ",
                    icon: "circle.lefthalf.filled"
                ) {
                    Picker("Appearance", selection: appearance) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: HudLayout.popoverWidthCompact / 2)
                    .accessibilityLabel("Blink appearance")
                }
                SettingsDivider()
                HudSettingsControlRow(
                    title: "Desktop background",
                    subtitle: "A calm stage behind a set of notes",
                    icon: "rectangle.inset.filled"
                ) {
                    Picker("Desktop background", selection: backgroundLevel) {
                        ForEach(BackgroundLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: HudLayout.popoverWidthCompact / 2)
                    .accessibilityLabel("Desktop background strength")
                }
                SettingsDivider()
                HudSettingsControlRow(
                    title: "Keep one note clear",
                    subtitle: "Show the background only when notes form a set",
                    icon: "rectangle.on.rectangle.slash"
                ) {
                    Toggle("Keep one note clear", isOn: suppressSoloDrape)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .disabled(!store.config.drape.enabled)
                        .accessibilityLabel("Keep the desktop clear behind a single note")
                }
                SettingsDivider()
                HudSettingsControlRow(
                    title: "Focus dimming",
                    subtitle: "Quiet the desktop around the focused note",
                    value: "\(Int(store.config.focus.dim * 100))%",
                    icon: "circle.dashed"
                ) {
                    Slider(value: focusDim, in: 0...0.8, step: 0.05)
                        .frame(width: HudLayout.popoverWidthCompact / 2)
                        .accessibilityLabel("Focus dimming")
                        .accessibilityValue("\(Int(store.config.focus.dim * 100)) percent")
                }
            }

            HudSettingsSection("Motion & Gestures", labelTint: settingsTheme.palette.muted) {
                HudSettingsControlRow(
                    title: "Panel motion",
                    subtitle: "Animate notes as they appear and recede",
                    icon: "sparkles"
                ) {
                    Toggle("Panel motion", isOn: motionEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Animate panels")
                }
                SettingsDivider()
                HudSettingsPickerRow(
                    title: "Entrance effect",
                    subtitle: "Reduce Motion in macOS always takes precedence",
                    icon: "wand.and.stars",
                    selection: entrance
                ) {
                    Text("Shimmer").tag("shimmer")
                    Text("Drop").tag("drop")
                    Text("Draw").tag("draw")
                    Text("None").tag("none")
                }
                .disabled(!store.config.motion.enabled)
                SettingsDivider()
                HudSettingsControlRow(
                    title: "Fling panels",
                    subtitle: "Release a quick drag to glide and bounce",
                    icon: "hand.draw"
                ) {
                    Toggle("Fling panels", isOn: flingEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Fling panels after a quick drag")
                }
                SettingsDivider()
                HudSettingsControlRow(
                    title: "Shake to shade",
                    subtitle: "Shake a panel sideways to fold its content",
                    icon: "arrow.left.and.right"
                ) {
                    Toggle("Shake to shade", isOn: shakeEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Shake panels to shade them")
                }
            }
        }
    }

    private func openConfig() {
        NSWorkspace.shared.open(store.fileURL)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case notes
    case desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .notes: "Notes"
        case .desktop: "Desktop"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Files, startup and session behavior"
        case .notes: "How new notes look and open"
        case .desktop: "Appearance, focus, movement and gestures"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .notes: "note.text"
        case .desktop: "display"
        }
    }
}

private enum BackgroundLevel: String, CaseIterable, Identifiable {
    case off
    case light
    case full

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private enum PanelSizePreset: String, Hashable {
    case compact
    case standard
    case large
    case custom

    var size: (width: Double, height: Double)? {
        switch self {
        case .compact: (360, 280)
        case .standard: (420, 340)
        case .large: (520, 420)
        case .custom: nil
        }
    }

    var description: String {
        guard let size else { return "Custom size from config.json" }
        return "\(Int(size.width)) × \(Int(size.height)) points"
    }

    static func matching(width: Double, height: Double) -> PanelSizePreset {
        for preset in [PanelSizePreset.compact, .standard, .large] {
            guard let size = preset.size else { continue }
            if abs(width - size.width) < 0.5, abs(height - size.height) < 0.5 {
                return preset
            }
        }
        return .custom
    }
}

private struct SettingsDivider: View {
    @Environment(\.hudTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.hairline.subtle)
            .frame(height: HudStrokeWidth.thin)
            .padding(.leading, HudIconSize.medium + HudSpacing.xl + HudSpacing.md)
            .accessibilityHidden(true)
    }
}
