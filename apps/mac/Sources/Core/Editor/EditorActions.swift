import Foundation
import CoreFoundation

/// The only Editor capability that may invoke effects. Planning is pure and a
/// confirmation consumes its opaque token before checking freshness or executing.
final class EditorActions {
    struct Operation {
        let kind: String
        let layerId: String
        let entryIndices: [Int]
        let mode: String
    }
    struct Plan {
        let id: String
        let expires: Date
        let revision: String
        let snapshotId: String
        let operation: Operation
        let payload: [String: Any]
    }
    private var pending: Plan?
    private var receipts: [[String: Any]] = []
    private var journals: [String: EditorMutationJournal] = [:]
    private var undone = Set<String>()
    private let journalFactory: (() -> EditorMutationJournal)?
    var supportsUndo: Bool { journalFactory != nil }
    private let now: () -> Date
    private let execute: (Operation) throws -> [String: Any]
    private let reveal: () throws -> [String: Any]
    init(now: @escaping () -> Date = Date.init,
         execute: @escaping (Operation) throws -> [String: Any],
         reveal: @escaping () throws -> [String: Any],
         journalFactory: (() -> EditorMutationJournal)? = nil) {
        self.journalFactory = journalFactory
        self.now = now; self.execute = execute; self.reveal = reveal
    }

    func plan(_ payload: [String: Any], snapshot: EditorBridge.Snapshot) throws -> [String: Any] {
        guard let kind = payload["kind"] as? String, ["gather", "open"].contains(kind),
              let layerId = payload["layerId"] as? String,
              let layer = snapshot.subject.layers.first(where: { $0.id == layerId }),
              let group = (snapshot.projection["groups"] as? [[String: Any]])?.first(where: { $0["id"] as? String == layerId }),
              let snapshotId = snapshot.projection["snapshotId"] as? String else {
            throw EditorBridgeError("invalid_request", "Choose a configured layer and a supported action.")
        }
        var selected: Int?
        if let raw = payload["entryIndex"], !(raw is NSNull) {
            guard kind == "open", let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let index = raw as? Int, layer.projects.indices.contains(index) else {
                throw EditorBridgeError("invalid_request", "Invalid entry index.")
            }
            selected = index
        }
        let rows = group["rows"] as? [[String: Any]] ?? []
        // Keys/ranges come from the exact displayed source, including unknown
        // project fields. Never reconstruct identity by encoding LayerProject.
        let records = snapshot.subject.entries.filter { $0["layerId"] as? String == layerId }
        let ordered = records.flatMap { record in
            (record["ranges"] as? [[String: Int]] ?? []).map { (record, $0["from"] ?? 0) }
        }.sorted { $0.1 < $1.1 }.map(\.0)
        let held = Set(rows.flatMap { $0["entryKeys"] as? [String] ?? [] })
        var entries: [[String: Any]] = []
        var indices: [Int] = []
        for (index, project) in layer.projects.enumerated() where selected == nil || selected == index {
            guard ordered.indices.contains(index), let key = ordered[index]["key"] as? String,
                  ordered[index]["ambiguous"] as? Bool != true, !held.contains(key) else { continue }
            var entry: [String: Any] = ["entryIndex": index, "entryKey": key, "app": (project.app ?? project.match?.appEquals ?? project.match?.app) as Any? ?? NSNull()]
            if let url = project.url, !url.isEmpty { entry["method"] = "url"; entry["value"] = url }
            else if let app = project.launch ?? project.app ?? project.match?.appEquals ?? project.match?.app, !app.isEmpty {
                entry["method"] = "app"; entry["value"] = app
            } else if let path = project.path {
                entry["method"] = "command"; entry["value"] = "lattices start"; entry["cwd"] = path
            } else { continue }
            entry["description"] = "Open " + (entry["value"] as? String ?? "entry")
            entries.append(entry); indices.append(index)
        }
        if kind == "open" && entries.isEmpty {
            throw EditorBridgeError("unavailable", "No unambiguous missing entry has an opening method.")
        }
        let id = UUID().uuidString, expires = now().addingTimeInterval(60)
        let targets = (group["layout"] as? [String: Any])?["openTargets"] as? [[String: Any]] ?? []
        let displays = snapshot.projection["displays"] as? [[String: Any]] ?? []
        let summary: [String: Any] = ["planId": id, "kind": kind, "layerId": layerId, "layerName": layer.label,
            "expiresAt": ISO8601DateFormatter().string(from: expires),
            "explanation": kind == "open" ? "Open only these missing entries. Existing windows stay where they are." : "Focus this layer: put away outside windows and arrange its windows.",
            "shortcut": kind == "gather" ? "⌘⌥ layer switch" : NSNull(),
            "layoutCount": kind == "open" ? 0 : targets.filter { $0["status"] as? String == "moves" }.count,
            "putAwayCount": kind == "open" ? 0 : NSNull(), "displaysLeftAlone": displays.filter { kind == "open" || $0["main"] as? Bool != true }.map {
                ["id": $0["id"] ?? NSNull(), "name": $0["name"] ?? NSNull()]
            }, "entries": kind == "open" ? entries : [],
            "warnings": kind == "open" ? ["Only the listed missing entries will be opened. No layer switch or staging."] : ["Gather puts away windows outside this layer and lays out its windows.", "The exact number of windows put away is unknown."]]
        pending = Plan(id: id, expires: expires, revision: snapshot.subject.revision, snapshotId: snapshotId,
            operation: Operation(kind: kind, layerId: layerId, entryIndices: kind == "open" ? indices : [],
                                 mode: kind == "gather" ? "focus" : "launch"), payload: summary)
        return summary
    }

    func confirm(_ id: String, snapshot: () throws -> EditorBridge.Snapshot) -> [String: Any] {
        let layerId = pending?.id == id ? pending?.operation.layerId : nil
        let kind = pending?.id == id ? pending!.operation.kind : "gather"
        var journal: EditorMutationJournal?
        do {
            guard let plan = pending, plan.id == id else { throw EditorBridgeError("invalid_plan", "A fresh confirmation plan is required.") }
            pending = nil // Burn before every failure, including stale inventory and executor errors.
            guard now() < plan.expires else { throw EditorBridgeError("expired_plan", "This plan expired. Review a new plan.") }
            let current = try snapshot()
            guard current.subject.revision == plan.revision,
                  current.projection["snapshotId"] as? String == plan.snapshotId else {
                throw EditorBridgeError("stale_plan", "The workspace or windows changed. Review a new plan.")
            }
            journal = journalFactory?()
            let counts = try journal.map { try $0.run { try execute(plan.operation) } } ?? execute(plan.operation)
            return receipt(planId: id, layerId: layerId, kind: kind, ok: true, counts: counts, journal: journal)
        } catch {
            let failure = error as? EditorBridgeError ?? EditorBridgeError("action_failed", error.localizedDescription)
            return receipt(planId: id, layerId: layerId, kind: kind, ok: false, counts: [:], journal: journal, error: failure)
        }
    }

    private var newestUndoable: String? {
        receipts.compactMap { $0["actionId"] as? String }.first { journals[$0] != nil && !undone.contains($0) }
    }

    func history() -> [String: Any] {
        ["actions": receipts.map { receipt in
            var value = receipt
            let id = value["actionId"] as? String ?? ""
            value["undoable"] = journals[id] != nil && !undone.contains(id)
            return value
        }, "newestUndoableActionId": newestUndoable as Any? ?? NSNull()]
    }

    private func receipt(planId: String?, layerId: String?, kind: String, ok: Bool, counts: [String: Any],
                         journal: EditorMutationJournal? = nil, error: EditorBridgeError? = nil) -> [String: Any] {
        let message = error?.message ?? (kind == "open"
            ? "Requested opening the confirmed missing entries. Opened apps stay open."
            : kind == "reveal" ? "Restored available parked windows and hidden apps."
            : "Gathered the layer. Review the refreshed windows for the outcome.")
        let id = UUID().uuidString
        var value: [String: Any] = ["actionId": id, "planId": planId as Any? ?? NSNull(), "kind": kind,
            "layerId": layerId as Any? ?? NSNull(), "ok": ok, "at": ISO8601DateFormatter().string(from: now()),
            "message": message, "label": kind.capitalized, "counts": counts, "undoable": journal != nil]
        if let error { value["error"] = ["code": error.code, "message": error.message] }
        if let journal {
            journals[id] = journal
            receipts.insert(value, at: 0)
            receipts = Array(receipts.prefix(10))
            let retained = Set(receipts.compactMap { $0["actionId"] as? String })
            journals = journals.filter { retained.contains($0.key) }
            undone.formIntersection(retained)
        }
        return value
    }

    func undo(_ id: String) -> [String: Any] {
        let receiptId = UUID().uuidString
        let original = receipts.first { $0["actionId"] as? String == id }
        var value: [String: Any] = ["actionId": receiptId, "undoOfActionId": id, "planId": NSNull(),
            "kind": "undo", "layerId": original?["layerId"] ?? NSNull(),
            "at": ISO8601DateFormatter().string(from: now()), "undoable": false]
        guard newestUndoable == id, let journal = journals[id] else {
            value.merge(["ok": false, "message": "Undo the newest action first.", "counts": [:],
                         "error": ["code": "undo_order", "message": "Undo the newest action first."]]) { _, n in n }
            return value
        }
        journal.seal() // Also cancels any deferred parking verification for this action.
        undone.insert(id)
        let opened = original?["kind"] as? String == "open"
        let stack = EditorUndo()
        stack.record(.init(actionId: id, label: original?["label"] as? String ?? "Action",
                           at: now(), opened: opened, moves: journal.moves))
        do {
            let result = try stack.undo(id, environment: journal.environment())
            value["ok"] = true
            value["counts"] = ["restored": result.restored, "skipped": result.skipped.count]
            value["reasons"] = result.skipped
            value["message"] = "Undid " + (original?["kind"] as? String ?? "action")
                + " · restored \(result.restored), skipped \(result.skipped.count)."
                + (opened ? " Opened apps stay open." : "")
        } catch {
            value["ok"] = false; value["counts"] = [:]
            value["message"] = error.localizedDescription
            value["error"] = ["code": "undo_failed", "message": error.localizedDescription]
        }
        return value
    }

    func showAll() -> [String: Any] {
        // Reveal remains an escape hatch. Its inverses may put windows away,
        // so it is not added to the user-approved restore-only Undo stack.
        do { return receipt(planId: nil, layerId: nil, kind: "reveal", ok: true, counts: try reveal()) }
        catch { return receipt(planId: nil, layerId: nil, kind: "reveal", ok: false, counts: [:],
                               error: EditorBridgeError("action_failed", error.localizedDescription)) }
    }
}
