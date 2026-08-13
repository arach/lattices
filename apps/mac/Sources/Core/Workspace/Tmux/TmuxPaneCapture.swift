import Foundation

/// Exact tmux pane text. Never falls back to screenshot or OCR.
enum TmuxPaneCapture {
    struct Target: Equatable {
        let session: String
        let paneId: String
        let paneName: String
        let tty: String?
    }

    static func capture(
        session: String?,
        pane: String?,
        paneId: String?,
        tty: String?,
        lines: Int,
        includeEscapes: Bool
    ) throws -> JSON {
        guard TmuxQuery.isAvailable else {
            throw RouterError.custom("tmux is not available")
        }
        guard session != nil || paneId != nil || tty != nil else {
            throw RouterError.missingParam("session, paneId, or tty")
        }

        let sessions = TmuxQuery.listSessions()
        let ttyIndex = ttyIndex(from: ProcessModel.shared)
        let target = try resolve(
            session: session,
            pane: pane,
            paneId: paneId,
            tty: tty,
            sessions: sessions,
            ttyIndex: ttyIndex
        )

        let clamped = max(1, min(lines, 500))
        let text = TmuxQuery.capturePane(
            paneId: target.paneId,
            lineLimit: clamped,
            includeEscapes: includeEscapes
        ) ?? ""
        let lineCount = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count

        var obj: [String: JSON] = [
            "ok": .bool(true),
            "session": .string(target.session),
            "paneId": .string(target.paneId),
            "paneName": .string(target.paneName),
            "text": .string(text),
            "lineCount": .int(lineCount),
        ]
        if let tty = target.tty {
            obj["tty"] = .string(tty)
        }
        return .object(obj)
    }

    static func resolve(
        session: String?,
        pane: String?,
        paneId: String?,
        tty: String?,
        sessions: [TmuxSession],
        ttyIndex: [String: (session: String, paneId: String)]
    ) throws -> Target {
        var matches: [Target] = []

        if let paneId, !paneId.isEmpty {
            matches = targets(in: sessions, ttyIndex: ttyIndex).filter { $0.paneId == normalizePaneId(paneId) }
        } else if let tty, !tty.isEmpty {
            let key = normalizeTTY(tty)
            if let hit = ttyIndex[key],
               let target = targets(in: sessions, ttyIndex: ttyIndex).first(where: {
                   $0.session == hit.session && $0.paneId == hit.paneId
               }) {
                matches = [target]
            }
        } else if let session, !session.isEmpty {
            let inSession = targets(in: sessions, ttyIndex: ttyIndex).filter { $0.session == session }
            if let pane, !pane.isEmpty {
                let wanted = normalizePaneId(pane)
                matches = inSession.filter {
                    $0.paneId == wanted || $0.paneName == pane
                }
            } else {
                matches = inSession
            }
        }

        if matches.isEmpty {
            throw RouterError.notFound(missingDescription(session: session, pane: pane, paneId: paneId, tty: tty))
        }
        if matches.count > 1 {
            let listed = matches.map { "\($0.session) \($0.paneId) \($0.paneName)" }.joined(separator: ", ")
            throw RouterError.custom("Ambiguous pane. Candidates: \(listed)")
        }
        return matches[0]
    }

    static func ttyIndex(from processes: ProcessModel) -> [String: (session: String, paneId: String)] {
        var index: [String: (session: String, paneId: String)] = [:]
        for entry in processes.processTable.values {
            guard entry.tty != "??", let link = processes.tmuxLinkage(for: entry) else { continue }
            index[normalizeTTY(entry.tty)] = link
        }
        return index
    }

    private static func targets(
        in sessions: [TmuxSession],
        ttyIndex: [String: (session: String, paneId: String)]
    ) -> [Target] {
        let ttyByPane = Dictionary(uniqueKeysWithValues: ttyIndex.map { ($0.value.paneId, $0.key) })
        return sessions.flatMap { session in
            session.panes.map { pane in
                Target(
                    session: session.name,
                    paneId: pane.id,
                    paneName: pane.title.isEmpty ? pane.windowName : pane.title,
                    tty: ttyByPane[pane.id].map { "/dev/\($0)" }
                )
            }
        }
    }

    static func normalizeTTY(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/dev/", with: "")
    }

    static func normalizePaneId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("%") { return trimmed }
        if trimmed.allSatisfy(\.isNumber) { return "%\(trimmed)" }
        return trimmed
    }

    private static func missingDescription(session: String?, pane: String?, paneId: String?, tty: String?) -> String {
        if let paneId { return "pane \(paneId)" }
        if let tty { return "tty \(tty)" }
        if let session, let pane { return "session \(session) pane \(pane)" }
        if let session { return "session \(session)" }
        return "pane"
    }
}
