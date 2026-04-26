import DeckKit
import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var store = DeckStore()

    var body: some View {
        NavigationStack {
            ZStack {
                companionBackground
                    .ignoresSafeArea()

                if let manifest = store.manifest,
                   let snapshot = store.snapshot,
                   let endpoint = store.activeEndpoint {
                    deckShell(manifest: manifest, snapshot: snapshot, endpoint: endpoint)
                } else {
                    connectionView
                }
            }
            .navigationTitle("Lattices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if store.activeEndpoint != nil {
                        Button {
                            store.refreshSnapshot()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}

private extension ContentView {
    var companionBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.11, blue: 0.17),
                    Color(red: 0.08, green: 0.18, blue: 0.24),
                    Color(red: 0.03, green: 0.07, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: 140, y: -220)

            Circle()
                .fill(Color.mint.opacity(0.11))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -180, y: 260)
        }
    }

    var connectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                connectionHero
                discoveryCard
                manualConnectionCard

                if let message = store.errorMessage {
                    statusCard(
                        title: "Connection Issue",
                        detail: message,
                        tint: Color.red.opacity(0.18),
                        stroke: Color.red.opacity(0.28)
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
        }
    }

    var connectionHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mac Command Deck")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Discover the running Lattices menu bar app on your local network, then control voice, layout, switching, and history from iPhone or iPad.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(deckCardBackground(stroke: Color.white.opacity(0.12)))
    }

    var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Nearby Macs")
                Spacer()
                Button("Refresh") {
                    store.refreshDiscovery()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan.opacity(0.75))
            }

            if store.discoveredBridges.isEmpty {
                Text("No Lattices companion bridge has been discovered yet. Make sure the macOS menu bar app is running on the same local network.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.discoveredBridges) { bridge in
                        Button {
                            store.connect(to: bridge)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.cyan.opacity(0.18))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: "macwindow.and.iphone")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bridge.name)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("\(bridge.host):\(bridge.port) • \(bridge.source)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(0.68))
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(Color.white.opacity(0.52))
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(deckInsetBackground(stroke: Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(deckCardBackground(stroke: Color.white.opacity(0.1)))
    }

    var manualConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Manual Connection")

            Text("Use this if Bonjour discovery is blocked. A common host format is `air.local` or your Mac’s local network name.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                TextField("Mac host", text: $store.manualHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(deckInsetBackground(stroke: Color.white.opacity(0.08)))

                TextField("Port", text: $store.manualPort)
                    .keyboardType(.numberPad)
                    .padding(12)
                    .background(deckInsetBackground(stroke: Color.white.opacity(0.08)))
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white)

            Button {
                store.connectManually()
            } label: {
                HStack {
                    Spacer()
                    Text("Connect")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint.opacity(0.8))
        }
        .padding(20)
        .background(deckCardBackground(stroke: Color.white.opacity(0.1)))
    }

    func deckShell(
        manifest: DeckManifest,
        snapshot: DeckRuntimeSnapshot,
        endpoint: BridgeEndpoint
    ) -> some View {
        VStack(spacing: 16) {
            deckStatusHeader(endpoint: endpoint)

            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    pageRail(pages: manifest.pages)
                        .frame(width: 220)

                    pageDetail(manifest: manifest, snapshot: snapshot)
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 14) {
                    pageStrip(pages: manifest.pages)
                    pageDetail(manifest: manifest, snapshot: snapshot)
                }
            }
        }
        .padding(18)
    }

    func deckStatusHeader(endpoint: BridgeEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected to \(endpoint.name)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("\(endpoint.host):\(endpoint.port) • \(store.health?.mode ?? "bridge")")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                }

                Spacer()

                Button("Change Mac") {
                    store.disconnect()
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.7))
            }

            if store.isPerformingAction, let label = store.lastActionLabel {
                statusCard(
                    title: "Running \(label)",
                    detail: "Sending the action to your Mac companion bridge.",
                    tint: Color.cyan.opacity(0.16),
                    stroke: Color.cyan.opacity(0.28)
                )
            } else if let result = store.lastActionResult {
                statusCard(
                    title: result.summary,
                    detail: result.detail ?? "The Mac deck action completed successfully.",
                    tint: result.ok ? Color.mint.opacity(0.18) : Color.red.opacity(0.18),
                    stroke: result.ok ? Color.mint.opacity(0.26) : Color.red.opacity(0.26)
                )
            } else if let error = store.errorMessage {
                statusCard(
                    title: "Bridge Error",
                    detail: store.lastActionLabel.map { "\($0): \(error)" } ?? error,
                    tint: Color.red.opacity(0.18),
                    stroke: Color.red.opacity(0.28)
                )
            }
        }
    }

    func pageRail(pages: [DeckPage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Pages")

            ForEach(pages) { page in
                Button {
                    store.selectedPageID = page.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.iconSystemName)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text(page.kind.rawValue.capitalized)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.62))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(page.id == store.selectedPageID ? accentColor(for: page).opacity(0.34) : Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(page.id == store.selectedPageID ? accentColor(for: page).opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(deckCardBackground(stroke: Color.white.opacity(0.1)))
    }

    func pageStrip(pages: [DeckPage]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pages) { page in
                    Button {
                        store.selectedPageID = page.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: page.iconSystemName)
                            Text(page.title)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(page.id == store.selectedPageID ? accentColor(for: page).opacity(0.34) : Color.white.opacity(0.08))
                                .overlay(
                                    Capsule()
                                        .stroke(page.id == store.selectedPageID ? accentColor(for: page).opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func pageDetail(manifest: DeckManifest, snapshot: DeckRuntimeSnapshot) -> some View {
        let activePage = manifest.pages.first(where: { $0.id == store.selectedPageID }) ?? manifest.pages.first

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let activePage {
                    pageTitle(page: activePage)

                    switch activePage.kind {
                    case .cockpit:
                        cockpitPage(snapshot: snapshot)
                    case .voice:
                        voicePage(snapshot: snapshot)
                    case .layout:
                        layoutPage(snapshot: snapshot)
                    case .switch:
                        switchPage(snapshot: snapshot)
                    case .history:
                        historyPage(snapshot: snapshot)
                    case .mac, .custom:
                        placeholderPage(title: activePage.title)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func pageTitle(page: DeckPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Shared deck surface powered by the running Lattices menu bar app.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    func cockpitPage(snapshot: DeckRuntimeSnapshot) -> some View {
        let cockpit = snapshot.cockpit
        let pages = cockpit?.pages ?? []
        let selectedCockpitPage = pages.first(where: { $0.id == store.selectedCockpitPageID }) ?? pages.first
        let trackpad = snapshot.trackpad

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                compactMetric(title: "Visible", value: "\(snapshot.desktop?.visibleWindowCount ?? 0)")
                compactMetric(title: "Sessions", value: "\(snapshot.desktop?.sessionCount ?? 0)")
                compactMetric(title: "Active App", value: snapshot.desktop?.activeAppName ?? "Mac")
            }

            if let cockpit {
                statusCard(
                    title: cockpit.title ?? "Command Deck",
                    detail: cockpit.detail ?? "Quick controls from your Mac-defined cockpit board.",
                    tint: Color.cyan.opacity(0.14),
                    stroke: Color.cyan.opacity(0.22)
                )
            }

            if let trackpad {
                CompanionTrackpadSurface(state: trackpad) { event, dx, dy in
                    store.sendTrackpad(event: event, dx: dx, dy: dy)
                }
                .padding(18)
                .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
            }

            if pages.count > 1 {
                cockpitPageStrip(pages: pages)
            }

            if let selectedCockpitPage {
                cockpitBoardCard(page: selectedCockpitPage)
            } else {
                infoCard(
                    title: "No Cockpit Layout",
                    detail: "Open Lattices on the Mac and configure the companion cockpit in Settings > Shortcuts."
                )
            }
        }
    }

    func voicePage(snapshot: DeckRuntimeSnapshot) -> some View {
        let voice = snapshot.voice
        let phase = voice?.phase.rawValue.capitalized ?? "Unknown"
        let examples = [
            "Optimize the layout",
            "Move this window left",
            "Focus Safari",
            "Switch to my review layer"
        ]

        return VStack(alignment: .leading, spacing: 16) {
            metricHero(title: phase, subtitle: voice?.provider?.uppercased() ?? "VOICE")

            actionRow(
                primaryTitle: voice?.phase == .listening ? "Stop Listening" : "Start Voice",
                primaryIcon: voice?.phase == .listening ? "stop.fill" : "mic.fill",
                primaryAction: { store.perform(actionID: "voice.toggle", pageID: "voice") },
                secondaryTitle: "Cancel",
                secondaryIcon: "xmark",
                secondaryAction: { store.perform(actionID: "voice.cancel", pageID: "voice") }
            )

            if let transcript = voice?.transcript, !transcript.isEmpty {
                infoCard(title: "Transcript", detail: transcript)
            }

            if let response = voice?.responseSummary, !response.isEmpty {
                infoCard(title: "Response", detail: response)
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Try Saying")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(examples, id: \.self) { example in
                        Text(example)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(deckInsetBackground(stroke: Color.white.opacity(0.08)))
                    }
                }
            }
            .padding(18)
            .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
        }
    }

    func layoutPage(snapshot: DeckRuntimeSnapshot) -> some View {
        let desktop = snapshot.desktop
        let layout = snapshot.layout
        let layoutTasks = snapshot.switcher?.items.filter { $0.kind == .task } ?? []
        let appItems = Array((snapshot.switcher?.items.filter { $0.kind == .application } ?? []).prefix(5))
        let windowItems = Array((snapshot.switcher?.items.filter { $0.kind == .window } ?? []).prefix(4))
        let placements: [(String, String, String)] = [
            ("Left", "left", "rectangle.leadinghalf.filled"),
            ("Right", "right", "rectangle.trailinghalf.filled"),
            ("Top Left", "top-left", "rectangle.inset.topleft.filled"),
            ("Top Right", "top-right", "rectangle.inset.topright.filled"),
            ("Bottom Left", "bottom-left", "rectangle.inset.bottomleft.filled"),
            ("Bottom Right", "bottom-right", "rectangle.inset.bottomright.filled"),
            ("Center", "center", "plus.rectangle.on.rectangle"),
            ("Maximize", "maximize", "macwindow")
        ]
        let precisionPlacements: [(String, String, String)] = [
            ("Left Third", "left-third", "rectangle.leadingthird.inset.filled"),
            ("Center Third", "center-third", "rectangle.center.inset.filled"),
            ("Right Third", "right-third", "rectangle.trailingthird.inset.filled"),
            ("Top Third", "top-third", "rectangle.topthird.inset.filled"),
            ("Middle Third", "middle-third", "rectangle.center.inset.filled"),
            ("Bottom Third", "bottom-third", "rectangle.bottomthird.inset.filled")
        ]

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                compactMetric(title: "Screens", value: "\(desktop?.screenCount ?? 0)")
                compactMetric(title: "Visible", value: "\(desktop?.visibleWindowCount ?? 0)")
                compactMetric(title: "Sessions", value: "\(desktop?.sessionCount ?? 0)")
            }

            if let focus = layout?.frontmostWindow {
                frontmostWindowCard(
                    focus: focus,
                    screenName: layout?.screenName
                )
            } else if let layer = desktop?.activeLayerName ?? desktop?.activeAppName {
                infoCard(title: "Active Focus", detail: layer)
            }

            actionRow(
                primaryTitle: "Optimize Layout",
                primaryIcon: "rectangle.3.group.fill",
                primaryAction: { store.perform(actionID: "layout.optimize", pageID: "layout") },
                secondaryTitle: "Center Window",
                secondaryIcon: "plus.rectangle.on.rectangle",
                secondaryAction: {
                    store.perform(
                        actionID: "layout.placeFrontmost",
                        pageID: "layout",
                        payload: ["placement": .string("center")]
                    )
                }
            )

            if let preview = layout?.preview, !preview.windows.isEmpty {
                layoutPreviewCard(preview: preview)
            }

            placementSection(title: "Quick Placements", placements: placements)
            placementSection(title: "Precision Layouts", placements: precisionPlacements)
            sizeAdjustmentSection()

            if !appItems.isEmpty {
                quickSwitchSection(title: "Apps", items: appItems)
            }

            if !windowItems.isEmpty {
                quickSwitchSection(title: "Windows", items: windowItems)
            }

            if !layoutTasks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Layers & Tasks")

                    ForEach(layoutTasks) { item in
                        switcherButton(item: item)
                    }
                }
                .padding(18)
                .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
            }
        }
    }

    func switchPage(snapshot: DeckRuntimeSnapshot) -> some View {
        let items = snapshot.switcher?.items ?? []
        let groups = Dictionary(grouping: items) { $0.kind }
        let orderedKinds: [DeckSwitcherItemKind] = [
            .application,
            .window,
            .task,
            .session
        ]

        return VStack(alignment: .leading, spacing: 16) {
            if let focus = snapshot.layout?.frontmostWindow {
                frontmostWindowCard(
                    focus: focus,
                    screenName: snapshot.layout?.screenName
                )
            }

            ForEach(orderedKinds, id: \.rawValue) { kind in
                if let entries = groups[kind], !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel(kind.rawValue.capitalized)

                        ForEach(entries) { item in
                            switcherButton(item: item)
                        }
                    }
                    .padding(18)
                    .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
                }
            }
        }
    }

    func historyPage(snapshot: DeckRuntimeSnapshot) -> some View {
        let entries = snapshot.history

        return VStack(alignment: .leading, spacing: 16) {
            if entries.isEmpty {
                infoCard(
                    title: "No Recent History",
                    detail: "Run a few deck actions on the Mac and the shared history feed will start filling in here."
                )
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)

                                if let detail = entry.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(0.72))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer()

                            if let undo = entry.undoActionID {
                                Button("Undo") {
                                    store.perform(actionID: undo, pageID: "history")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.mint.opacity(0.8))
                            }
                        }
                    }
                    .padding(18)
                    .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
                }
            }
        }
    }

    func placeholderPage(title: String) -> some View {
        infoCard(title: title, detail: "This deck page will be expanded as the shared contract grows.")
    }

    func frontmostWindowCard(
        focus: DeckLayoutFocusWindow,
        screenName: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.mint.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 5) {
                    sectionLabel("Frontmost Window")
                    Text(focus.appName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let title = focus.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }

            HStack(spacing: 10) {
                detailChip(
                    icon: "ruler",
                    text: "\(Int(focus.frame.w.rounded()))×\(Int(focus.frame.h.rounded()))"
                )

                if let placement = focus.placement {
                    detailChip(
                        icon: "square.split.2x2",
                        text: humanPlacementLabel(placement)
                    )
                }

                if let screenName, !screenName.isEmpty {
                    detailChip(icon: "display", text: screenName)
                }
            }
        }
        .padding(20)
        .background(deckCardBackground(stroke: Color.white.opacity(0.1)))
    }

    func layoutPreviewCard(preview: DeckLayoutPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Layout Preview")
                Spacer()
                Text("Tap a window to focus it")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.66))
            }

            GeometryReader { geometry in
                let fullSize = geometry.size
                let canvas = CGSize(
                    width: max(fullSize.width - 24, 10),
                    height: max(fullSize.height - 24, 10)
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    ForEach(preview.windows) { window in
                        let frame = previewFrame(window.normalizedFrame, in: canvas)
                        Button {
                            store.perform(
                                actionID: "switch.focusItem",
                                pageID: "layout",
                                payload: ["itemID": .string(window.itemID)]
                            )
                        } label: {
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        window.isFrontmost
                                        ? LinearGradient(
                                            colors: [Color.cyan.opacity(0.72), Color.mint.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                window.isFrontmost
                                                ? Color.white.opacity(0.55)
                                                : Color.white.opacity(0.12),
                                                lineWidth: 1
                                            )
                                    )

                                if frame.width > 96, frame.height > 54 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(window.subtitle ?? window.title)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.76))
                                            .lineLimit(1)

                                        Text(window.title)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                    }
                                    .padding(10)
                                }
                            }
                            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                        }
                        .buttonStyle(.plain)
                        .offset(x: frame.minX + 12, y: frame.minY + 12)
                    }
                }
            }
            .aspectRatio(max(preview.aspectRatio, 1.0), contentMode: .fit)
        }
        .padding(18)
        .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
    }

    func placementSection(
        title: String,
        placements: [(String, String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(title)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(placements, id: \.1) { placement in
                    Button {
                        store.perform(
                            actionID: "layout.placeFrontmost",
                            pageID: "layout",
                            payload: ["placement": .string(placement.1)]
                        )
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: placement.2)
                            Text(placement.0)
                            Spacer()
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(deckInsetBackground(stroke: Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
    }

    func sizeAdjustmentSection() -> some View {
        let adjustments: [(String, String, String, String)] = [
            ("Wider", "width", "grow", "arrow.left.and.right"),
            ("Narrower", "width", "shrink", "arrow.left.and.right"),
            ("Taller", "height", "grow", "arrow.up.and.down"),
            ("Shorter", "height", "shrink", "arrow.up.and.down"),
            ("Grow", "both", "grow", "plus.rectangle.on.rectangle"),
            ("Shrink", "both", "shrink", "minus.rectangle")
        ]

        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Size Controls")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(adjustments, id: \.0) { adjustment in
                    Button {
                        store.perform(
                            actionID: "layout.resizeFrontmost",
                            pageID: "layout",
                            payload: [
                                "dimension": .string(adjustment.1),
                                "direction": .string(adjustment.2)
                            ]
                        )
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: adjustment.3)
                            Text(adjustment.0)
                            Spacer()
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(deckInsetBackground(stroke: Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
    }

    func quickSwitchSection(
        title: String,
        items: [DeckSwitcherItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(title)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            store.perform(
                                actionID: "switch.focusItem",
                                pageID: "layout",
                                payload: ["itemID": .string(item.id)]
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: icon(for: item))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)

                                Text(item.title)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                if let subtitle = item.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(0.68))
                                        .lineLimit(2)
                                }
                            }
                            .padding(14)
                            .frame(width: 180, alignment: .leading)
                            .background(
                                deckInsetBackground(
                                    stroke: item.isFrontmost
                                    ? Color.cyan.opacity(0.28)
                                    : Color.white.opacity(0.08)
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
    }

    func cockpitPageStrip(pages: [DeckCockpitPage]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pages) { page in
                    Button {
                        store.selectedCockpitPageID = page.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(page.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            if let subtitle = page.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.64))
                                    .lineLimit(2)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(page.id == store.selectedCockpitPageID ? Color.cyan.opacity(0.3) : Color.white.opacity(0.08))
                                .overlay(
                                    Capsule()
                                        .stroke(page.id == store.selectedCockpitPageID ? Color.cyan.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func cockpitBoardCard(page: DeckCockpitPage) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 130, maximum: .infinity), spacing: 10, alignment: .top),
            count: max(2, min(page.columns, horizontalSizeClass == .regular ? 4 : 2))
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel(page.title)
                    if let subtitle = page.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                Spacer()
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(page.tiles) { tile in
                    cockpitTileButton(tile: tile)
                }
            }
        }
        .padding(18)
        .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
    }

    func cockpitTileButton(tile: DeckCockpitTile) -> some View {
        let tint = accentColor(for: tile.accentToken)
        let isEnabled = tile.isEnabled && tile.actionID != nil

        return Button {
            guard let actionID = tile.actionID else { return }
            store.perform(
                actionID: actionID,
                pageID: "cockpit",
                payload: tile.payload,
                label: tile.title
            )
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: tile.iconSystemName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    if tile.isActive {
                        Text("Live")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                }

                Text(tile.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let subtitle = tile.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isEnabled ? tint.opacity(tile.isActive ? 0.34 : 0.22) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isEnabled ? tint.opacity(tile.isActive ? 0.5 : 0.3) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? 1 : 0.65)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    func switcherButton(item: DeckSwitcherItem) -> some View {
        Button {
            store.perform(
                actionID: "switch.focusItem",
                pageID: "switch",
                payload: ["itemID": .string(item.id)]
            )
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(item.isFrontmost ? Color.cyan.opacity(0.22) : Color.white.opacity(0.08))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon(for: item))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.68))
                    }
                }

                Spacer()

                if item.isFrontmost {
                    Text("Live")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.cyan.opacity(0.28)))
                }
            }
            .padding(14)
            .background(deckInsetBackground(stroke: item.isFrontmost ? Color.cyan.opacity(0.25) : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    func metricHero(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subtitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .tracking(1.4)

            Text(title)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(deckCardBackground(stroke: Color.white.opacity(0.12)))
    }

    func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
    }

    func actionRow(
        primaryTitle: String,
        primaryIcon: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryIcon: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            actionButton(title: primaryTitle, icon: primaryIcon, tint: .cyan.opacity(0.8), action: primaryAction)
            actionButton(title: secondaryTitle, icon: secondaryIcon, tint: .white.opacity(0.18), action: secondaryAction)
        }
    }

    func actionButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(tint)
            )
        }
        .buttonStyle(.plain)
    }

    func infoCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            Text(detail)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(deckCardBackground(stroke: Color.white.opacity(0.08)))
    }

    func statusCard(title: String, detail: String, tint: Color, stroke: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(deckCardBackground(fill: tint, stroke: stroke))
    }

    func detailChip(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    func sectionLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.62))
            .tracking(1.3)
    }

    func deckCardBackground(
        fill: Color = Color.white.opacity(0.08),
        stroke: Color
    ) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    func deckInsetBackground(stroke: Color) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    func accentColor(for page: DeckPage) -> Color {
        accentColor(for: page.accentToken)
    }

    func accentColor(for token: String?) -> Color {
        switch token {
        case "lattices-cockpit":
            return .cyan
        case "lattices-voice":
            return .cyan
        case "lattices-layout":
            return .mint
        case "lattices-switch":
            return .teal
        case "lattices-history":
            return .orange
        case "voice":
            return .cyan
        case "switch":
            return .teal
        case "layout":
            return .mint
        case "mouse":
            return .orange
        case "rose":
            return .pink
        default:
            return .blue
        }
    }

    func icon(for item: DeckSwitcherItem) -> String {
        switch item.kind {
        case .application:
            return "app.badge"
        case .window:
            return "macwindow"
        case .tab:
            return "square.on.square"
        case .task:
            return "square.grid.2x2.fill"
        case .session:
            return "terminal"
        }
    }

    func humanPlacementLabel(_ placement: String) -> String {
        placement
            .split(separator: "-")
            .map(\.capitalized)
            .joined(separator: " ")
    }

    func previewFrame(_ rect: DeckRect, in canvas: CGSize) -> CGRect {
        CGRect(
            x: rect.x * canvas.width,
            y: rect.y * canvas.height,
            width: rect.w * canvas.width,
            height: rect.h * canvas.height
        )
    }
}
