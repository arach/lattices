import AppKit
import SwiftUI

// MARK: - HyperspaceCommandBar
//
// The `/` command bar for Hyperspace — a slim palette pinned to the bottom of the
// survey monitor. Curated to the survey's own verbs: search the windows on this
// screen, target a group or layer (⏎ adds them to the selection), and /tile to
// stage a placement. Monitor-scoped — it only ever sees the windows / clusters /
// layers on the screen you opened it on. Wears the same chrome as the main command
// bar (HUDChrome carbon texture + cyan accent) so the two read as one family. Like
// NewLayerPanel it must be its own key panel, because the survey's screen-panels
// can't become key. Nothing real moves here: selections build the set, /tile
// stages a location, and gather (⏎/G) is still the one real move.

final class HyperspaceCommandModel: ObservableObject {
    struct WindowItem: Identifiable { let wid: UInt32; let title: String; let app: String; var id: UInt32 { wid } }
    struct GroupItem: Identifiable { let cid: Int; let name: String; let hint: String; let members: [UInt32]; var id: Int { cid } }
    struct LayerItem: Identifiable { let lid: String; let name: String; let members: [UInt32]; var id: String { lid } }

    enum Row: Identifiable {
        case window(WindowItem)
        case group(GroupItem)
        case layer(LayerItem)
        case tile(name: String, placement: GridPlacement)
        case saveLayer
        case command(label: String, detail: String, fill: String)

        var id: String {
            switch self {
            case .window(let w):        return "w\(w.wid)"
            case .group(let g):         return "g\(g.cid)"
            case .layer(let l):         return "l\(l.lid)"
            case .tile(let n, _):       return "t\(n)"
            case .saveLayer:            return "savelayer"
            case .command(let l, _, _): return "c\(l)"
            }
        }
    }

    /// What a commit does to the bar: dismiss it, or stay up (selection toggles the
    /// selection and a verb hint pre-fills the field — either way you keep going).
    enum Commit { case close, stay }

    @Published var query: String = "" { didSet { if selected != 0 { selected = 0 } } }
    @Published var selected: Int = 0
    /// The picked set on this screen, in pick order — refreshed after every selection so
    /// rows can show their slot / count. Mirrors the survey's own selection.
    @Published var pluckedOrder: [UInt32] = []

    let windows: [WindowItem]
    let groups: [GroupItem]
    let layers: [LayerItem]

    var onPluckWindow: (UInt32) -> Void = { _ in }
    var onPluckGroup:  (Int) -> Void = { _ in }
    var onRecallLayer: (String) -> Void = { _ in }
    var onTile:        (GridPlacement) -> Void = { _ in }
    var onSaveLayer:   () -> Void = { }
    var pluckedProvider: () -> [UInt32] = { [] }

    init(windows: [WindowItem], groups: [GroupItem], layers: [LayerItem]) {
        self.windows = windows
        self.groups = groups
        self.layers = layers
    }

    func refreshPluck() { pluckedOrder = pluckedProvider() }

    /// 1-based slot of a window in the pick order (the badge number), or nil.
    func slot(of wid: UInt32) -> Int? { pluckedOrder.firstIndex(of: wid).map { $0 + 1 } }
    /// How many of a group's / layer's windows are currently plucked.
    func pluckedCount(_ members: [UInt32]) -> Int {
        let set = Set(pluckedOrder); return members.reduce(0) { $0 + (set.contains($1) ? 1 : 0) }
    }

    // Named half / quadrant / maximize positions → a GridPlacement the survey stages,
    // mirroring the right-click tile menu so /tile and the menu speak the same grid.
    static let tilePositions: [(String, GridPlacement)] = [
        ("Left Half",    GridPlacement(columns: 2, rows: 1, column: 0, row: 0)!),
        ("Right Half",   GridPlacement(columns: 2, rows: 1, column: 1, row: 0)!),
        ("Top Half",     GridPlacement(columns: 1, rows: 2, column: 0, row: 0)!),
        ("Bottom Half",  GridPlacement(columns: 1, rows: 2, column: 0, row: 1)!),
        ("Maximize",     GridPlacement(columns: 1, rows: 1, column: 0, row: 0)!),
        ("Top Left",     GridPlacement(columns: 2, rows: 2, column: 0, row: 0)!),
        ("Top Right",    GridPlacement(columns: 2, rows: 2, column: 1, row: 0)!),
        ("Bottom Left",  GridPlacement(columns: 2, rows: 2, column: 0, row: 1)!),
        ("Bottom Right", GridPlacement(columns: 2, rows: 2, column: 1, row: 1)!),
    ]

    var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        if q.hasPrefix("/tile") || q.hasPrefix("/place") {
            let rest = arg(q, ["/tile", "/place"])
            return Self.tilePositions
                .filter { rest.isEmpty || $0.0.lowercased().contains(rest) }
                .map { Row.tile(name: $0.0, placement: $0.1) }
        }
        if q.hasPrefix("/group") {
            let rest = arg(q, ["/group"])
            return groups
                .filter { rest.isEmpty || $0.hint.lowercased() == rest || score($0.name, rest) != nil }
                .map(Row.group)
        }
        if q.hasPrefix("/layer") {
            let rest = arg(q, ["/layer"])
            if rest.hasPrefix("new") { return [.saveLayer] }
            return layers
                .filter { rest.isEmpty || score($0.name, rest) != nil }
                .map(Row.layer)
        }
        // A bare "/" (or an unrecognised command) → the verb menu.
        if q.hasPrefix("/") {
            let rest = String(q.dropFirst())
            let menu: [Row] = [
                .command(label: "/tile",  detail: "stage a placement for the selection",      fill: "/tile "),
                .command(label: "/group", detail: "target a cluster by name or ⇧-letter",      fill: "/group "),
                .command(label: "/layer", detail: "recall a layer · /layer new saves the pick", fill: "/layer "),
            ]
            return menu.filter { rest.isEmpty || labelOf($0).lowercased().contains(rest) }
        }
        // Empty query → the things you usually target: groups, then layers.
        if q.isEmpty {
            return groups.map(Row.group) + layers.map(Row.layer)
        }
        // Plain search across windows + groups + layers, scored; groups/layers edge
        // out a same-score window so a typed cluster name leads.
        var scored: [(Int, Row)] = []
        for w in windows { if let s = best([w.title, w.app], q) { scored.append((s, .window(w))) } }
        for g in groups  { if let s = score(g.name, q)         { scored.append((s + 2, .group(g))) } }
        for l in layers  { if let s = score(l.name, q)         { scored.append((s + 1, .layer(l))) } }
        return scored.sorted { $0.0 > $1.0 }.prefix(9).map { $0.1 }
    }

    func move(_ d: Int) {
        let n = rows.count
        guard n > 0 else { return }
        selected = (selected + d + n) % n
    }

    func commitSelected() -> Commit {
        let r = rows
        guard selected >= 0, selected < r.count else { return .stay }
        switch r[selected] {
        case .window(let w):           onPluckWindow(w.wid); return .stay
        case .group(let g):            onPluckGroup(g.cid);  return .stay
        case .layer(let l):            onRecallLayer(l.lid); return .stay
        case .tile(_, let p):          onTile(p);            return .close
        case .saveLayer:               onSaveLayer();        return .close
        case .command(_, _, let fill): query = fill;         return .stay
        }
    }

    // MARK: scoring
    private func arg(_ q: String, _ tokens: [String]) -> String {
        for t in tokens where q.hasPrefix(t) {
            return String(q.dropFirst(t.count)).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
    private func score(_ hay: String, _ q: String) -> Int? {
        let h = hay.lowercased()
        if q.isEmpty { return 0 }
        if h == q { return 100 }
        if h.hasPrefix(q) { return 60 }
        if h.contains(q) { return 30 }
        return nil
    }
    private func best(_ fields: [String], _ q: String) -> Int? { fields.compactMap { score($0, q) }.max() }
    private func labelOf(_ row: Row) -> String { if case .command(let l, _, _) = row { return l }; return "" }
}

// MARK: - HyperspaceCommandView

struct HyperspaceCommandView: View {
    @ObservedObject var model: HyperspaceCommandModel
    var onActivate: (Int) -> Void
    var onDismiss: () -> Void
    @FocusState private var focused: Bool

    private let radius: CGFloat = 14

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }           // click-away closes; survey stays visible
            card.frame(width: 580).padding(.bottom, 90)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focused = true                               // assert focus only once the panel is key
        }
    }

    // Results sit ABOVE the input (the bar lives at the bottom of the screen); same
    // carbon card / cyan rim as the main command bar so they read as one surface.
    private var card: some View {
        let rows = model.rows
        return VStack(spacing: 0) {
            if !rows.isEmpty {
                VStack(spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        rowView(row, selected: i == model.selected)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(i) }
                    }
                }
                .padding(.vertical, 5)
                Rectangle().fill(Palette.border).frame(height: 0.5)
            }
            inputRow
        }
        .background(cardTexture)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(borderGradient, lineWidth: 0.75))
        .overlay(alignment: .top) { topRim }
        .shadow(color: Color.black.opacity(0.5), radius: 22, y: 10)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium)).foregroundColor(Palette.textMuted).frame(width: 20)
            TextField("Search windows, groups, layers   ·   /tile  /group  /layer", text: $model.query)
                .textFieldStyle(.plain)
                .font(Typo.mono(14)).foregroundColor(Palette.text)
                .focused($focused)
                .onExitCommand(perform: onDismiss)
            if !model.pluckedOrder.isEmpty {
                Text("\(model.pluckedOrder.count) selected")
                    .font(Typo.mono(9)).foregroundColor(HUDChrome.cyan.opacity(0.9))
            }
            Text("esc").font(Typo.mono(9)).foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background(LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.012)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func rowView(_ row: HyperspaceCommandModel.Row, selected: Bool) -> some View {
        let plucked = isPlucked(row)
        let lit = selected || plucked
        let accent: Color = selected ? HUDChrome.cyan : (plucked ? HUDChrome.cyan.opacity(0.85) : tint(row))
        return HStack(spacing: 11) {
            Image(systemName: icon(row))
                .font(.system(size: 11, weight: .medium)).foregroundColor(accent).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(row)).font(Typo.mono(12))
                    .foregroundColor(lit ? Palette.text : Palette.textDim).lineLimit(1)
                if let m = meta(row) {
                    Text(m).font(Typo.mono(10)).foregroundColor(Palette.textMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing(row, selected: selected)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(rowBackground(selected: selected, plucked: plucked))
    }

    // Cursor row → bright cyan wash + solid leading bar; a selected-but-not-cursor row
    // → a quieter persistent cyan tint + dim bar, so the selected set stays legible
    // at a glance (the layer-preview pop, not a green glow).
    @ViewBuilder private func rowBackground(selected: Bool, plucked: Bool) -> some View {
        ZStack(alignment: .leading) {
            if selected { HUDChrome.cyan.opacity(0.14) }
            else if plucked { HUDChrome.cyan.opacity(0.06) }
            else { Color.clear }
            if selected { Rectangle().fill(HUDChrome.cyan).frame(width: 2) }
            else if plucked { Rectangle().fill(HUDChrome.cyan.opacity(0.45)).frame(width: 2) }
        }
    }

    @ViewBuilder private func trailing(_ row: HyperspaceCommandModel.Row, selected: Bool) -> some View {
        switch row {
        case .window(let w):
            if let s = model.slot(of: w.wid) { slotBadge("\(s)") } else { keyHint("⏎ select", selected) }
        case .group(let g): countOrHint(model.pluckedCount(g.members), g.members.count, selected)
        case .layer(let l): countOrHint(model.pluckedCount(l.members), l.members.count, selected)
        case .tile:       keyHint("⏎ stage", selected)
        case .saveLayer:  keyHint("⏎ save", selected)
        case .command:    keyHint("⏎", selected)
        }
    }

    @ViewBuilder private func countOrHint(_ picked: Int, _ total: Int, _ selected: Bool) -> some View {
        if picked > 0 { slotBadge("\(picked)/\(total)", full: picked >= total && total > 0) }
        else { keyHint("⏎ select", selected) }
    }

    private func slotBadge(_ text: String, full: Bool = true) -> some View {
        Text(text)
            .font(Typo.monoBold(9)).foregroundColor(full ? HUDChrome.onSignal : HUDChrome.cyan)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(full ? HUDChrome.cyan : HUDChrome.cyan.opacity(0.16)))
    }

    private func keyHint(_ text: String, _ selected: Bool) -> some View {
        Text(text).font(Typo.mono(9)).foregroundColor(selected ? HUDChrome.cyan.opacity(0.8) : Palette.textMuted)
    }

    private func isPlucked(_ row: HyperspaceCommandModel.Row) -> Bool {
        switch row {
        case .window(let w): return model.slot(of: w.wid) != nil
        case .group(let g):  return model.pluckedCount(g.members) > 0
        case .layer(let l):  return model.pluckedCount(l.members) > 0
        default:             return false
        }
    }

    // MARK: chrome (ported from the main command bar so the two match)
    private var cardTexture: some View {
        ZStack {
            LinearGradient(colors: [HUDChrome.baseTop, HUDChrome.baseBottom], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [HUDChrome.cyan.opacity(0.06), .clear, HUDChrome.rose.opacity(0.035)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
        }
    }
    private var borderGradient: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
    }
    private var topRim: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: Color.white.opacity(0.5), location: 0.28),
            .init(color: HUDChrome.cyan.opacity(0.38), location: 0.5),
            .init(color: Color.white.opacity(0.5), location: 0.72),
            .init(color: .clear, location: 1.0),
        ], startPoint: .leading, endPoint: .trailing)
        .frame(height: 1).blur(radius: 0.4)
    }

    // MARK: row presentation
    private func icon(_ r: HyperspaceCommandModel.Row) -> String {
        switch r {
        case .window:    return "macwindow"
        case .group:     return "square.grid.2x2"
        case .layer:     return "square.stack.3d.up"
        case .tile:      return "rectangle.righthalf.inset.filled"
        case .saveLayer: return "plus.square.on.square"
        case .command:   return "slash.circle"
        }
    }
    private func tint(_ r: HyperspaceCommandModel.Row) -> Color {
        switch r {
        case .group, .layer, .saveLayer: return HUDChrome.cyan.opacity(0.7)
        default:                          return Palette.textDim
        }
    }
    private func title(_ r: HyperspaceCommandModel.Row) -> String {
        switch r {
        case .window(let w):        return w.title
        case .group(let g):         return g.name
        case .layer(let l):         return l.name
        case .tile(let n, _):       return n
        case .saveLayer:            return "Save the selection as a layer"
        case .command(let l, _, _): return l
        }
    }
    private func meta(_ r: HyperspaceCommandModel.Row) -> String? {
        switch r {
        case .window(let w): return w.app
        case .group(let g):  return g.hint.isEmpty ? "\(g.members.count)" : "⇧\(g.hint) · \(g.members.count)"
        case .layer(let l):  return "\(l.members.count) here"
        case .tile:          return nil
        case .saveLayer:     return nil
        case .command(_, let d, _): return d
        }
    }
}

// MARK: - HyperspaceCommandPanel

final class HyperspaceCommandPanel: NSPanel {
    private let model: HyperspaceCommandModel
    private let onClose: () -> Void
    private var monitor: Any?

    init(model: HyperspaceCommandModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)   // above the survey panels
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        let view = HyperspaceCommandView(
            model: model,
            onActivate: { [weak self] i in self?.activate(i) },
            onDismiss:  { [weak self] in self?.onClose() })
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var canBecomeKey: Bool { true }

    func present(on screen: NSScreen) {
        setFrame(screen.frame, display: true)
        model.refreshPluck()                 // reflect anything already selected
        installMonitor()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        super.close()
    }

    /// Run the highlighted row's action and decide whether the bar stays up.
    private func activate(_ index: Int) {
        model.selected = index
        switch model.commitSelected() {
        case .close: onClose()
        case .stay:  model.refreshPluck()    // show the new slot / count immediately
        }
    }

    // Local monitor so ↑↓/⏎/Esc drive the list before the focused TextField sees
    // them (typing still falls through). Mirrors the survey's own monitor pattern.
    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.isKeyWindow else { return e }
            switch e.keyCode {
            case 53:     self.onClose(); return nil                       // Esc
            case 126:    self.model.move(-1); return nil                  // ↑
            case 125:    self.model.move(1); return nil                   // ↓
            case 36, 76: self.activate(self.model.selected); return nil   // ⏎ / keypad Enter
            default:     return e
            }
        }
    }
}
