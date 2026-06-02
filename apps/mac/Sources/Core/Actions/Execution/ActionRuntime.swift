import AppKit
import ApplicationServices
import Foundation

final class ActionRuntime {
    static let shared = ActionRuntime()

    private let history = ActionHistoryStore(limit: 50)

    func execute(params: JSON?) throws -> JSON {
        guard case .object(let root) = params else {
            throw RouterError.missingParam("type")
        }

        if let actions = root["actions"]?.arrayValue {
            return try executeBatch(root: root, actions: actions)
        }

        let action = root["action"] ?? params
        return try executeOne(action: action, root: params)
    }

    func history(params: JSON?) -> JSON {
        history.list(params: params)
    }

    func undo(params: JSON?) throws -> JSON {
        let receipts = try selectUndoReceipts(params: params)
        let receipt = try executeUndo(receipts: receipts, params: params)
        let status = receipt["status"]?.stringValue
        let dryRun = receipt["dryRun"]?.boolValue == true
        let undoOf = receipt["undoOf"]?.arrayValue?.compactMap(\.stringValue) ?? []

        if status == "ok", !dryRun {
            history.recordUndo(receipt, undoOf: undoOf)
        } else {
            history.record(receipt)
        }

        return receipt
    }

    func resolveWindowPlace(params: JSON?) throws -> JSON {
        let normalizedParams = try Self.windowPlaceParams(action: params, root: params)
        let placement = PlacementSpec(json: normalizedParams["placement"] ?? normalizedParams["position"])
        let displayIndex = normalizedParams["display"]?.intValue
        var trace: [String] = []
        var events: [JSON] = []

        let resolved = try resolveWindowTarget(params: normalizedParams, trace: &trace, events: &events)
        let screen = onMain {
            Self.resolveTargetScreen(for: resolved.entry, displayIndex: displayIndex)
        }

        var result: [String: JSON] = [
            "ok": .bool(true),
            "target": resolved.json,
            "targetKind": .string(resolved.kind),
            "targetResolution": .string(resolved.resolution),
            "display": screenJSON(screen, requestedIndex: displayIndex),
            "trace": .array(trace.map { .string($0) }),
            "events": .array(events),
        ]

        if let wid = resolved.wid { result["wid"] = .int(Int(wid)) }
        if let pid = resolved.pid { result["pid"] = .int(Int(pid)) }
        if let app = resolved.app { result["app"] = .string(app) }
        if let title = resolved.title { result["title"] = .string(title) }
        if let session = resolved.session { result["session"] = .string(session) }

        if let placement {
            let targetFrame = onMain {
                WindowTiler.tileFrame(for: placement, on: screen)
            }
            let beforeFrame = resolved.wid.flatMap { Self.cgWindowFrameTopLeft(wid: $0) }
            result["placement"] = placement.jsonValue
            result["plan"] = planJSON(
                target: resolved,
                placement: placement,
                targetFrame: targetFrame,
                beforeFrame: beforeFrame
            )
            result["verificationTolerance"] = .double(Double(Self.verificationTolerance(forApp: resolved.app)))
        }

        return .object(result)
    }

    func executeWindowPlace(params: JSON?, source: String = "daemon", requestId: String? = nil) throws -> JSON {
        let context = ActionInvocationContext(
            requestId: requestId ?? Self.makeId(prefix: "req"),
            actionId: Self.makeId(prefix: "act"),
            source: source,
            compatibilityMethod: nil
        )
        let receipt = try executeWindowPlace(params: params, context: context)
        history.record(receipt)
        return receipt
    }

    private func executeBatch(root: [String: JSON], actions: [JSON]) throws -> JSON {
        let requestId = root["requestId"]?.stringValue ?? Self.makeId(prefix: "req")
        let source = root["source"]?.stringValue ?? "daemon"
        var receipts: [JSON] = []
        var okCount = 0

        for action in actions {
            let context = ActionInvocationContext(
                requestId: requestId,
                actionId: action["id"]?.stringValue ?? Self.makeId(prefix: "act"),
                source: action["source"]?.stringValue ?? source,
                compatibilityMethod: nil
            )
            let receipt = try executeOne(action: action, root: .object(root), context: context)
            receipts.append(receipt)
            if receipt["ok"]?.boolValue == true { okCount += 1 }
        }

        let status: String
        if okCount == actions.count {
            status = "ok"
        } else if okCount > 0 {
            status = "partial"
        } else {
            status = "failed"
        }

        return .object([
            "ok": .bool(status == "ok"),
            "status": .string(status),
            "requestId": .string(requestId),
            "receipts": .array(receipts),
        ])
    }

    private func executeOne(action: JSON?, root: JSON?) throws -> JSON {
        let context = ActionInvocationContext(
            requestId: root?["requestId"]?.stringValue ?? action?["requestId"]?.stringValue ?? Self.makeId(prefix: "req"),
            actionId: action?["id"]?.stringValue ?? Self.makeId(prefix: "act"),
            source: root?["source"]?.stringValue ?? action?["source"]?.stringValue ?? "daemon",
            compatibilityMethod: nil
        )
        return try executeOne(action: action, root: root, context: context)
    }

    private func executeOne(action: JSON?, root: JSON?, context: ActionInvocationContext) throws -> JSON {
        let type = action?["type"]?.stringValue ?? root?["type"]?.stringValue
        guard type == "window.place" else {
            throw RouterError.custom("Unsupported action type: \(type ?? "<missing>")")
        }

        let placeParams = try Self.windowPlaceParams(action: action, root: root)
        let receipt = try executeWindowPlace(params: placeParams, context: context)
        history.record(receipt)
        return receipt
    }

    private func executeWindowPlace(params: JSON?, context: ActionInvocationContext) throws -> JSON {
        guard let placement = PlacementSpec(json: params?["placement"] ?? params?["position"]) else {
            throw RouterError.missingParam("placement")
        }

        let displayIndex = params?["display"]?.intValue
        let dryRun = params?["dryRun"]?.boolValue == true
        var trace: [String] = []
        var events: [JSON] = []

        let resolved = try resolveWindowTarget(params: params, trace: &trace, events: &events)
        let screen = onMain {
            Self.resolveTargetScreen(for: resolved.entry, displayIndex: displayIndex)
        }
        let targetFrame = onMain {
            WindowTiler.tileFrame(for: placement, on: screen)
        }
        let verificationTolerance = Self.verificationTolerance(forApp: resolved.app)

        trace.append("placement \(placement.wireValue)")
        events.append(event("plan.computeFrame", "computed \(placement.wireValue) on \(screen.localizedName)"))

        var beforeFrame: CGRect?
        if let wid = resolved.wid {
            beforeFrame = Self.cgWindowFrameTopLeft(wid: wid)
        }

        var blockedReason: String?
        var requiredPermissions: [String] = []

        if dryRun {
            trace.append("dry run; skipped execution")
            events.append(event("execute.skipped", "dry run requested; no window mutation performed"))
        } else if let wid = resolved.wid, let pid = resolved.pid {
            if !AXIsProcessTrusted() {
                blockedReason = "accessibility-not-trusted"
                requiredPermissions.append("accessibility")
                trace.append("blocked: Accessibility permission required for deterministic window placement")
                events.append(event("execute.blocked", "Accessibility permission required to move wid \(wid)"))
            } else {
                onMain {
                    WindowTiler.tileWindowById(wid: wid, pid: pid, to: placement, on: screen)
                }
                DesktopModel.shared.markInteraction(wid: wid)
                trace.append("executed window move")
                events.append(event("execute.placeWindow", "moved wid \(wid)"))
            }
        } else if let session = resolved.session {
            let terminal = Preferences.shared.terminal
            onMain {
                WindowTiler.tile(session: session, terminal: terminal, to: placement, on: screen)
            }
            trace.append("executed terminal session fallback")
            events.append(event("execute.placeSessionWindow", "placed session \(session) through terminal fallback"))
        }

        let afterFrame = dryRun ? nil : resolved.wid.flatMap { wid in
            Self.waitForWindowFrame(
                wid: wid,
                targetFrame: targetFrame,
                tolerance: verificationTolerance
            )
        }
        let verified = dryRun ? false : (afterFrame.map { Self.framesClose($0, targetFrame, tolerance: verificationTolerance) } ?? false)
        if dryRun {
            trace.append("verification skipped for dry run")
            events.append(event("verify.skipped", "dry run requested; no final frame verification performed"))
        } else if verified {
            trace.append("verified target frame")
            events.append(event("verify.frame", "verified final frame"))
        } else if afterFrame != nil {
            trace.append("verification could not confirm exact target frame")
            events.append(event("verify.frame", "final frame did not match target within tolerance"))
        } else {
            trace.append("verification unavailable")
            events.append(event("verify.frame", "no window id available for verification"))
        }

        let status: String
        if dryRun {
            status = "planned"
        } else if blockedReason != nil {
            status = "blocked"
        } else if resolved.wid == nil || verified {
            status = "ok"
        } else {
            status = "failed"
        }
        let ok = status == "ok" || status == "planned"

        let receiptId = Self.makeId(prefix: "exec")
        var receipt: [String: JSON] = [
            "ok": .bool(ok),
            "status": .string(status),
            "receiptId": .string(receiptId),
            "requestId": .string(context.requestId),
            "source": .string(context.source),
            "action": .object([
                "id": .string(context.actionId),
                "type": .string("window.place"),
            ]),
            "target": resolved.json,
            "targetKind": .string(resolved.kind),
            "targetResolution": .string(resolved.resolution),
            "placement": placement.jsonValue,
            "dryRun": .bool(dryRun),
            "display": screenJSON(screen, requestedIndex: displayIndex),
            "verificationTolerance": .double(Double(verificationTolerance)),
            "plan": planJSON(
                target: resolved,
                placement: placement,
                targetFrame: targetFrame,
                beforeFrame: beforeFrame
            ),
            "mutations": .array([
                mutationJSON(
                    target: resolved,
                    beforeFrame: beforeFrame,
                    targetFrame: targetFrame,
                    afterFrame: afterFrame
                )
            ]),
            "verified": .bool(verified),
            "trace": .array(trace.map { .string($0) }),
            "events": .array(events),
            "timestamp": .double(Date().timeIntervalSince1970),
        ]

        if let wid = resolved.wid { receipt["wid"] = .int(Int(wid)) }
        if let pid = resolved.pid { receipt["pid"] = .int(Int(pid)) }
        if let app = resolved.app { receipt["app"] = .string(app) }
        if let title = resolved.title { receipt["title"] = .string(title) }
        if let session = resolved.session { receipt["session"] = .string(session) }
        if let blockedReason {
            receipt["blockedReason"] = .string(blockedReason)
        }
        if !requiredPermissions.isEmpty {
            receipt["requiredPermissions"] = .array(requiredPermissions.map { .string($0) })
        }
        if let compatibilityMethod = context.compatibilityMethod {
            receipt["compatibilityMethod"] = .string(compatibilityMethod)
        }
        let undoable = status == "ok" &&
            !dryRun &&
            resolved.wid != nil &&
            resolved.pid != nil &&
            beforeFrame != nil &&
            afterFrame != nil
        receipt["undoable"] = .bool(undoable)
        if undoable {
            receipt["undo"] = .object([
                "strategy": .string("restore-frame"),
                "requiresCurrentFrameMatch": .bool(true),
                "frameSource": .string("mutations.from"),
            ])
        }

        return .object(receipt)
    }

    private func selectUndoReceipts(params: JSON?) throws -> [JSON] {
        let receiptId = params?["receiptId"]?.stringValue
        let requestId = params?["requestId"]?.stringValue
        let wid = params?["wid"]?.uint32Value
        let steps = max(1, params?["steps"]?.intValue ?? 1)

        let snapshot = history.snapshot()
        let receipts = snapshot.receipts
        let undone = snapshot.undoneReceiptIds

        func matchesFilters(_ receipt: JSON) -> Bool {
            if let wid, receipt["wid"]?.uint32Value != wid {
                return false
            }
            return true
        }

        if let receiptId {
            guard let receipt = receipts.first(where: { $0["receiptId"]?.stringValue == receiptId }) else {
                throw RouterError.notFound("action receipt \(receiptId)")
            }
            guard matchesFilters(receipt), isUndoableReceipt(receipt, undoneReceiptIds: undone) else {
                throw RouterError.custom("Receipt \(receiptId) is not undoable")
            }
            return [receipt]
        }

        if let requestId {
            let selected = receipts.filter { receipt in
                receipt["requestId"]?.stringValue == requestId &&
                    matchesFilters(receipt) &&
                    isUndoableReceipt(receipt, undoneReceiptIds: undone)
            }
            guard !selected.isEmpty else {
                throw RouterError.notFound("undoable receipts for request \(requestId)")
            }
            return selected
        }

        let candidates = receipts.filter { receipt in
            matchesFilters(receipt) && isUndoableReceipt(receipt, undoneReceiptIds: undone)
        }

        guard !candidates.isEmpty else {
            throw RouterError.notFound("undoable action")
        }

        if wid != nil {
            return Array(candidates.prefix(steps))
        }

        var selected: [JSON] = []
        var seenRequestIds: Set<String> = []
        for receipt in candidates {
            let groupId = receipt["requestId"]?.stringValue ?? receipt["receiptId"]?.stringValue ?? UUID().uuidString
            guard !seenRequestIds.contains(groupId) else { continue }
            seenRequestIds.insert(groupId)
            selected.append(contentsOf: candidates.filter { ($0["requestId"]?.stringValue ?? $0["receiptId"]?.stringValue) == groupId })
            if seenRequestIds.count >= steps {
                break
            }
        }

        return selected
    }

    private func executeUndo(receipts: [JSON], params: JSON?) throws -> JSON {
        let dryRun = params?["dryRun"]?.boolValue == true
        let force = params?["force"]?.boolValue == true
        let source = params?["source"]?.stringValue ?? "daemon"
        let requestId = params?["requestId"]?.stringValue ?? Self.makeId(prefix: "req")
        let actionId = params?["id"]?.stringValue ?? Self.makeId(prefix: "act")
        let receiptId = Self.makeId(prefix: "exec")
        let undoOf = receipts.compactMap { $0["receiptId"]?.stringValue }
        let requestIds = Array(Set(receipts.compactMap { $0["requestId"]?.stringValue })).sorted()
        let moves = receipts.flatMap { undoMoves(from: $0) }

        guard !moves.isEmpty else {
            throw RouterError.custom("Selected receipts do not contain restorable window frames")
        }

        if Set(moves.map(\.wid)).count != moves.count {
            throw RouterError.custom("Multi-step undo for repeated windows is not supported yet; undo one step at a time")
        }

        var trace: [String] = [
            "selected \(receipts.count) receipt\(receipts.count == 1 ? "" : "s")",
            "prepared \(moves.count) restore mutation\(moves.count == 1 ? "" : "s")",
        ]
        var events: [JSON] = [
            event("undo.select", "selected \(receipts.count) receipt\(receipts.count == 1 ? "" : "s")"),
            event("undo.plan", "prepared \(moves.count) restore mutation\(moves.count == 1 ? "" : "s")"),
        ]

        var plannedMoves: [PlannedUndoMove] = []
        var conflicts: [JSON] = []
        var blockedReason: String?
        var requiredPermissions: [String] = []

        for move in moves {
            let currentFrame = Self.cgWindowFrameTopLeft(wid: move.wid)
            if !force {
                if let currentFrame, let expected = move.expectedCurrentFrame {
                    if !Self.framesClose(currentFrame, expected, tolerance: move.tolerance) {
                        conflicts.append(undoConflictJSON(move: move, currentFrame: currentFrame))
                    }
                } else if currentFrame == nil {
                    conflicts.append(undoConflictJSON(move: move, currentFrame: nil))
                }
            }
            plannedMoves.append(PlannedUndoMove(move: move, currentFrame: currentFrame, afterFrame: nil))
        }

        if !conflicts.isEmpty {
            blockedReason = "current-frame-mismatch"
            trace.append("blocked: current frame did not match receipt state")
            events.append(event("undo.blocked", "current frame did not match receipt state"))
        } else if !dryRun && !AXIsProcessTrusted() {
            blockedReason = "accessibility-not-trusted"
            requiredPermissions.append("accessibility")
            trace.append("blocked: Accessibility permission required for deterministic window restore")
            events.append(event("undo.blocked", "Accessibility permission required to restore windows"))
        } else if dryRun {
            trace.append("dry run; skipped restore")
            events.append(event("undo.skipped", "dry run requested; no window mutation performed"))
        } else {
            let restoreMoves = moves.map { move in
                (wid: move.wid, pid: move.pid, frame: move.restoreFrame)
            }
            onMain {
                WindowTiler.batchMoveAndRaiseWindows(restoreMoves)
            }
            trace.append("executed restore")
            events.append(event("undo.restore", "restored \(restoreMoves.count) window\(restoreMoves.count == 1 ? "" : "s")"))

            plannedMoves = plannedMoves.map { planned in
                var updated = planned
                updated.afterFrame = Self.waitForWindowFrame(
                    wid: planned.move.wid,
                    targetFrame: planned.move.restoreFrame,
                    tolerance: planned.move.tolerance
                )
                return updated
            }
            DesktopModel.shared.markInteraction(wids: moves.map(\.wid))
        }

        let verified = !dryRun && blockedReason == nil && plannedMoves.allSatisfy { planned in
            guard let after = planned.afterFrame else { return false }
            return Self.framesClose(after, planned.move.restoreFrame, tolerance: planned.move.tolerance)
        }

        if verified {
            trace.append("verified restored frame\(plannedMoves.count == 1 ? "" : "s")")
            events.append(event("undo.verify", "verified restored frame\(plannedMoves.count == 1 ? "" : "s")"))
        } else if dryRun {
            trace.append("verification skipped for dry run")
            events.append(event("undo.verify.skipped", "dry run requested; no final frame verification performed"))
        } else if blockedReason == nil {
            trace.append("verification could not confirm restored frame\(plannedMoves.count == 1 ? "" : "s")")
            events.append(event("undo.verify", "restored frame verification failed"))
        }

        let status: String
        if blockedReason != nil {
            status = "blocked"
        } else if dryRun {
            status = "planned"
        } else if verified {
            status = "ok"
        } else {
            status = "failed"
        }
        let ok = status == "ok" || status == "planned"

        var receipt: [String: JSON] = [
            "ok": .bool(ok),
            "status": .string(status),
            "receiptId": .string(receiptId),
            "requestId": .string(requestId),
            "source": .string(source),
            "action": .object([
                "id": .string(actionId),
                "type": .string("actions.undo"),
            ]),
            "target": .object([
                "kind": .string("undo"),
                "receiptCount": .int(receipts.count),
                "mutationCount": .int(moves.count),
            ]),
            "targetKind": .string("undo"),
            "targetResolution": .string("history"),
            "undoOf": .array(undoOf.map { .string($0) }),
            "undoRequestIds": .array(requestIds.map { .string($0) }),
            "dryRun": .bool(dryRun),
            "force": .bool(force),
            "mutations": .array(plannedMoves.map { undoMutationJSON($0) }),
            "verified": .bool(verified),
            "undoable": .bool(false),
            "trace": .array(trace.map { .string($0) }),
            "events": .array(events),
            "timestamp": .double(Date().timeIntervalSince1970),
        ]

        if let blockedReason {
            receipt["blockedReason"] = .string(blockedReason)
        }
        if !requiredPermissions.isEmpty {
            receipt["requiredPermissions"] = .array(requiredPermissions.map { .string($0) })
        }
        if !conflicts.isEmpty {
            receipt["conflicts"] = .array(conflicts)
        }

        return .object(receipt)
    }

    private func resolveWindowTarget(params: JSON?, trace: inout [String], events: inout [JSON]) throws -> ResolvedWindowTarget {
        if let wid = params?["wid"]?.uint32Value {
            guard let entry = DesktopModel.shared.windows[wid] else {
                throw RouterError.notFound("window \(wid)")
            }
            trace.append("resolved target by wid")
            events.append(event("plan.resolveTarget", "resolved wid \(wid)"))
            return ResolvedWindowTarget(kind: "wid", resolution: "wid", confidence: 1.0, entry: entry)
        }

        if let session = params?["session"]?.stringValue {
            if let entry = DesktopModel.shared.windowForSession(session) {
                trace.append("resolved target by session")
                events.append(event("plan.resolveTarget", "resolved session \(session) to wid \(entry.wid)"))
                return ResolvedWindowTarget(kind: "session", resolution: "session", confidence: 1.0, entry: entry, session: session)
            }

            if let entry = Self.windowForSessionViaTerminalSynthesis(session) {
                trace.append("resolved target by terminal synthesis")
                events.append(event("plan.resolveTarget", "resolved session \(session) through terminal synthesis to wid \(entry.wid)"))
                return ResolvedWindowTarget(
                    kind: "session",
                    resolution: "terminal-synthesis",
                    confidence: 0.9,
                    entry: entry,
                    session: session
                )
            }

            trace.append("session window not in DesktopModel; using terminal fallback")
            events.append(event("plan.resolveTarget", "session \(session) will use terminal fallback"))
            return ResolvedWindowTarget(kind: "session", resolution: "terminal-fallback", confidence: 0.4, session: session)
        }

        if let app = params?["app"]?.stringValue {
            let title = params?["title"]?.stringValue
            guard let entry = DesktopModel.shared.windowForApp(app: app, title: title) else {
                throw RouterError.notFound("window for app \(app)")
            }
            trace.append("resolved target by app/title match")
            events.append(event("plan.resolveTarget", "resolved app \(app) to wid \(entry.wid)"))
            return ResolvedWindowTarget(kind: "app", resolution: "app-title", confidence: title == nil ? 0.75 : 0.9, entry: entry)
        }

        if let target = Self.frontmostWindowTarget() {
            let entry = DesktopModel.shared.windows[target.wid]
            trace.append("resolved target by frontmost window")
            events.append(event("plan.resolveTarget", "resolved frontmost window \(target.wid)"))
            return ResolvedWindowTarget(
                kind: "frontmost",
                resolution: "frontmost",
                confidence: 0.85,
                entry: entry,
                wid: target.wid,
                pid: target.pid
            )
        }

        throw RouterError.custom("Could not resolve a window target for placement")
    }

    private static func windowPlaceParams(action: JSON?, root: JSON?) throws -> JSON {
        var dict: [String: JSON] = [:]

        func copy(_ key: String, from json: JSON?) {
            if let value = json?[key] {
                dict[key] = value
            }
        }

        if case .object(let args) = action?["args"] {
            for (key, value) in args {
                dict[key] = value
            }
        }

        for key in ["placement", "position", "display", "dryRun", "wid", "session", "app", "title"] {
            copy(key, from: root)
            copy(key, from: action)
        }

        if let target = action?["target"] ?? root?["target"] {
            try mergeTarget(target, into: &dict)
        }

        return .object(dict)
    }

    private static func mergeTarget(_ target: JSON, into dict: inout [String: JSON]) throws {
        guard case .object(let obj) = target else {
            throw RouterError.custom("target must be an object")
        }
        let kind = obj["kind"]?.stringValue?.lowercased() ?? "frontmost"

        switch kind {
        case "frontmost", "current":
            return
        case "wid", "window":
            guard let wid = obj["wid"] ?? obj["id"] else {
                throw RouterError.missingParam("target.wid")
            }
            dict["wid"] = wid
        case "session":
            guard let session = obj["session"] ?? obj["name"] else {
                throw RouterError.missingParam("target.session")
            }
            dict["session"] = session
        case "app":
            guard let app = obj["app"] ?? obj["name"] else {
                throw RouterError.missingParam("target.app")
            }
            dict["app"] = app
            if let title = obj["title"] {
                dict["title"] = title
            }
        default:
            throw RouterError.custom("Unsupported window.place target kind: \(kind)")
        }
    }

    private func event(_ phase: String, _ message: String) -> JSON {
        .object([
            "phase": .string(phase),
            "message": .string(message),
            "time": .double(Date().timeIntervalSince1970),
        ])
    }

    private func planJSON(
        target: ResolvedWindowTarget,
        placement: PlacementSpec,
        targetFrame: CGRect,
        beforeFrame: CGRect?
    ) -> JSON {
        var mutation: [String: JSON] = [
            "kind": .string(target.wid == nil ? "placeSessionWindow" : "placeWindow"),
            "to": Self.frameJSON(targetFrame),
        ]
        if let wid = target.wid { mutation["wid"] = .int(Int(wid)) }
        if let session = target.session { mutation["session"] = .string(session) }
        if let beforeFrame { mutation["from"] = Self.frameJSON(beforeFrame) }

        return .object([
            "actionType": .string("window.place"),
            "target": target.json,
            "placement": placement.jsonValue,
            "steps": .array([
                .string("resolve target"),
                .string("compute frame"),
                .string(target.wid == nil ? "place session window" : "place window"),
                .string("verify frame"),
            ]),
            "mutations": .array([.object(mutation)]),
        ])
    }

    private func mutationJSON(
        target: ResolvedWindowTarget,
        beforeFrame: CGRect?,
        targetFrame: CGRect,
        afterFrame: CGRect?
    ) -> JSON {
        var obj: [String: JSON] = [
            "kind": .string(target.wid == nil ? "placeSessionWindow" : "placeWindow"),
            "to": Self.frameJSON(targetFrame),
        ]
        if let wid = target.wid { obj["wid"] = .int(Int(wid)) }
        if let pid = target.pid { obj["pid"] = .int(Int(pid)) }
        if let session = target.session { obj["session"] = .string(session) }
        if let beforeFrame { obj["from"] = Self.frameJSON(beforeFrame) }
        if let afterFrame { obj["after"] = Self.frameJSON(afterFrame) }
        return .object(obj)
    }

    private func undoMoves(from receipt: JSON) -> [UndoMove] {
        guard let mutations = receipt["mutations"]?.arrayValue else { return [] }
        let receiptId = receipt["receiptId"]?.stringValue ?? "<unknown>"
        let requestId = receipt["requestId"]?.stringValue
        let app = receipt["app"]?.stringValue
        let session = receipt["session"]?.stringValue
        let tolerance = CGFloat(receipt["verificationTolerance"]?.numericDouble ?? Double(Self.verificationTolerance(forApp: app)))

        return mutations.compactMap { mutation in
            guard let wid = mutation["wid"]?.uint32Value,
                  let pidInt = mutation["pid"]?.intValue ?? receipt["pid"]?.intValue,
                  let restoreFrame = Self.frame(from: mutation["from"]) else {
                return nil
            }
            let expectedCurrent = Self.frame(from: mutation["after"]) ?? Self.frame(from: mutation["to"])
            return UndoMove(
                receiptId: receiptId,
                requestId: requestId,
                wid: wid,
                pid: Int32(pidInt),
                app: app,
                session: session,
                restoreFrame: restoreFrame,
                expectedCurrentFrame: expectedCurrent,
                tolerance: tolerance
            )
        }
    }

    private func isUndoableReceipt(_ receipt: JSON, undoneReceiptIds: Set<String>) -> Bool {
        guard let receiptId = receipt["receiptId"]?.stringValue,
              !undoneReceiptIds.contains(receiptId),
              receipt["status"]?.stringValue == "ok",
              receipt["action"]?["type"]?.stringValue == "window.place" else {
            return false
        }
        if receipt["undoable"]?.boolValue == false {
            return false
        }
        return !undoMoves(from: receipt).isEmpty
    }

    private func undoMutationJSON(_ planned: PlannedUndoMove) -> JSON {
        let move = planned.move
        var obj: [String: JSON] = [
            "kind": .string("restoreFrame"),
            "receiptId": .string(move.receiptId),
            "wid": .int(Int(move.wid)),
            "pid": .int(Int(move.pid)),
            "from": planned.currentFrame.map(Self.frameJSON) ?? .null,
            "to": Self.frameJSON(move.restoreFrame),
            "tolerance": .double(Double(move.tolerance)),
        ]
        if let requestId = move.requestId { obj["requestId"] = .string(requestId) }
        if let app = move.app { obj["app"] = .string(app) }
        if let session = move.session { obj["session"] = .string(session) }
        if let expected = move.expectedCurrentFrame { obj["expectedCurrent"] = Self.frameJSON(expected) }
        if let after = planned.afterFrame { obj["after"] = Self.frameJSON(after) }
        return .object(obj)
    }

    private func undoConflictJSON(move: UndoMove, currentFrame: CGRect?) -> JSON {
        var obj: [String: JSON] = [
            "receiptId": .string(move.receiptId),
            "wid": .int(Int(move.wid)),
            "reason": .string(currentFrame == nil ? "window-frame-unavailable" : "current-frame-mismatch"),
            "target": Self.frameJSON(move.restoreFrame),
            "tolerance": .double(Double(move.tolerance)),
        ]
        if let currentFrame { obj["current"] = Self.frameJSON(currentFrame) }
        if let expected = move.expectedCurrentFrame { obj["expectedCurrent"] = Self.frameJSON(expected) }
        return .object(obj)
    }

    private func screenJSON(_ screen: NSScreen, requestedIndex: Int?) -> JSON {
        let resolvedIndex = NSScreen.screens.firstIndex(where: { $0 === screen })
        var obj: [String: JSON] = [
            "name": .string(screen.localizedName),
            "resolvedIndex": .int(resolvedIndex ?? -1),
        ]
        if let requestedIndex {
            obj["requestedIndex"] = .int(requestedIndex)
        }
        return .object(obj)
    }

    private func onMain<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }

    private static func framesClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 6) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
            abs(a.origin.y - b.origin.y) <= tolerance &&
            abs(a.width - b.width) <= tolerance &&
            abs(a.height - b.height) <= tolerance
    }

    private static func verificationTolerance(forApp app: String?) -> CGFloat {
        guard let app else { return 6 }
        if app == "Terminal" || app == "iTerm2" {
            return 14
        }
        return 6
    }

    private static func windowForSessionViaTerminalSynthesis(_ session: String) -> WindowEntry? {
        ProcessModel.shared.synthesizeTerminals()
            .first { $0.tmuxSession == session }
            .flatMap { instance in
                instance.windowId.flatMap { DesktopModel.shared.windows[$0] }
            }
    }

    private static func waitForWindowFrame(
        wid: UInt32,
        targetFrame: CGRect,
        tolerance: CGFloat,
        timeout: TimeInterval = 0.8,
        interval: useconds_t = 50_000
    ) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastFrame: CGRect?

        repeat {
            if let frame = Self.cgWindowFrameTopLeft(wid: wid) {
                lastFrame = frame
                if framesClose(frame, targetFrame, tolerance: tolerance) {
                    return frame
                }
            }
            usleep(interval)
        } while Date() < deadline

        return lastFrame
    }

    private static func cgWindowFrameTopLeft(wid: UInt32) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let windowNumber = info[kCGWindowNumber as String] as? UInt32,
                  windowNumber == wid,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            var rect = CGRect.zero
            if CGRectMakeWithDictionaryRepresentation(bounds, &rect) {
                return rect
            }
        }

        return nil
    }

    private static func frame(from json: JSON?) -> CGRect? {
        guard case .object(let obj) = json,
              let x = obj["x"]?.numericDouble,
              let y = obj["y"]?.numericDouble,
              let w = obj["w"]?.numericDouble,
              let h = obj["h"]?.numericDouble else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func resolveTargetScreen(for entry: WindowEntry?, displayIndex: Int?) -> NSScreen {
        if let displayIndex, displayIndex >= 0, displayIndex < NSScreen.screens.count {
            return NSScreen.screens[displayIndex]
        }
        if let entry {
            return WindowTiler.screenForWindowFrame(entry.frame)
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private static func frontmostWindowTarget() -> (wid: UInt32, pid: Int32)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              !LatticesRuntime.isLatticesBundleIdentifier(app.bundleIdentifier) else {
            return nil
        }

        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let focusedWindow = focusedRef else {
            return nil
        }

        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(focusedWindow as! AXUIElement, &wid) == .success else {
            return nil
        }
        return (UInt32(wid), app.processIdentifier)
    }

    private static func frameJSON(_ frame: CGRect) -> JSON {
        .object([
            "x": .double(Double(frame.origin.x)),
            "y": .double(Double(frame.origin.y)),
            "w": .double(Double(frame.width)),
            "h": .double(Double(frame.height)),
        ])
    }

    private static func makeId(prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.lowercased())"
    }
}

private struct ActionInvocationContext {
    let requestId: String
    let actionId: String
    let source: String
    let compatibilityMethod: String?
}

private struct UndoMove {
    let receiptId: String
    let requestId: String?
    let wid: UInt32
    let pid: Int32
    let app: String?
    let session: String?
    let restoreFrame: CGRect
    let expectedCurrentFrame: CGRect?
    let tolerance: CGFloat
}

private struct PlannedUndoMove {
    let move: UndoMove
    let currentFrame: CGRect?
    var afterFrame: CGRect?
}

private struct ResolvedWindowTarget {
    let kind: String
    let resolution: String
    let confidence: Double
    let entry: WindowEntry?
    let session: String?
    let explicitWid: UInt32?
    let explicitPid: Int32?

    init(
        kind: String,
        resolution: String,
        confidence: Double,
        entry: WindowEntry? = nil,
        session: String? = nil,
        wid: UInt32? = nil,
        pid: Int32? = nil
    ) {
        self.kind = kind
        self.resolution = resolution
        self.confidence = confidence
        self.entry = entry
        self.session = session ?? entry?.latticesSession
        self.explicitWid = wid
        self.explicitPid = pid
    }

    var wid: UInt32? { entry?.wid ?? explicitWid }
    var pid: Int32? { entry?.pid ?? explicitPid }
    var app: String? { entry?.app }
    var title: String? { entry?.title }

    var json: JSON {
        var obj: [String: JSON] = [
            "kind": .string(kind),
            "resolution": .string(resolution),
            "confidence": .double(confidence),
        ]
        if let wid { obj["wid"] = .int(Int(wid)) }
        if let pid { obj["pid"] = .int(Int(pid)) }
        if let app { obj["app"] = .string(app) }
        if let title { obj["title"] = .string(title) }
        if let session { obj["session"] = .string(session) }
        return .object(obj)
    }
}

private final class ActionHistoryStore {
    private let limit: Int
    private let lock = NSLock()
    private var receipts: [JSON] = []
    private var undoneReceiptIds: Set<String> = []

    init(limit: Int) {
        self.limit = limit
    }

    func record(_ receipt: JSON) {
        lock.lock()
        receipts.insert(receipt, at: 0)
        if receipts.count > limit {
            receipts.removeLast(receipts.count - limit)
        }
        lock.unlock()
    }

    func recordUndo(_ receipt: JSON, undoOf receiptIds: [String]) {
        lock.lock()
        undoneReceiptIds.formUnion(receiptIds)
        receipts.insert(receipt, at: 0)
        if receipts.count > limit {
            receipts.removeLast(receipts.count - limit)
        }
        lock.unlock()
    }

    func snapshot() -> (receipts: [JSON], undoneReceiptIds: Set<String>) {
        lock.lock()
        let result = (receipts, undoneReceiptIds)
        lock.unlock()
        return result
    }

    func list(params: JSON?) -> JSON {
        let limit = params?["limit"]?.intValue ?? 20
        let type = params?["type"]?.stringValue
        let source = params?["source"]?.stringValue
        let wid = params?["wid"]?.uint32Value
        let requestId = params?["requestId"]?.stringValue
        let status = params?["status"]?.stringValue
        let session = params?["session"]?.stringValue
        let undoable = params?["undoable"]?.boolValue

        lock.lock()
        let snapshot = receipts
        let undone = undoneReceiptIds
        lock.unlock()

        let filtered = snapshot.map { decorate($0, undoneReceiptIds: undone) }.filter { receipt in
            if let type, receipt["action"]?["type"]?.stringValue != type {
                return false
            }
            if let source, receipt["source"]?.stringValue != source {
                return false
            }
            if let wid, receipt["wid"]?.uint32Value != wid {
                return false
            }
            if let requestId, receipt["requestId"]?.stringValue != requestId {
                return false
            }
            if let status, receipt["status"]?.stringValue != status {
                return false
            }
            if let session, receipt["session"]?.stringValue != session {
                return false
            }
            if let undoable, receipt["undoable"]?.boolValue != undoable {
                return false
            }
            return true
        }

        return .array(Array(filtered.prefix(max(0, limit))))
    }

    private func decorate(_ receipt: JSON, undoneReceiptIds: Set<String>) -> JSON {
        guard case .object(var obj) = receipt else { return receipt }
        let isUndone = obj["receiptId"]?.stringValue.map { undoneReceiptIds.contains($0) } ?? false
        obj["undone"] = .bool(isUndone)
        if isUndone {
            obj["undoable"] = .bool(false)
        }
        return .object(obj)
    }
}
