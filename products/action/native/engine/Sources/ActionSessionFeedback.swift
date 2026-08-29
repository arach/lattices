import Foundation

struct ActionSessionFeedbackDocument: Codable, Sendable {
    struct Item: Codable, Identifiable, Sendable {
        let id: String
        let createdAt: String
        let startTimeSeconds: Double
        let endTimeSeconds: Double?
        let region: Region?
        let drawing: Drawing?
        let instruction: String
    }

    struct Region: Codable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Drawing: Codable, Sendable {
        struct Point: Codable, Sendable {
            let x: Double
            let y: Double
        }

        let points: [Point]
    }

    let sessionId: String
    var updatedAt: String
    var items: [Item]

    static func empty(for sessionId: String) -> ActionSessionFeedbackDocument {
        ActionSessionFeedbackDocument(
            sessionId: sessionId,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            items: []
        )
    }
}

struct ActionAgentFeedbackExport: Codable, Sendable {
    struct Item: Codable, Sendable {
        let id: String
        let createdAt: String
        let instruction: String
        let startTimeSeconds: Double
        let startTimecode: String
        let endTimeSeconds: Double?
        let endTimecode: String?
        let region: ActionSessionFeedbackDocument.Region?
        let drawing: ActionSessionFeedbackDocument.Drawing?
    }

    let sessionId: String
    let expression: String
    let expectedResult: String
    let actualResult: String
    let videoPath: String
    let tracePath: String
    let feedbackPath: String
    let updatedAt: String
    let itemCount: Int
    let items: [Item]
}

extension ActionSessionFeedbackDocument {
    func agentExport(for session: ActionSessionSummary) -> ActionAgentFeedbackExport {
        let sortedItems = items.sorted { lhs, rhs in
            lhs.startTimeSeconds < rhs.startTimeSeconds
        }

        return ActionAgentFeedbackExport(
            sessionId: session.sessionId,
            expression: session.expression,
            expectedResult: session.expectedResult,
            actualResult: session.actualResult,
            videoPath: session.videoURL.path,
            tracePath: session.traceURL.path,
            feedbackPath: session.feedbackURL.path,
            updatedAt: updatedAt,
            itemCount: sortedItems.count,
            items: sortedItems.map { item in
                ActionAgentFeedbackExport.Item(
                    id: item.id,
                    createdAt: item.createdAt,
                    instruction: item.instruction,
                    startTimeSeconds: item.startTimeSeconds,
                    startTimecode: item.startTimeSeconds.actionTimecode,
                    endTimeSeconds: item.endTimeSeconds,
                    endTimecode: item.endTimeSeconds?.actionTimecode,
                    region: item.region,
                    drawing: item.drawing
                )
            }
        )
    }

    func agentMarkdown(for session: ActionSessionSummary) -> String {
        let export = agentExport(for: session)
        var lines: [String] = [
            "# Agent Feedback",
            "",
            "- Session: `\(export.sessionId)`",
            "- Expression: `\(export.expression)`",
            "- Expected Result: `\(export.expectedResult)`",
            "- Actual Result: `\(export.actualResult)`",
            "- Video: `\(export.videoPath)`",
            "- Trace: `\(export.tracePath)`",
            "- Source Feedback: `\(export.feedbackPath)`",
            "- Updated: `\(export.updatedAt)`",
            ""
        ]

        if export.items.isEmpty {
            lines.append("No feedback items yet.")
            return lines.joined(separator: "\n")
        }

        lines.append("## Requested Changes")
        lines.append("")

        for (index, item) in export.items.enumerated() {
            lines.append("\(index + 1). Time: `\(item.startTimecode)\(item.endTimecode.map { "-\($0)" } ?? "")`")
            if let region = item.region {
                lines.append("   Region: `x=\(region.x.actionPercent) y=\(region.y.actionPercent) w=\(region.width.actionPercent) h=\(region.height.actionPercent)`")
            }
            if let drawing = item.drawing {
                lines.append("   Drawing: `\(drawing.points.count) points`")
            }
            lines.append("   Instruction: \(item.instruction)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

private extension Double {
    var actionTimecode: String {
        guard isFinite, self >= 0 else {
            return "00:00.0"
        }
        let minutes = Int(self) / 60
        let wholeSeconds = Int(self) % 60
        let tenths = Int((self * 10).rounded(.down)) % 10
        return String(format: "%02d:%02d.%01d", minutes, wholeSeconds, tenths)
    }

    var actionPercent: String {
        String(format: "%.1f%%", self * 100)
    }
}
