import DeckKit
import SwiftUI

// MARK: - Router

struct ContentView: View {
    @StateObject private var store = DeckStore()
    @State private var showLatsDeck = false
    @State private var showSettings = false
    @State private var trustedBridges: [StoredBridgeTrust] = []

    private var liveMachines: [HomeMachine] {
        HomeDataAdapter.machines(store: store, trustedBridges: trustedBridges)
    }

    private var liveRecent: [HomeRecentEntry] {
        HomeDataAdapter.recent(snapshot: store.snapshot, machineLabel: store.connectionLabel)
    }

    private var liveAgentFeed: [HomeAgentFeedEntry] {
        HomeDataAdapter.agentFeed(snapshot: store.snapshot)
    }

    private var liveAttention: [HomeAttentionItem] {
        HomeDataAdapter.attention(snapshot: store.snapshot)
    }

    private var liveCloud: HomeCloudStatus {
        HomeDataAdapter.cloud(snapshot: store.snapshot)
    }

    private var liveBottomTelemetry: HomeBottomTelemetry {
        HomeDataAdapter.bottomTelemetry(
            snapshot: store.snapshot,
            machineLabel: store.connectionLabel
        )
    }

    var body: some View {
        NavigationStack {
            LatsBackground {
                HomeView(
                    // Live data — every section with a real source on
                    // DeckRuntimeSnapshot is wired through HomeDataAdapter.
                    // Sections still without a backend (terminal/calendar/
                    // scenes/routines/sync) pass empty arrays; their
                    // tiles/sections hide themselves.
                    machines:  liveMachines,
                    scenes:    [],
                    routines:  [],
                    recent:    liveRecent,
                    sync:      [],
                    cloud:     liveCloud,
                    agentFeed: liveAgentFeed,
                    terminal:  [],
                    calendar:  [],
                    attention: liveAttention,
                    bottomTelemetry: liveBottomTelemetry,

                    onEnterDeck: { machine in
                        // Only the currently-active machine has a live bridge.
                        // Tapping an offline / online-but-not-active card must
                        // not silently open the active machine's deck.
                        guard machine.status == .active else { return }
                        showLatsDeck = true
                    },
                    onPair:      { showSettings = true },
                    onSettings:  { showSettings = true },

                    // Voice relay — wired to the active Mac via /deck/perform.
                    voiceState:        store.snapshot?.voice,
                    voiceMacLabel:     store.connectionLabel,
                    isVoicePerforming: store.isPerformingAction,
                    onVoiceStart:      { store.startVoice() },
                    onVoiceStop:       { store.stopVoice() },
                    onVoiceCancel:     { store.stopVoice() },
                    onVoiceRemediate:  { _ in /* deferred — wired after error pipeline lands */ }
                )
                .onAppear {
                    trustedBridges = DeckBridgeSecurityStore.shared.trustedBridgeList()
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showLatsDeck) {
                LatsDeckScreen(
                    liveSnapshot: store.snapshot,
                    connectionLabel: store.connectionLabel,
                    onAction: { actionID, payload, label in
                        store.perform(
                            actionID: actionID,
                            pageID: "cockpit",
                            payload: payload,
                            label: label
                        )
                    },
                    onTrackpadEvent: { event, dx, dy in
                        store.sendTrackpad(event: event, dx: dx, dy: dy)
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                LatsSettingsView(store: store)
                    .preferredColorScheme(.dark)
            }
            // Adaptive polling: speed up while the user is in the cockpit
            // (Deck or settings) — Home alone runs in ambient mode.
            .onChange(of: showLatsDeck) { _, isOpen in
                store.setUIPriority(isOpen ? .fast : .ambient)
            }
            .onChange(of: showSettings) { _, isOpen in
                store.setUIPriority(isOpen ? .fast : .ambient)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Home (no Mac connected)

struct LatsHomeView: View {
    @ObservedObject var store: DeckStore
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LatsTopBar(
                product: "LATS",
                section: "PAIR",
                trailing: AnyView(
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundStyle(LatsPalette.textDim)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                )
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    discoveryCard
                    manualCard
                    if let message = store.errorMessage {
                        errorCard(message)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            LatsSectionLabel(text: "lats deck")
            Text("Pair your Mac")
                .font(LatsFont.ui(28, weight: .bold))
                .foregroundStyle(LatsPalette.text)
                .tracking(-0.4)
            Text("A trackpad cockpit on your iPad. Discover the Lattices menu bar app on your local network and pair this device to start sending voice, layout, and shortcut commands.")
                .font(LatsFont.ui(13))
                .foregroundStyle(LatsPalette.textDim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: [
                        LatsPalette.surface,
                        LatsPalette.surface.opacity(0.4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LatsSectionLabel(text: "nearby macs")
                Spacer()
                LatsButton(title: "Refresh", icon: "arrow.clockwise", style: .ghost) {
                    store.refreshDiscovery()
                }
            }

            if store.discoveredBridges.isEmpty {
                LatsEmptyState(
                    title: "no bridge discovered",
                    subtitle: "Make sure the Lattices menu bar app is running on the same Wi-Fi network.",
                    icon: "wifi.exclamationmark"
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(store.discoveredBridges) { bridge in
                        LatsListRow(
                            title: bridge.name,
                            subtitle: "\(bridge.host):\(bridge.port) · \(bridge.source)",
                            icon: "macwindow.and.iphone",
                            iconTint: .green,
                            onTap: { store.connect(to: bridge) }
                        ) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LatsPalette.textFaint)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LatsSectionLabel(text: "manual connection")
                Spacer()
            }
            Text("Use this if Bonjour discovery is blocked. Enter the Mac's Bonjour host, such as `mini.local`, or its local network name.")
                .font(LatsFont.mono(10))
                .foregroundStyle(LatsPalette.textDim)
                .lineSpacing(2)

            VStack(spacing: 8) {
                LatsField(placeholder: "Mac host", text: $store.manualHost, autocapitalize: false)
                LatsField(placeholder: "Port", text: $store.manualPort, keyboardType: .numberPad)
            }

            LatsButton(title: "Connect", icon: "bolt.fill", style: .primary(.green)) {
                store.connectManually()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(LatsPalette.red)
                LatsSectionLabel(text: "connection issue", tint: LatsPalette.red)
            }
            Text(message)
                .font(LatsFont.mono(11))
                .foregroundStyle(LatsPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.red.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Connected home (Mac paired)

struct LatsConnectedHome: View {
    @ObservedObject var store: DeckStore
    let onEnterDeck: () -> Void
    let onSettings: () -> Void

    @State private var trustedBridges: [StoredBridgeTrust] = []

    private var securityLabel: String? {
        guard let h = store.health else { return nil }
        if h.requestSigningRequired && h.payloadEncryptionRequired { return "secure" }
        if h.requestSigningRequired { return "signed" }
        return nil
    }

    // MARK: - Deck cards (one per paired Mac)

    private struct DeckCard: Identifiable {
        let id: String
        let name: String       // e.g., "Arach's Mac mini" or "air.local"
        let host: String       // e.g., "mini.local" — secondary line
        let icon: String
        let isActive: Bool
        let isOnline: Bool
        let endpoint: BridgeEndpoint?
    }

    /// Compare bridge names loosely (case- and punctuation-insensitive) so a
    /// trusted record matches its discovered/active counterpart even if the
    /// service name and the persisted name differ slightly.
    private static func nameKey(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: ".local", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private static func deckIcon(for hostOrName: String) -> String {
        let s = hostOrName.lowercased()
        if s.contains("mini") { return "macmini" }
        if s.contains("studio") { return "macstudio" }
        if s.contains("imac") { return "desktopcomputer" }
        if s.contains("air") || s.contains("book") || s.contains("pro") { return "laptopcomputer" }
        return "macwindow.and.iphone"
    }

    private var deckCards: [DeckCard] {
        var cards: [DeckCard] = []
        var seenKeys = Set<String>()

        if let endpoint = store.activeEndpoint {
            let displayName = endpoint.name.isEmpty ? endpoint.host : endpoint.name
            seenKeys.insert(Self.nameKey(displayName))
            seenKeys.insert(Self.nameKey(endpoint.host))
            cards.append(DeckCard(
                id: "active-\(endpoint.host)",
                name: displayName,
                host: endpoint.host,
                icon: Self.deckIcon(for: displayName + " " + endpoint.host),
                isActive: true,
                isOnline: true,
                endpoint: endpoint
            ))
        }

        for bridge in store.discoveredBridges {
            let displayName = bridge.name.isEmpty ? bridge.host : bridge.name
            let nk = Self.nameKey(displayName)
            let hk = Self.nameKey(bridge.host)
            if seenKeys.contains(nk) || seenKeys.contains(hk) { continue }
            seenKeys.insert(nk); seenKeys.insert(hk)
            cards.append(DeckCard(
                id: "online-\(bridge.host)",
                name: displayName,
                host: bridge.host,
                icon: Self.deckIcon(for: displayName + " " + bridge.host),
                isActive: false,
                isOnline: true,
                endpoint: bridge
            ))
        }

        for trust in trustedBridges {
            let nk = Self.nameKey(trust.bridgeName)
            if seenKeys.contains(nk) { continue }
            seenKeys.insert(nk)
            cards.append(DeckCard(
                id: "trusted-\(trust.bridgePublicKey)",
                name: trust.bridgeName,
                host: "paired",
                icon: Self.deckIcon(for: trust.bridgeName),
                isActive: false,
                isOnline: false,
                endpoint: nil
            ))
        }
        return cards
    }

    var body: some View {
        VStack(spacing: 0) {
            LatsTopBar(
                product: "LATS",
                section: store.connectionLabel,
                trailing: AnyView(
                    HStack(spacing: 8) {
                        if let security = securityLabel {
                            LatsBadge(text: security, tint: LatsPalette.green, dot: true)
                        }
                        Button { store.refreshSnapshot() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LatsPalette.textDim)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        Button(action: onSettings) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 13))
                                .foregroundStyle(LatsPalette.textDim)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                )
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    decksRow
                    quickStats
                    surfacesSection
                    if let result = store.lastActionResult {
                        actionResultCard(result)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { trustedBridges = DeckBridgeSecurityStore.shared.trustedBridgeList() }
    }

    private var decksRow: some View {
        let cards = deckCards
        let columns = [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(cards) { card in
                deckCardView(card)
            }
        }
    }

    private func deckCardView(_ card: DeckCard) -> some View {
        let tint: Color = card.isActive ? LatsPalette.green
            : card.isOnline ? LatsPalette.blue
            : LatsPalette.textFaint

        return Button {
            if card.isActive {
                onEnterDeck()
            } else if let endpoint = card.endpoint {
                store.connect(to: endpoint)
                // Open the deck cover; it will reflect the new snapshot when it lands.
                onEnterDeck()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tint.opacity(0.15))
                        Image(systemName: card.icon)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.4), lineWidth: 1)
                    )

                    Spacer()

                    if card.isActive {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LatsPalette.textDim)
                    } else if !card.isOnline {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(LatsPalette.textFaint)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name)
                        .font(LatsFont.mono(13, weight: .semibold))
                        .foregroundStyle(LatsPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(card.host)
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(card.isActive ? tint.opacity(0.08) : LatsPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(card.isActive ? tint.opacity(0.5) : LatsPalette.hairline2, lineWidth: 1)
            )
            .opacity(card.isOnline ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!card.isOnline)
    }

    private var quickStats: some View {
        HStack(spacing: 8) {
            statTile(
                label: "windows",
                value: "\(store.snapshot?.desktop?.visibleWindowCount ?? 0)",
                tint: .blue
            )
            statTile(
                label: "sessions",
                value: "\(store.snapshot?.desktop?.sessionCount ?? 0)",
                tint: .green
            )
            statTile(
                label: "active app",
                value: store.snapshot?.desktop?.activeAppName ?? "—",
                tint: .amber
            )
        }
    }

    private func statTile(label: String, value: String, tint: LatsTint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LatsSectionLabel(text: label, tint: tint.color.opacity(0.85))
            Text(value)
                .font(LatsFont.mono(14, weight: .regular))
                .foregroundStyle(LatsPalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private var surfacesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LatsSectionLabel(text: "surfaces")
                Spacer()
                Text("legacy · will fold into deck")
                    .font(LatsFont.mono(9))
                    .foregroundStyle(LatsPalette.textFaint)
            }

            let pages = store.manifest?.pages ?? []

            VStack(spacing: 6) {
                ForEach(pages) { page in
                    NavigationLink {
                        LatsSurfaceDetailView(page: page, store: store)
                    } label: {
                        LatsListRow(
                            title: page.title,
                            subtitle: page.kind.rawValue,
                            icon: page.iconSystemName,
                            iconTint: tint(for: page)
                        ) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LatsPalette.textFaint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func tint(for page: DeckPage) -> LatsTint {
        switch page.kind {
        case .cockpit: return .green
        case .voice: return .red
        case .layout: return .blue
        case .switch: return .teal
        case .history: return .amber
        case .mac, .custom: return .violet
        }
    }

    private func actionResultCard(_ result: DeckActionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(result.ok ? LatsPalette.green : LatsPalette.red)
                    .frame(width: 6, height: 6)
                LatsSectionLabel(text: result.ok ? "last action" : "action failed",
                                 tint: result.ok ? LatsPalette.green : LatsPalette.red)
            }
            Text(result.summary)
                .font(LatsFont.ui(13, weight: .semibold))
                .foregroundStyle(LatsPalette.text)
            if let detail = result.detail, !detail.isEmpty {
                Text(detail)
                    .font(LatsFont.mono(10))
                    .foregroundStyle(LatsPalette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill((result.ok ? LatsPalette.green : LatsPalette.red).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((result.ok ? LatsPalette.green : LatsPalette.red).opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Settings drawer

struct LatsSettingsView: View {
    @ObservedObject var store: DeckStore
    @Environment(\.dismiss) private var dismiss

    @State private var trustedBridges: [StoredBridgeTrust] = []

    var body: some View {
        LatsBackground {
            VStack(spacing: 0) {
                LatsTopBar(
                    product: "LATS",
                    section: "SETTINGS",
                    onClose: { dismiss() }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        macsCard
                        if store.activeEndpoint != nil {
                            activeDetailCard
                            disconnectCard
                        }
                        aboutCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { reloadTrustedBridges() }
    }

    // MARK: - Macs list

    private struct MacEntry: Identifiable {
        let id: String
        let name: String
        let host: String
        let port: Int
        let source: String         // "Bonjour", "Manual", "Paired"
        let isActive: Bool
        let isOnline: Bool         // discovered on the network now
        let isTrusted: Bool        // previously paired
        let publicKey: String?     // for forget action
        let fingerprint: String?
    }

    private var macEntries: [MacEntry] {
        var entries: [MacEntry] = []
        let activeName = store.activeEndpoint?.name
        let activePK = store.health?.bridgePublicKey

        // Active first
        if let endpoint = store.activeEndpoint {
            let h = store.health
            entries.append(MacEntry(
                id: "active-\(endpoint.host):\(endpoint.port)",
                name: endpoint.name,
                host: endpoint.host,
                port: endpoint.port,
                source: endpoint.source,
                isActive: true,
                isOnline: true,
                isTrusted: h.map { DeckBridgeSecurityStore.shared.isTrusted(health: $0) } ?? false,
                publicKey: h?.bridgePublicKey,
                fingerprint: h?.bridgeFingerprint
            ))
        }

        // Discovered (excluding the active one)
        for bridge in store.discoveredBridges {
            if bridge.name == activeName { continue }
            entries.append(MacEntry(
                id: "discovered-\(bridge.host):\(bridge.port)",
                name: bridge.name,
                host: bridge.host,
                port: bridge.port,
                source: bridge.source,
                isActive: false,
                isOnline: true,
                isTrusted: false,         // unknown until we pair
                publicKey: nil,
                fingerprint: nil
            ))
        }

        // Trusted but offline (paired before, not currently discovered)
        for trust in trustedBridges {
            if trust.bridgePublicKey == activePK { continue }
            // skip if it shows up under discovered with the same name (best-effort match)
            if entries.contains(where: { $0.name == trust.bridgeName && $0.isOnline }) { continue }
            entries.append(MacEntry(
                id: "trusted-\(trust.bridgePublicKey)",
                name: trust.bridgeName,
                host: "—",
                port: 0,
                source: "Paired",
                isActive: false,
                isOnline: false,
                isTrusted: true,
                publicKey: trust.bridgePublicKey,
                fingerprint: trust.bridgeFingerprint
            ))
        }
        return entries
    }

    private var macsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LatsSectionLabel(text: "macs")
                Spacer()
                LatsButton(title: "Refresh", icon: "arrow.clockwise", style: .ghost) {
                    store.refreshDiscovery()
                    reloadTrustedBridges()
                }
            }

            let entries = macEntries
            if entries.isEmpty {
                LatsEmptyState(
                    title: "no macs paired",
                    subtitle: "Pair from the home screen, or open Lattices on the Mac and join the same Wi-Fi.",
                    icon: "macwindow.and.iphone"
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(entries) { entry in
                        macRow(entry)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private func macRow(_ entry: MacEntry) -> some View {
        let stateTint: LatsTint = entry.isActive ? .green : entry.isOnline ? .blue : .amber
        let stateLabel: String = entry.isActive ? "active" : entry.isOnline ? "online" : "offline"

        return Button {
            if !entry.isActive, entry.isOnline {
                store.connect(to: BridgeEndpoint(
                    name: entry.name,
                    host: entry.host,
                    port: entry.port,
                    source: entry.source
                ))
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(stateTint.color.opacity(0.15))
                    Image(systemName: entry.isOnline ? "macwindow.and.iphone" : "macwindow")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(stateTint.color)
                }
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(stateTint.color.opacity(0.4), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(LatsFont.ui(13, weight: .semibold))
                            .foregroundStyle(LatsPalette.text)
                        if entry.isTrusted {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(LatsPalette.green)
                        }
                    }
                    if entry.isOnline {
                        Text("\(entry.host):\(entry.port) · \(entry.source)")
                            .font(LatsFont.mono(10))
                            .foregroundStyle(LatsPalette.textDim)
                    } else if let fp = entry.fingerprint {
                        Text("paired · \(String(fp.prefix(10)))…")
                            .font(LatsFont.mono(10))
                            .foregroundStyle(LatsPalette.textDim)
                    } else {
                        Text(entry.source.lowercased())
                            .font(LatsFont.mono(10))
                            .foregroundStyle(LatsPalette.textDim)
                    }
                }

                Spacer()

                LatsBadge(text: stateLabel, tint: stateTint.color, dot: entry.isActive)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(entry.isActive ? stateTint.color.opacity(0.10) : Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(entry.isActive ? stateTint.color.opacity(0.5) : LatsPalette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let pk = entry.publicKey, !entry.isActive {
                Button(role: .destructive) {
                    DeckBridgeSecurityStore.shared.forgetBridge(publicKey: pk)
                    reloadTrustedBridges()
                } label: { Label("Forget", systemImage: "trash") }
            }
        }
    }

    private func reloadTrustedBridges() {
        trustedBridges = DeckBridgeSecurityStore.shared.trustedBridgeList()
    }

    // MARK: - Active detail / disconnect / about

    private var activeDetailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LatsSectionLabel(text: "active session")
            if let endpoint = store.activeEndpoint {
                LatsKVRow(key: "host", value: endpoint.host, valueColor: LatsPalette.green)
                LatsKVRow(key: "port", value: "\(endpoint.port)")
                LatsKVRow(key: "source", value: endpoint.source)
            }
            if let h = store.health {
                LatsKVRow(key: "mode", value: h.mode)
                let sec = (h.requestSigningRequired && h.payloadEncryptionRequired) ? "signed + encrypted"
                    : h.requestSigningRequired ? "signed" : "open"
                LatsKVRow(key: "security", value: sec, valueColor: LatsPalette.green)
                LatsKVRow(key: "fingerprint", value: String(h.bridgeFingerprint.prefix(12)) + "…",
                          valueColor: LatsPalette.textDim)
                LatsKVRow(key: "version", value: h.version, valueColor: LatsPalette.textDim)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private var disconnectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LatsSectionLabel(text: "device")
            Text("Disconnecting clears the active session. Re-pair to re-encrypt this device with the Mac.")
                .font(LatsFont.mono(10))
                .foregroundStyle(LatsPalette.textDim)
                .fixedSize(horizontal: false, vertical: true)
            LatsButton(title: "Disconnect", icon: "xmark.circle", style: .primary(.red)) {
                store.disconnect()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            LatsSectionLabel(text: "about")
            LatsKVRow(key: "build", value: "lats deck · v0.1")
            LatsKVRow(key: "device", value: UIDevice.current.model)
            LatsKVRow(key: "system", value: "iOS \(UIDevice.current.systemVersion)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }
}

// MARK: - Surface detail (per page kind)

struct LatsSurfaceDetailView: View {
    let page: DeckPage
    @ObservedObject var store: DeckStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LatsBackground {
            VStack(spacing: 0) {
                LatsTopBar(
                    product: "LATS",
                    section: page.title.uppercased(),
                    trailing: AnyView(EmptyView()),
                    onClose: { dismiss() }
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch page.kind {
                        case .cockpit:
                            LatsCockpitSurface(store: store)
                        case .voice:
                            LatsVoiceSurface(store: store)
                        case .layout:
                            LatsLayoutSurface(store: store)
                        case .switch:
                            LatsSwitchSurface(store: store)
                        case .history:
                            LatsHistorySurface(store: store)
                        case .mac, .custom:
                            LatsEmptyState(
                                title: page.title.lowercased(),
                                subtitle: "This surface will be expanded as the shared contract grows.",
                                icon: page.iconSystemName
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 880)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Surface bodies

struct LatsCockpitSurface: View {
    @ObservedObject var store: DeckStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LatsSectionLabel(text: "command deck")
            Text("Open the cockpit for the full Lats Deck experience.")
                .font(LatsFont.mono(11))
                .foregroundStyle(LatsPalette.textDim)
            if let cockpit = store.snapshot?.cockpit {
                let pageCount = cockpit.pages.count
                let tileCount = cockpit.pages.reduce(0) { $0 + $1.tiles.count }
                HStack(spacing: 8) {
                    statChip(label: "decks", value: "\(pageCount)", tint: .green)
                    statChip(label: "tiles", value: "\(tileCount)", tint: .blue)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private func statChip(label: String, value: String, tint: LatsTint) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(tint.color.opacity(0.8))
            Text(value)
                .font(LatsFont.mono(11, weight: .semibold))
                .foregroundStyle(LatsPalette.text)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(
            Capsule().fill(tint.color.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(tint.color.opacity(0.4), lineWidth: 1)
        )
    }
}

struct LatsVoiceSurface: View {
    @ObservedObject var store: DeckStore

    private var phaseLabel: String {
        store.snapshot?.voice?.phase.rawValue.uppercased() ?? "IDLE"
    }
    private var phaseColor: Color {
        switch store.snapshot?.voice?.phase {
        case .listening: return LatsPalette.red
        case .transcribing, .reasoning: return LatsPalette.violet
        case .speaking: return LatsPalette.amber
        default: return LatsPalette.green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroPhase
            actions
            transcriptCard
            tryThis
        }
    }

    private var heroPhase: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(phaseColor).frame(width: 8, height: 8)
                LatsSectionLabel(text: store.snapshot?.voice?.provider?.uppercased() ?? "VOICE",
                                 tint: phaseColor)
            }
            Text(phaseLabel)
                .font(LatsFont.ui(36, weight: .bold))
                .foregroundStyle(LatsPalette.text)
                .tracking(-0.6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }

    private var actions: some View {
        HStack(spacing: 8) {
            LatsButton(
                title: store.snapshot?.voice?.phase == .listening ? "Stop" : "Start Voice",
                icon: store.snapshot?.voice?.phase == .listening ? "stop.fill" : "mic.fill",
                style: .primary(.red)
            ) {
                store.perform(actionID: "voice.toggle", pageID: "voice")
            }
            LatsButton(title: "Cancel", icon: "xmark", style: .secondary) {
                store.perform(actionID: "voice.cancel", pageID: "voice")
            }
        }
    }

    @ViewBuilder
    private var transcriptCard: some View {
        if let transcript = store.snapshot?.voice?.transcript, !transcript.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                LatsSectionLabel(text: "transcript")
                Text("\u{201C}\(transcript)\u{201D}")
                    .font(LatsFont.ui(15))
                    .foregroundStyle(LatsPalette.text)
                    .lineSpacing(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
            )
        }

        if let summary = store.snapshot?.voice?.responseSummary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                LatsSectionLabel(text: "response")
                Text(summary)
                    .font(LatsFont.mono(11))
                    .foregroundStyle(LatsPalette.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
            )
        }
    }

    private var tryThis: some View {
        let examples = [
            "Optimize the layout",
            "Move this window left",
            "Focus Safari",
            "Switch to my review layer",
        ]
        return VStack(alignment: .leading, spacing: 8) {
            LatsSectionLabel(text: "try saying")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 6)], spacing: 6) {
                ForEach(examples, id: \.self) { e in
                    Text(e)
                        .font(LatsFont.mono(11))
                        .foregroundStyle(LatsPalette.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.025))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(LatsPalette.hairline, lineWidth: 1)
                        )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }
}

struct LatsLayoutSurface: View {
    @ObservedObject var store: DeckStore

    private let placements: [(String, String, String)] = [
        ("Left",        "left",         "rectangle.leadinghalf.filled"),
        ("Right",       "right",        "rectangle.trailinghalf.filled"),
        ("Top Left",    "top-left",     "rectangle.inset.topleft.filled"),
        ("Top Right",   "top-right",    "rectangle.inset.topright.filled"),
        ("Bottom Left", "bottom-left",  "rectangle.inset.bottomleft.filled"),
        ("Bottom Right","bottom-right", "rectangle.inset.bottomright.filled"),
        ("Center",      "center",       "plus.rectangle.on.rectangle"),
        ("Maximize",    "maximize",     "macwindow"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stats
            actions
            if let preview = store.snapshot?.layout?.preview, !preview.windows.isEmpty {
                previewCard(preview: preview)
            }
            placementsCard
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            stat("screens", "\(store.snapshot?.desktop?.screenCount ?? 0)", .blue)
            stat("visible", "\(store.snapshot?.desktop?.visibleWindowCount ?? 0)", .teal)
            stat("sessions", "\(store.snapshot?.desktop?.sessionCount ?? 0)", .green)
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: LatsTint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LatsSectionLabel(text: label, tint: tint.color.opacity(0.8))
            Text(value)
                .font(LatsFont.mono(14, weight: .regular))
                .foregroundStyle(LatsPalette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(LatsPalette.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LatsPalette.hairline2, lineWidth: 1))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            LatsButton(title: "Optimize", icon: "rectangle.3.group.fill", style: .primary(.blue)) {
                store.perform(actionID: "layout.optimize", pageID: "layout")
            }
            LatsButton(title: "Center", icon: "plus.rectangle.on.rectangle") {
                store.perform(
                    actionID: "layout.placeFrontmost",
                    pageID: "layout",
                    payload: ["placement": .string("center")]
                )
            }
        }
    }

    private var placementsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LatsSectionLabel(text: "placements")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                ForEach(placements, id: \.1) { p in
                    Button {
                        store.perform(
                            actionID: "layout.placeFrontmost",
                            pageID: "layout",
                            payload: ["placement": .string(p.1)]
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: p.2).font(.system(size: 12))
                            Text(p.0).font(LatsFont.mono(11, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(LatsPalette.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.025))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).stroke(LatsPalette.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1))
    }

    private func previewCard(preview: DeckLayoutPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LatsSectionLabel(text: "stage")
                Spacer()
                Text("tap a window to focus")
                    .font(LatsFont.mono(9))
                    .foregroundStyle(LatsPalette.textFaint)
            }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LatsPalette.bgEdge)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).stroke(LatsPalette.hairline, lineWidth: 1)
                        )
                    ForEach(preview.windows) { w in
                        let frame = CGRect(
                            x: w.normalizedFrame.x * geo.size.width,
                            y: w.normalizedFrame.y * geo.size.height,
                            width: w.normalizedFrame.w * geo.size.width,
                            height: w.normalizedFrame.h * geo.size.height
                        )
                        let tint = LatsTint.from(token: w.appCategoryTint).color
                        Button {
                            store.perform(
                                actionID: "switch.focusItem",
                                pageID: "layout",
                                payload: ["itemID": .string(w.itemID)]
                            )
                        } label: {
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(tint.opacity(w.isFrontmost ? 0.42 : 0.22))
                                if frame.width > 80, frame.height > 32 {
                                    Text(w.title)
                                        .font(LatsFont.mono(9, weight: .semibold))
                                        .foregroundStyle(LatsPalette.text)
                                        .padding(6)
                                }
                            }
                            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(tint.opacity(w.isFrontmost ? 0.85 : 0.45), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
            .aspectRatio(max(preview.aspectRatio, 1.0), contentMode: .fit)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1))
    }
}

struct LatsSwitchSurface: View {
    @ObservedObject var store: DeckStore

    var body: some View {
        let items = store.snapshot?.switcher?.items ?? []
        let groups = Dictionary(grouping: items, by: { $0.kind })
        let order: [DeckSwitcherItemKind] = [.application, .window, .task, .session]

        return VStack(alignment: .leading, spacing: 14) {
            ForEach(order, id: \.rawValue) { kind in
                if let entries = groups[kind], !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        LatsSectionLabel(text: kind.rawValue)
                        VStack(spacing: 4) {
                            ForEach(entries) { item in
                                switcherRow(item)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(LatsPalette.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(LatsPalette.hairline2, lineWidth: 1)
                    )
                }
            }

            if items.isEmpty {
                LatsEmptyState(
                    title: "no items",
                    subtitle: "Open some apps or windows on the Mac to see them here.",
                    icon: "square.stack.3d.up"
                )
            }
        }
    }

    private func switcherRow(_ item: DeckSwitcherItem) -> some View {
        Button {
            store.perform(
                actionID: "switch.focusItem",
                pageID: "switch",
                payload: ["itemID": .string(item.id)]
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: item.kind))
                    .font(.system(size: 12))
                    .foregroundStyle(LatsPalette.text)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(item.isFrontmost ? LatsPalette.green.opacity(0.22) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(item.isFrontmost ? LatsPalette.green.opacity(0.5) : LatsPalette.hairline, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(LatsFont.ui(13, weight: .medium))
                        .foregroundStyle(LatsPalette.text)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(LatsFont.mono(10))
                            .foregroundStyle(LatsPalette.textDim)
                    }
                }
                Spacer()
                if item.isFrontmost {
                    LatsBadge(text: "live", tint: LatsPalette.green, dot: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(LatsPalette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func icon(for kind: DeckSwitcherItemKind) -> String {
        switch kind {
        case .application: return "app.badge"
        case .window: return "macwindow"
        case .tab: return "square.on.square"
        case .task: return "square.grid.2x2.fill"
        case .session: return "terminal"
        }
    }
}

struct LatsHistorySurface: View {
    @ObservedObject var store: DeckStore

    var body: some View {
        let entries = store.snapshot?.history ?? []
        return VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                LatsEmptyState(
                    title: "no history yet",
                    subtitle: "Run a deck action and the shared history feed will start filling in.",
                    icon: "clock.arrow.circlepath"
                )
            } else {
                ForEach(entries) { entry in
                    historyRow(entry)
                }
            }
        }
    }

    private func historyRow(_ entry: DeckHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(LatsFont.ui(13, weight: .medium))
                        .foregroundStyle(LatsPalette.text)
                    if let detail = entry.detail, !detail.isEmpty {
                        Text(detail)
                            .font(LatsFont.mono(10))
                            .foregroundStyle(LatsPalette.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if let undo = entry.undoActionID {
                    LatsButton(title: "Undo", icon: "arrow.uturn.backward", style: .primary(.amber)) {
                        store.perform(actionID: undo, pageID: "history")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(LatsPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(LatsPalette.hairline2, lineWidth: 1)
        )
    }
}
