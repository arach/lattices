import AppKit

/// A design projection, not an execution plan. The layout algorithm is shared;
/// desktop/AX eligibility changes the explanation, never the designed slots.
extension EditorGeometry {
    func layout(_ layer: Layer, members: [LayerMembership.Member], entryKeys: [String],
                ambiguousKeys: Set<String>) -> [String: Any]? {
        guard let main = displays.first(where: { $0.displayId == mainID }),
              let visible = visibleFrame, !(Self.frame(visible) is NSNull) else { return nil }
        let kind = layer.layout.flatMap(LayerLayout.Kind.init)
        guard layer.layout == nil || layer.layout?.lowercased() == "none" || kind != nil else { return nil }
        let aspect = visible.width / visible.height
        var skipped: [[String: Any]] = []
        func skip(_ index: Int, _ reason: String) {
            skipped.append(["entryIndex": index, "entryKey": entryKeys[index], "reason": reason])
        }
        func identity(_ index: Int) -> [String: Any] {
            ["entryIndex": index, "entryKey": entryKeys[index],
             "ambiguous": ambiguousKeys.contains(entryKeys[index])]
        }
        func rect(_ fractions: (CGFloat, CGFloat, CGFloat, CGFloat)) -> CGRect {
            CGRect(x: fractions.0, y: fractions.1, width: fractions.2, height: fractions.3)
        }
        func unit(_ frame: CGRect, on display: CGRect) -> CGRect {
            CGRect(x: (frame.minX - display.minX) / display.width,
                   y: (frame.minY - display.minY) / display.height,
                   width: frame.width / display.width, height: frame.height / display.height)
        }
        // Explicit tile coordinates use the same parser/preset snapshot as a
        // switch. A display-only entry has no designed size: preserve its actual
        // position when known, rather than inventing a full-screen destination.
        func fixed(_ project: LayerProject, current: OverviewRow?) -> (CGRect, UInt32)? {
            if let tile = project.tile {
                guard let placement = placements[tile] ?? PlacementSpec(string: tile) else { return nil }
                let index = project.display ?? 0
                guard let display = displays.first(where: { $0.index == index }) ?? displays.first,
                      visibleFrames[display.displayId] != nil else { return nil }
                return (rect(placement.fractions), display.displayId)
            }
            guard let current, let frame = current.frame,
                  let display = displays.first(where: { $0.index == current.display }),
                  let visible = visibleFrames[display.displayId], !(Self.frame(visible) is NSNull) else { return nil }
            return (unit(frame, on: visible), display.displayId)
        }
        func target(_ index: Int, box: CGRect, display: UInt32) -> [String: Any] {
            var result = identity(index)
            result["unitFrame"] = Self.frame(box)
            result["displayId"] = String(display)
            if let visible = visibleFrames[display] {
                result["frame"] = Self.frame(WindowTiler.tileFrame(
                    fractions: (box.minX, box.minY, box.width, box.height), inDisplay: visible))
            }
            return result
        }
        let automatic = members.filter { !$0.placed }
        let openTypes = automatic.map { AppTypeClassifier.classify($0.entry.app) }
        let openBoxes = kind.map { LayerLayout.frames($0, types: openTypes, aspect: aspect) } ?? []
        let openByID = Dictionary(uniqueKeysWithValues: zip(automatic, openBoxes).map { ($0.0.entry.wid, $0.1) })
        var open: [[String: Any]] = []
        for member in members {
            let window = member.entry, index = member.project
            let current = rows[window.wid]
            let destination: (CGRect, UInt32)? = member.placed
                ? fixed(layer.projects[index], current: current)
                : openByID[window.wid].map { ($0, mainID) }
            var item = identity(index)
            if let (box, display) = destination { item = target(index, box: box, display: display) }
            else { item["unitFrame"] = NSNull(); item["displayId"] = NSNull(); item["frame"] = NSNull() }
            item["windowId"] = window.wid
            var reason: String?
            if kind == nil && !member.placed { reason = "no layout" }
            else if destination == nil { reason = "explicit placement unavailable" }
            else if tucked[layer.id]?.contains(window.wid) == true { reason = "tucked away" }
            else if let display = current?.display,
                    displays.first(where: { $0.index == display })?.displayId != mainID { reason = "on another display" }
            else if main.currentSpaceId <= 0 { reason = "no live desktop" }
            else if !window.spaceIds.contains(main.currentSpaceId) { reason = "on another desktop" }
            else if current?.position != .live { reason = "no live position" }
            else if !standardWindows.contains(window.wid) { reason = "not a standard window" }
            else if member.placed { reason = "explicit placement; excluded from automatic layout" }
            if let reason { item["status"] = "wontMove"; item["reason"] = reason }
            else if let (box, display) = destination, let visible = visibleFrames[display], let frame = current?.frame {
                let expected = WindowTiler.tileFrame(fractions: (box.minX, box.minY, box.width, box.height), inDisplay: visible)
                let delta = [frame.minX - expected.minX, frame.minY - expected.minY,
                             frame.maxX - expected.maxX, frame.maxY - expected.maxY]
                item["status"] = delta.allSatisfy { abs($0) <= 3 } ? "stays" : "moves"
            } else { item["status"] = "wontMove"; item["reason"] = "no live position" }
            open.append(item)
        }
        var allIndices: [Int] = [], allTypes: [AppType] = []
        var all: [[String: Any]] = []
        for (index, project) in layer.projects.enumerated() {
            guard !ambiguousKeys.contains(entryKeys[index]) else { skip(index, "ambiguous duplicate entry"); continue }
            let app = [project.app, project.match?.appEquals, project.match?.app]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            guard let app else { skip(index, "no app name"); continue }
            if project.tile != nil || project.display != nil {
                if let (box, display) = fixed(project, current: members.first(where: { $0.project == index }).flatMap { rows[$0.entry.wid] }) {
                    all.append(target(index, box: box, display: display))
                } else { skip(index, "explicit placement unavailable") }
            } else if kind != nil {
                allIndices.append(index); allTypes.append(AppTypeClassifier.classify(app))
            }
        }
        let allBoxes = kind.map { LayerLayout.frames($0, types: allTypes, aspect: aspect) } ?? []
        all += zip(allIndices, allBoxes).map { target($0.0, box: $0.1, display: mainID) }
        all.sort { ($0["entryIndex"] as! Int) < ($1["entryIndex"] as! Int) }
        return ["kind": kind?.name ?? "none", "displayId": String(mainID), "visibleFrame": Self.frame(visible),
                "lanes": ["open": Self.layoutLanes(kind, types: openTypes, boxes: openBoxes, aspect: aspect),
                          "all": Self.layoutLanes(kind, types: allTypes, boxes: allBoxes, aspect: aspect)],
                "openTargets": open, "allTargets": all, "skipped": skipped]
    }

    /// Ruler extents are unions of the actual algorithm's rectangles. No second
    /// copy of lane-width/column/stack arithmetic is maintained by the bridge.
    static func layoutLanes(_ kind: LayerLayout.Kind?, types: [AppType], boxes: [CGRect], aspect: CGFloat) -> [[String: Any]] {
        guard !boxes.isEmpty else { return [] }
        if kind == .auto && aspect >= LayerLayout.ultrawide {
            let used = LayerLayout.Lane.allCases.filter { lane in types.contains { LayerLayout.lane(for: $0) == lane } }
            if used.count > 1 {
                return used.map { lane in
                    let frames = zip(types, boxes).filter { LayerLayout.lane(for: $0.0) == lane }.map(\.1)
                    let area = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
                    let label = lane == .left ? "Terminals & chat" : lane == .middle ? "Editors & design" : "Other apps"
                    return ["x": area.minX, "w": area.width, "label": label]
                }
            }
        }
        var spans: [CGRect] = []
        for box in boxes.sorted(by: { $0.minX < $1.minX }) where !spans.contains(where: { $0.minX == box.minX && $0.width == box.width }) {
            spans.append(box)
        }
        return spans.enumerated().map { index, box in
            let label: String
            if spans.count == 2 && (kind == .masterStack || (kind == .auto && aspect < LayerLayout.ultrawide)) {
                label = index == 0 ? "Main" : "Stack"
            } else { label = "Column \(index + 1)" }
            return ["x": box.minX, "w": box.width, "label": label]
        }
    }
}
