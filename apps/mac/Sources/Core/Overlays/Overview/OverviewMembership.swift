import Foundation

/// A layer's whole membership, as the sidebar shows it: every configured
/// entry and the windows it holds, its tucked windows, and windows on its
/// scene that nothing claims. Built from every window, never from the
/// scope or the matched rows, so browsing a monitor, Desktop, search or
/// kind never shrinks it.
struct OverviewMembership: Equatable {
    struct Item: Identifiable, Equatable {
        let wid: UInt32
        let app: String
        let title: String
        /// The configured entry that holds it; nil for tucked or unclaimed
        /// windows no entry matches.
        let entry: String?
        let tier: LayerMembership.Tier?
        /// Where it is: monitor, Desktop, and what keeps it from showing.
        let location: String
        /// On the Space its monitor is showing.
        let isShowing: Bool
        /// The Space it's on, nil when Spaces can't place it.
        var spaceId: Int? = nil
        var id: UInt32 { wid }
    }

    /// A configured entry with no window to show.
    struct Missing: Identifiable, Equatable {
        let index: Int
        let name: String
        let pattern: String?
        /// "No window" when its app runs, "Not open" when nothing does.
        let note: String
        var id: Int { index }
    }

    let layerId: String
    let label: String
    let isActive: Bool
    let slot: Int?
    /// Windows its entries hold, entry by entry.
    let members: [Item]
    /// Configured entries holding nothing.
    let missing: [Missing]
    /// Windows the layer keeps tucked away.
    let tucked: [Item]
    /// On its scene, not configured, and claimed by no layer.
    let unclaimed: [Item]

    var total: Int { members.count + missing.count + tucked.count }
    var isEmpty: Bool { members.isEmpty && missing.isEmpty && tucked.isEmpty && unclaimed.isEmpty }
    /// Every entry and window, unclaimed ones too.
    var count: Int { members.count + missing.count + tucked.count + unclaimed.count }

    /// The part of it on one Space: its windows there. Entries with no
    /// window are on no Desktop, so they drop out until All desktops.
    func on(space spaceId: Int) -> OverviewMembership {
        let here: (Item) -> Bool = { $0.spaceId == spaceId }
        return OverviewMembership(
            layerId: layerId, label: label, isActive: isActive, slot: slot,
            members: members.filter(here), missing: [],
            tucked: tucked.filter(here), unclaimed: unclaimed.filter(here)
        )
    }
}

extension OverviewMembership {
    /// The membership of `layerId`, or nil when there's no such layer.
    /// `projection` gives each window's location; only its `all` rows and
    /// displays are read, which ignore the scope.
    static func make(
        layerId: String, inputs: OverviewProjection.Inputs, projection: OverviewProjection
    ) -> OverviewMembership? {
        guard let layer = inputs.layers.first(where: { $0.id == layerId }) else { return nil }
        let tuckedHere = inputs.tucked[layerId] ?? []
        let claimed = Set(inputs.layers.flatMap { other in
            other.windows.map(\.wid) + other.entries.flatMap { $0.unknown.map(\.wid) }
        })
        let tuckedAnywhere = inputs.tucked.values.reduce(into: Set<UInt32>()) { $0.formUnion($1) }

        func item(_ wid: UInt32, app: String, title: String, entry: String?, tier: LayerMembership.Tier?, fallback: String?) -> Item {
            let row = projection.all[wid]
            return Item(
                wid: wid,
                app: row?.app ?? app,
                title: row?.title ?? title,
                entry: entry,
                tier: tier,
                location: row.map(projection.location(of:)) ?? fallback ?? "Minimized or closed",
                isShowing: row?.state == .showing,
                spaceId: row?.state == .unknown ? nil : row?.spaceId
            )
        }

        var seen: Set<UInt32> = []
        var members: [Item] = []
        var missing: [Missing] = []
        for entry in layer.entries {
            for window in entry.windows where !tuckedHere.contains(window.wid) && seen.insert(window.wid).inserted {
                members.append(item(window.wid, app: window.app, title: window.title, entry: entry.name,
                                    tier: window.tier, fallback: window.spot.note))
            }
            for window in entry.unknown where !tuckedHere.contains(window.wid) && seen.insert(window.wid).inserted {
                members.append(item(window.wid, app: window.app, title: window.title, entry: entry.name,
                                    tier: window.tier, fallback: "Minimized or closed"))
            }
            if entry.windows.isEmpty, entry.unknown.isEmpty {
                missing.append(Missing(
                    index: entry.index, name: entry.name, pattern: entry.pattern,
                    note: entry.missing?.note ?? "No window"
                ))
            }
        }

        // Tucked: the layer's own ledger, open windows only.
        let entryOf: [UInt32: String] = Dictionary(
            layer.entries.flatMap { entry in (entry.windows.map(\.wid) + entry.unknown.map(\.wid)).map { ($0, entry.name) } },
            uniquingKeysWith: { a, _ in a }
        )
        let tucked = tuckedHere.sorted().compactMap { wid -> Item? in
            guard let row = projection.all[wid] else { return nil }
            return item(wid, app: row.app, title: row.title, entry: entryOf[wid], tier: row.tier, fallback: nil)
        }

        // Unclaimed, as `LayerStage.want`: a scene extra counts only while
        // no layer claims or tucks it.
        let unclaimed = (inputs.extras[layerId] ?? []).sorted().compactMap { wid -> Item? in
            guard !claimed.contains(wid), !tuckedAnywhere.contains(wid), let row = projection.all[wid] else { return nil }
            return item(wid, app: row.app, title: row.title, entry: nil, tier: nil, fallback: nil)
        }

        return OverviewMembership(
            layerId: layer.id, label: layer.label, isActive: layer.isActive, slot: layer.slot,
            members: members, missing: missing, tucked: tucked, unclaimed: unclaimed
        )
    }
}
