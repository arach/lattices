import DeckKit
import SwiftUI

struct CompanionCockpitEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var prefs: Preferences
    var showsCloseButton: Bool = false

    @State private var selectedPageID = Self.defaultPageID
    @State private var trustRevision = 0

    private static let defaultPageID = LatticesCompanionCockpitCatalog.defaultLayout.pages.first?.id ?? ""

    private var layout: LatticesCompanionCockpitLayout {
        LatticesCompanionCockpitCatalog.normalized(prefs.companionCockpitLayout)
    }

    private var pageSelection: Binding<String> {
        Binding(
            get: { effectivePageID },
            set: { selectedPageID = $0 }
        )
    }

    private var effectivePageID: String {
        if layout.pages.contains(where: { $0.id == selectedPageID }) {
            return selectedPageID
        }
        return layout.pages.first?.id ?? Self.defaultPageID
    }

    private var selectedPage: LatticesCompanionCockpitLayout.Page? {
        layout.pages.first(where: { $0.id == effectivePageID }) ?? layout.pages.first
    }

    private var trustedDevices: [DeckTrustedDeviceSummary] {
        _ = trustRevision
        return LatticesCompanionSecurityCoordinator.shared.trustedDeviceSummaries()
    }

    private var pageCountLabel: String {
        "\(layout.pages.count) page\(layout.pages.count == 1 ? "" : "s")"
    }

    private var trustedDeviceLabel: String {
        "\(trustedDevices.count) trusted device\(trustedDevices.count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsCloseButton {
                topBar
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overviewCard
                    bridgeCard
                    pageEditorCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(minWidth: 820, minHeight: 680)
        .background(PanelBackground())
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMPANION")
                        .font(Typo.pixel(14))
                        .foregroundColor(Palette.textDim)
                        .tracking(1)

                    Text("Cockpit Editor")
                        .font(Typo.heading(14))
                        .foregroundColor(Palette.text)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
        }
    }

    private var overviewCard: some View {
        CompanionCockpitCard(
            title: "Companion Cockpit",
            eyebrow: "iPad & iPhone",
            summary: "Author the remote command deck in its own surface so desktop shortcut editing and companion layout design can evolve independently."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Design the companion deck here, separate from desktop shortcut preferences, so the remote controls can grow into their own focused surface.")
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    CompanionCockpitSummaryPill(
                        icon: "rectangle.grid.2x2",
                        label: "Pages",
                        value: pageCountLabel
                    )

                    CompanionCockpitSummaryPill(
                        icon: prefs.companionTrackpadEnabled ? "cursorarrow.motionlines" : "cursorarrow.slash",
                        label: "Trackpad",
                        value: prefs.companionTrackpadEnabled ? "Enabled" : "Off"
                    )

                    CompanionCockpitSummaryPill(
                        icon: "ipad.and.iphone",
                        label: "Bridge",
                        value: trustedDeviceLabel
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Pages")
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.text)

                    HStack(spacing: 8) {
                        ForEach(layout.pages) { page in
                            CompanionCockpitPageChip(title: page.title)
                        }
                    }
                }
            }
        }
    }

    private var bridgeCard: some View {
        CompanionCockpitCard(
            title: "Bridge & Trust",
            eyebrow: "Companion Link",
            summary: "Remote trackpad control and encrypted bridge trust stay together so device approval state is easy to inspect."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Remote Trackpad")
                            .font(Typo.monoBold(11))
                            .foregroundColor(Palette.text)

                        Text("Enable remote pointer control for the iPad trackpad surface. Accessibility permission is still required on the Mac.")
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Toggle("", isOn: $prefs.companionTrackpadEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trusted Devices")
                                .font(Typo.monoBold(11))
                                .foregroundColor(Palette.text)

                            Text("New companions must be approved on the Mac before they can send encrypted bridge requests.")
                                .font(Typo.caption(10.5))
                                .foregroundColor(Palette.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if trustedDevices.isEmpty == false {
                            Button("Forget All") {
                                LatticesCompanionSecurityCoordinator.shared.clearTrustedDevices()
                                trustRevision += 1
                            }
                            .buttonStyle(.plain)
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textDim)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if trustedDevices.isEmpty {
                            Text("No paired iPad or iPhone devices yet.")
                                .font(Typo.caption(10.5))
                                .foregroundColor(Palette.textMuted)
                        } else {
                            ForEach(trustedDevices) { device in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "ipad.and.iphone")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Palette.textDim)
                                        .frame(width: 14)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(Typo.caption(11))
                                            .foregroundColor(Palette.text)

                                        Text("\(device.fingerprint) - Last seen \(relativeTimestamp(device.lastSeenAt))")
                                            .font(Typo.caption(10))
                                            .foregroundColor(Palette.textMuted)
                                    }

                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(CompanionCockpitInsetPanel())
                }
            }
        }
    }

    private var pageEditorCard: some View {
        CompanionCockpitCard(
            title: "Page Layout",
            eyebrow: "Command Deck",
            summary: "Pick a page, then remap each slot to a shortcut definition from the catalog below."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Companion page", selection: pageSelection) {
                    ForEach(layout.pages) { page in
                        Text(page.title).tag(page.id)
                    }
                }
                .pickerStyle(.segmented)

                if let selectedPage {
                    VStack(alignment: .leading, spacing: 8) {
                        if let subtitle = selectedPage.subtitle, subtitle.isEmpty == false {
                            Text(subtitle)
                                .font(Typo.caption(10.5))
                                .foregroundColor(Palette.textMuted)
                        }

                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(minimum: 120, maximum: 220), spacing: 8, alignment: .top),
                                count: max(2, selectedPage.columns)
                            ),
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(Array(selectedPage.slotIDs.enumerated()), id: \.offset) { index, shortcutID in
                                CompanionCockpitSlotMenu(
                                    prefs: prefs,
                                    pageID: selectedPage.id,
                                    index: index,
                                    shortcutID: shortcutID
                                )
                            }
                        }
                    }
                    .padding(12)
                    .background(CompanionCockpitInsetPanel())
                }

                HStack(spacing: 10) {
                    Text("Changes appear in the iPad companion on the next snapshot refresh.")
                        .font(Typo.caption(10.5))
                        .foregroundColor(Palette.textMuted)

                    Spacer()

                    Button("Reset Companion Layout") {
                        prefs.resetCompanionCockpitLayout()
                    }
                    .buttonStyle(.plain)
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.textDim)
                }
            }
        }
    }

    private func relativeTimestamp(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

struct CompanionCockpitSettingsEntryContent: View {
    @ObservedObject var prefs: Preferences
    var onOpenEditor: () -> Void

    private var layout: LatticesCompanionCockpitLayout {
        LatticesCompanionCockpitCatalog.normalized(prefs.companionCockpitLayout)
    }

    private var trustedDeviceCount: Int {
        LatticesCompanionSecurityCoordinator.shared.trustedDeviceSummaries().count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Companion authoring now opens in a dedicated cockpit editor, so this shortcuts tab can stay focused on desktop hotkeys and tmux references.")
                .font(Typo.caption(10.5))
                .foregroundColor(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                CompanionCockpitSummaryPill(
                    icon: "rectangle.grid.2x2",
                    label: "Pages",
                    value: "\(layout.pages.count)"
                )

                CompanionCockpitSummaryPill(
                    icon: prefs.companionTrackpadEnabled ? "cursorarrow.motionlines" : "cursorarrow.slash",
                    label: "Trackpad",
                    value: prefs.companionTrackpadEnabled ? "Enabled" : "Off"
                )

                CompanionCockpitSummaryPill(
                    icon: "ipad.and.iphone",
                    label: "Trusted",
                    value: "\(trustedDeviceCount)"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current Pages")
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)

                HStack(spacing: 8) {
                    ForEach(layout.pages) { page in
                        CompanionCockpitPageChip(title: page.title)
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Open the dedicated cockpit editor to manage deck pages, trusted devices, and remote trackpad controls.")
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button("Open Cockpit Editor") {
                    onOpenEditor()
                }
                .buttonStyle(.plain)
                .font(Typo.caption(10.5))
                .foregroundColor(Palette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
            }
        }
    }
}

private struct CompanionCockpitCard<Content: View>: View {
    let title: String
    let eyebrow: String
    let summary: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(Typo.pixel(12))
                    .foregroundColor(Palette.textDim)
                    .tracking(1)

                Text(title)
                    .font(Typo.monoBold(12))
                    .foregroundColor(Palette.text)

                Text(summary)
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass()
    }
}

private struct CompanionCockpitSummaryPill: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.textDim)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(Typo.pixel(10))
                    .foregroundColor(Palette.textDim)

                Text(value)
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.text)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CompanionCockpitInsetPanel())
    }
}

private struct CompanionCockpitPageChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typo.caption(10.5))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CompanionCockpitInsetPanel())
    }
}

private struct CompanionCockpitInsetPanel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
    }
}

private struct CompanionCockpitSlotMenu: View {
    @ObservedObject var prefs: Preferences

    let pageID: String
    let index: Int
    let shortcutID: String

    private let categories = LatticesCompanionShortcutCategory.allCases

    private var definition: LatticesCompanionShortcutDefinition? {
        LatticesCompanionCockpitCatalog.definition(for: shortcutID)
    }

    var body: some View {
        Menu {
            Button("Empty Slot") {
                prefs.updateCompanionCockpitSlot(pageID: pageID, index: index, shortcutID: "")
            }

            ForEach(categories) { category in
                let shortcuts = LatticesCompanionCockpitCatalog.shortcuts.filter {
                    $0.category == category && $0.id.isEmpty == false
                }

                if shortcuts.isEmpty == false {
                    Section(category.title) {
                        ForEach(shortcuts) { shortcut in
                            Button {
                                prefs.updateCompanionCockpitSlot(
                                    pageID: pageID,
                                    index: index,
                                    shortcutID: shortcut.id
                                )
                            } label: {
                                Label(shortcut.title, systemImage: shortcut.iconSystemName)
                            }
                        }
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("Slot \(index + 1)")
                        .font(Typo.pixel(10))
                        .foregroundColor(Palette.textDim)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                }

                Image(systemName: definition?.iconSystemName ?? "square.dashed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textDim)

                Text(definition?.title ?? "Empty")
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(2)

                Text(definition?.subtitle ?? "Choose a shortcut")
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
