import AppKit
import SwiftUI

/// Pointer zones share the same PlacementSpec geometry as the tile buttons.
enum OverviewSnap: String, Codable, CaseIterable {
    case left, right, full, leftThird, middleThird, rightThird
    var placement: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .full: return "maximize"
        case .leftThird: return "left-third"
        case .middleThird: return "center-third"
        case .rightThird: return "right-third"
        }
    }
    var label: String {
        switch self {
        case .left: return "left half"
        case .right: return "right half"
        case .full: return "full"
        case .leftThird: return "left third"
        case .middleThird: return "middle third"
        case .rightThird: return "right third"
        }
    }
    var fractions: CGRect {
        guard let f = PlacementSpec(string: placement)?.fractions else { return .zero }
        return CGRect(x: f.0, y: f.1, width: f.2, height: f.3)
    }
    static func at(_ point: CGPoint, in size: CGSize) -> Self? {
        guard size.width > 0, size.height > 0, point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }
        let x = point.x / size.width, y = point.y / size.height
        if y < 0.2 { return .full }
        if y >= 0.65 { return x < 1 / 3 ? .leftThird : x < 2 / 3 ? .middleThird : .rightThird }
        return x < 0.5 ? .left : .right
    }
}

struct OverviewDeskPreferences: Codable, Equatable {
    var pinned: UInt32?
    var hidden: Set<UInt32> = []
    /// Optional so existing v1 preferences decode without losing pin/hide data.
    var revealed: Set<UInt32>? = nil
    var toolbar: [String: CGPoint] = [:]
    var lastToolbar: CGPoint?
    static let key = "overview.desk.preferences.v1"
    static func sizeKey(_ size: CGSize) -> String { "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))" }
    static func clamp(_ origin: CGPoint, toolbar: CGSize, room: CGSize) -> CGPoint {
        CGPoint(x: floor(min(max(0, origin.x), max(0, room.width - toolbar.width))),
                y: floor(min(max(0, origin.y), max(0, room.height - toolbar.height))))
    }
    mutating func togglePin(_ id: UInt32) {
        pinned = pinned == id ? nil : id
        hidden.remove(id)
    }
    mutating func hide(_ id: UInt32) {
        hidden.insert(id); revealed?.remove(id); if pinned == id { pinned = nil }
    }
    mutating func reveal(_ id: UInt32) {
        hidden.remove(id)
        if revealed == nil { revealed = [] }
        revealed?.insert(id)
    }
    func isExpanded(_ id: UInt32, inactive: Bool) -> Bool {
        !hidden.contains(id) && (!inactive || pinned == id || revealed?.contains(id) == true)
    }
    static func load(_ defaults: UserDefaults) -> Self {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
}

struct OverviewToolbarAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

struct OverviewScreenDrop: ViewModifier {
    @ObservedObject var model: OverviewModel
    let display: OverviewDisplay
    let spaceId: Int
    var mapSize: CGSize? = nil
    var preview: OverviewSnap? = nil
    @State private var targeted = false
    @State private var snap: OverviewSnap?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if targeted || preview != nil {
                    if let size = mapSize, let zone = snap ?? preview {
                        let f = zone.fractions
                        RoundedRectangle(cornerRadius: 5).fill(Palette.running.opacity(0.23))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.running, lineWidth: 2))
                            .frame(width: size.width * f.width, height: size.height * f.height)
                            .offset(x: size.width * f.minX, y: size.height * f.minY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if targeted || preview != nil {
                    Text(label).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text).padding(6).background(Palette.bg)
                        .fixedSize(horizontal: mapSize == nil, vertical: true)
                        .allowsHitTesting(false)
                }
            }
            .background { if OverviewDragProbe.enabled { OverviewProbeMark(id: "\(mapSize == nil ? "thumb" : "screen"):\(display.displayId):\(spaceId)") } }
            .onDrop(of: [OverviewMembershipDrag.type], delegate: OverviewScreenDropDelegate(
                model: model, display: display, spaceId: spaceId, size: mapSize,
                targeted: $targeted, snap: $snap))
    }
    private var label: String {
        guard let number = display.desktopNumber(of: spaceId) else { return "Full-screen Space cannot accept windows" }
        return "Move to Desktop \(number)" + ((snap ?? preview).map { " · " + $0.label } ?? "")
    }
}

private struct OverviewScreenDropDelegate: DropDelegate {
    let model: OverviewModel
    let display: OverviewDisplay
    let spaceId: Int
    let size: CGSize?
    @Binding var targeted: Bool
    @Binding var snap: OverviewSnap?
    func validateDrop(info: DropInfo) -> Bool { OverviewDragProbe.log("screen-validate"); return info.hasItemsConforming(to: [OverviewMembershipDrag.type]) }
    func dropEntered(info: DropInfo) { targeted = true; update(info) }
    func dropExited(info: DropInfo) { targeted = false; snap = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: model.moving.isEmpty ? .move : .forbidden)
    }
    private func update(_ info: DropInfo) { snap = size.flatMap { OverviewSnap.at(info.location, in: $0) } }
    func performDrop(info: DropInfo) -> Bool {
        OverviewDragProbe.log("screen-performDrop display=\(display.displayId) target=\(spaceId) kind=\(size == nil ? "thumbnail" : "map") busy=\(!model.moving.isEmpty)")
        let zone = size.flatMap { OverviewSnap.at(info.location, in: $0) }
        targeted = false; snap = nil
        guard model.moving.isEmpty else { return false }
        guard let destination = OverviewWindowDrop.destination(on: display, spaceId: spaceId) else {
            model.rejectMove("Full-screen Spaces cannot accept windows. Drop on an ordinary Desktop.")
            return false
        }
        guard size == nil || zone != nil else { return false }
        return OverviewMembershipDrag.receive(info.itemProviders(for: [OverviewMembershipDrag.type])) {
            model.moveDragged($0, to: destination, snap: zone)
        }
    }
}
