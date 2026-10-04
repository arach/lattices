import SwiftUI

/// Pure staged composition: opening, editing and cancelling never save or move.
struct OverviewComposition: Identifiable {
    enum Slot: String, CaseIterable, Identifiable {
        case left = "Left", middle = "Middle", right = "Right", full = "Full"
        var id: String { rawValue }
        var type: AppType { self == .left ? .terminal : self == .middle ? .editor : .browser }
        static func suggested(_ app: String) -> Slot {
            switch LayerLayout.lane(for: AppTypeClassifier.classify(app)) {
            case .left: return .left
            case .middle: return .middle
            case .right: return .right
            }
        }
    }
    let id = UUID()
    let windows: [WindowEntry]
    var name = ""
    var moveSources: [String] = []
    var slots: [UInt32: Slot]
    init(windows: [WindowEntry]) {
        var seen = Set<UInt32>()
        self.windows = windows.filter { seen.insert($0.wid).inserted }
        slots = Dictionary(self.windows.map { ($0.wid, Slot.suggested($0.app)) }, uniquingKeysWith: { a, _ in a })
    }
    var tiles: [UInt32: String] {
        let ordered = windows.filter { slots[$0.wid] != .full }.sorted {
            (Slot.allCases.firstIndex(of: slots[$0.wid] ?? .right) ?? 2) <
            (Slot.allCases.firstIndex(of: slots[$1.wid] ?? .right) ?? 2)
        }
        // Explicit composition uses the engine's lane layout, then persists
        // the same unit rectangles as grid tiles. Gather alone applies them.
        var types = ordered.map { (slots[$0.wid] ?? .right).type }
        let used = Set(ordered.compactMap { slots[$0.wid] })
        // Reserve empty neighboring lanes so Left never becomes centered and
        // Middle never collapses into the left half when another slot is empty.
        if used.contains(.middle) {
            if !used.contains(.left) { types.append(.terminal) }
            if !used.contains(.right) { types.append(.browser) }
        } else if used == [.left] { types.append(.browser) }
        else if used == [.right] { types.append(.terminal) }
        let frames = LayerLayout.frames(.auto, types: types, aspect: LayerLayout.ultrawide)
        var result: [UInt32: String] = [:]
        for (window, rect) in zip(ordered, frames) {
            let n = 10000
            let x = Int((rect.minX * CGFloat(n)).rounded()), y = Int((rect.minY * CGFloat(n)).rounded())
            let endX = Int((rect.maxX * CGFloat(n)).rounded()) - 1
            let endY = Int((rect.maxY * CGFloat(n)).rounded()) - 1
            result[window.wid] = "grid:\(n)x\(n):\(x),\(y)-\(endX),\(endY)"
        }
        for window in windows where slots[window.wid] == .full { result[window.wid] = "maximize" }
        return result
    }
    var preview: [UInt32: CGRect] {
        tiles.compactMapValues { text in
            guard let f = PlacementSpec(string: text)?.fractions else { return nil }
            return CGRect(x: f.0, y: f.1, width: f.2, height: f.3)
        }
    }
}

struct OverviewComposeSheet: View {
    @State var draft: OverviewComposition
    let create: (OverviewComposition) -> Bool
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New layer from \(draft.windows.count) windows").font(.headline)
            TextField("Layer name", text: $draft.name)
                .textFieldStyle(.roundedBorder).focused($nameFocused)
            ForEach(draft.windows, id: \.wid) { window in
                HStack {
                    Text(window.app + " · " + window.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        .onDrag { OverviewMembershipDrag(session: "", windows: [window.wid], sourceLayer: nil, move: false).provider() }
                    Picker("Slot", selection: Binding(get: { draft.slots[window.wid] ?? .right },
                                                     set: { draft.slots[window.wid] = $0 })) {
                        ForEach(OverviewComposition.Slot.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 125)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Palette.bg
                    ForEach(draft.windows, id: \.wid) { window in
                        if let rect = draft.preview[window.wid] {
                            previewWindow(window.app, rect: rect, size: geo.size)
                        }
                    }
                }
            }.frame(height: 160)
            .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                ForEach([OverviewComposition.Slot.left, .middle, .right]) { slot in
                    Text("Drop: " + slot.rawValue).font(.caption)
                        .frame(maxWidth: .infinity).padding(10)
                        .background(Palette.surface)
                        .onDrop(of: [OverviewMembershipDrag.type], isTargeted: nil) { providers in
                            OverviewMembershipDrag.receive(providers) { payload in
                                for wid in payload.windows where draft.windows.contains(where: { $0.wid == wid }) {
                                    draft.slots[wid] = slot
                                }
                            }
                        }
                }
            }
            }
            Text("Saves membership and slots only. Nothing moves until Gather. Full slots may overlap.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { if create(draft) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 580).background(Palette.bg)
        .onAppear { nameFocused = true }
    }
    private func previewWindow(_ app: String, rect: CGRect, size: CGSize) -> some View {
        let width: CGFloat = max(1, rect.width * size.width - 4)
        let height: CGFloat = max(1, rect.height * size.height - 4)
        let x: CGFloat = rect.minX * size.width + 2
        let y: CGFloat = rect.minY * size.height + 2
        return Text(app).font(.caption)
            .frame(width: width, height: height)
            .background(Palette.surface)
            .border(Palette.borderLit)
            .offset(x: x, y: y)
    }

}
