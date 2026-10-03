import Foundation
import CryptoKit

/// Immutable read of the layers subtree. No WorkspaceManager mutation or writer
/// is reachable from this adapter. Unknown fields survive in source and identity.
struct EditorSubject {
    static let id = "workspace-layers"
    let revision: String
    let source: String
    let layers: [Layer]
    let groups: [TabGroup]
    let entries: [[String: Any]]
    private let entryKeys: [[String]]

    static func canonical(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value,
            options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
    }

    static func hash(_ text: String) -> String {
        "sha256:" + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EditorBridgeError("unavailable", "Workspace configuration must be a JSON object.")
        }
        let rawLayers: [[String: Any]]
        if let value = root["layers"], !(value is NSNull) {
            guard let array = value as? [[String: Any]] else {
                throw EditorBridgeError("unavailable", "Workspace layers must be an array of objects.")
            }
            rawLayers = array
        } else { rawLayers = [] }
        let decoder = JSONDecoder()
        layers = try decoder.decode([Layer].self, from: JSONSerialization.data(withJSONObject: rawLayers))
        let rawGroups = root["groups"].flatMap { $0 is NSNull ? nil : $0 } ?? [Any]()
        groups = try decoder.decode([TabGroup].self,
            from: JSONSerialization.data(withJSONObject: rawGroups, options: .fragmentsAllowed))
        guard Set(layers.map(\.id)).count == layers.count else {
            throw EditorBridgeError("unavailable", "Duplicate layer IDs make this workspace ambiguous.")
        }
        let subset: [String: Any] = ["kind": Self.id, "version": 1, "layers": rawLayers]
        revision = Self.hash(try Self.canonical(subset))
        var records: [String: [String: Any]] = [:]
        var keys: [[String]] = []
        for (index, raw) in rawLayers.enumerated() {
            var layerKeys: [String] = []
            for entry in (raw["projects"] as? [[String: Any]]) ?? [] {
                let canonical = try Self.canonical(entry)
                let key = Self.hash(try Self.canonical(["layerId": layers[index].id, "content": entry]))
                layerKeys.append(key)
                records[key] = ["key": key, "layerId": layers[index].id, "canonical": canonical,
                                "ranges": [[String: Int]](), "ambiguous": false]
            }
            keys.append(layerKeys)
        }
        // Emit the exact displayed text and record offsets during traversal. A
        // text search would confuse nested lookalikes, escapes, or duplicates.
        var text = ""
        var offset = 0
        func append(_ part: String) { text += part; offset += part.utf16.count }
        func emit(_ value: Any, path: [String], depth: Int) throws {
            let start = offset
            if let object = value as? [String: Any] {
                let names = object.keys.sorted()
                append(names.isEmpty ? "{}" : "{\n")
                for (i, name) in names.enumerated() {
                    append(String(repeating: "  ", count: depth + 1))
                    append(try Self.canonical(name)); append(": ")
                    try emit(object[name]!, path: path + [name], depth: depth + 1)
                    append(i == names.count - 1 ? "\n" : ",\n")
                }
                if !names.isEmpty { append(String(repeating: "  ", count: depth) + "}") }
            } else if let array = value as? [Any] {
                append(array.isEmpty ? "[]" : "[\n")
                for (i, item) in array.enumerated() {
                    append(String(repeating: "  ", count: depth + 1))
                    try emit(item, path: path + [String(i)], depth: depth + 1)
                    append(i == array.count - 1 ? "\n" : ",\n")
                }
                if !array.isEmpty { append(String(repeating: "  ", count: depth) + "]") }
            } else { append(try Self.canonical(value)) }
            if path.count == 4, path[0] == "layers", path[2] == "projects",
               let l = Int(path[1]), let p = Int(path[3]) {
                let key = keys[l][p]
                var ranges = records[key]!["ranges"] as! [[String: Int]]
                ranges.append(["from": start, "to": offset])
                records[key]!["ranges"] = ranges
                records[key]!["ambiguous"] = ranges.count > 1
            }
        }
        try emit(subset, path: [], depth: 0)
        source = text + "\n"
        entryKeys = keys
        entries = records.keys.sorted().compactMap { records[$0] }
    }

    var descriptor: [String: Any] {
        ["id": Self.id, "kind": "lattices.workspace-layers", "label": "Workspace Layers", "revision": revision]
    }

    /// The only membership decision is the native resolver. Its index is used
    /// only to locate the already content-addressed entry in this same snapshot.
    func project(windows: [WindowEntry], sources: LayerMembership.Sources, geometry: EditorGeometry? = nil) throws -> [String: Any] {
        let resolution = LayerMembership.resolve(layers, windows: windows, sources: sources)
        let ambiguousKeys = Set(entries.filter { $0["ambiguous"] as? Bool == true }.compactMap { $0["key"] as? String })
        func row(_ window: WindowEntry, layerId: String?, key: String?, rule: Int? = nil) -> [String: Any] {
            var value: [String: Any] = ["id": "window:\(window.wid)", "windowId": window.wid, "app": window.app,
             "title": window.title, "layerId": layerId as Any? ?? NSNull(),
             "entryKeys": key.map { [$0] } ?? [],
             "matchedRule": (key.map { ambiguousKeys.contains($0) } == true ? nil : rule) as Any? ?? NSNull()]
            if let geometry { value.merge(geometry.window(window.wid)) { _, next in next } }
            return value
        }
        var projected: [[String: Any]] = layers.enumerated().map { i, layer in
            var group: [String: Any] = ["id": layer.id, "label": layer.label, "rows": resolution.layers[i].map { member in
                row(member.entry, layerId: layer.id, key: entryKeys[i][member.project], rule: member.project)
            }]
            if let preview = geometry?.preview(layer, members: resolution.layers[i]) { group["preview"] = preview }
            return group
        }
        var seen = Set<UInt32>()
        let unassigned = windows.sorted { ($0.zIndex, $0.wid) < ($1.zIndex, $1.wid) }.filter {
            sources.isContent($0) && resolution.owners[$0.wid] == nil && seen.insert($0.wid).inserted
        }
        // Reserved group identifier cannot collide with a user layer ID.
        var unassignedID = "__unassigned__"
        while layers.contains(where: { $0.id == unassignedID }) { unassignedID += "_" }
        projected.append(["id": unassignedID, "label": "Unassigned",
                          "rows": unassigned.map { row($0, layerId: nil, key: nil) }])
        var body: [String: Any] = ["groups": projected, "entries": entries]
        if let geometry { body["displays"] = geometry.wireDisplays }
        return body.merging(["snapshotId": Self.hash(try Self.canonical(body))]) { _, new in new }
    }
}

struct EditorBridgeError: Error {
    let code: String
    let message: String
    init(_ code: String, _ message: String) { self.code = code; self.message = message }
}
