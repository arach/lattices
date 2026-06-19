import CoreGraphics
import Foundation

struct RunFrame: Codable, Equatable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    init(_ frame: WindowFrame) {
        self.x = frame.x
        self.y = frame.y
        self.w = frame.w
        self.h = frame.h
    }
}

struct RunSurface: Codable, Identifiable, Equatable {
    let id: String
    let kind: String
    let wid: UInt32?
    let app: String?
    let title: String?
    let frame: RunFrame?
    let latticesSession: String?
    let x: Double?
    let y: Double?

    static func window(_ window: WindowEntry) -> RunSurface {
        RunSurface(
            id: "window-\(window.wid)",
            kind: "window",
            wid: window.wid,
            app: window.app,
            title: window.title,
            frame: RunFrame(window.frame),
            latticesSession: window.latticesSession,
            x: nil,
            y: nil
        )
    }

    static func cursor(_ point: CGPoint) -> RunSurface {
        RunSurface(
            id: "cursor-\(Int(point.x))-\(Int(point.y))",
            kind: "cursor",
            wid: nil,
            app: nil,
            title: "Mouse cursor",
            frame: nil,
            latticesSession: nil,
            x: Double(point.x),
            y: Double(point.y)
        )
    }
}

struct RunArtifact: Codable, Identifiable, Equatable {
    let id: String
    let runId: String
    let kind: String
    let path: String
    let relativePath: String
    let mimeType: String
    let createdAt: String
    let metadata: [String: JSON]
}

struct RunTraceEvent: Codable, Identifiable, Equatable {
    let id: String
    let runId: String
    let time: String
    let kind: String
    let summary: String
    let data: [String: JSON]
}

struct RunSession: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var source: String
    var state: String
    let startedAt: String
    var completedAt: String?
    let artifactDirectoryPath: String
    var surfaces: [RunSurface]
    var artifacts: [RunArtifact]
    var trace: [RunTraceEvent]
}

extension RunSession {
    var json: JSON {
        var obj: [String: JSON] = [
            "id": .string(id),
            "title": .string(title),
            "source": .string(source),
            "state": .string(state),
            "startedAt": .string(startedAt),
            "artifactDirectoryPath": .string(artifactDirectoryPath),
            "surfaces": .array(surfaces.map(\.json)),
            "artifacts": .array(artifacts.map(\.json)),
            "trace": .array(trace.map(\.json)),
        ]
        if let completedAt {
            obj["completedAt"] = .string(completedAt)
        }
        return .object(obj)
    }
}

extension RunSurface {
    var json: JSON {
        var obj: [String: JSON] = [
            "id": .string(id),
            "kind": .string(kind),
        ]
        if let wid { obj["wid"] = .int(Int(wid)) }
        if let app { obj["app"] = .string(app) }
        if let title { obj["title"] = .string(title) }
        if let frame {
            obj["frame"] = .object([
                "x": .double(frame.x),
                "y": .double(frame.y),
                "w": .double(frame.w),
                "h": .double(frame.h),
            ])
        }
        if let latticesSession {
            obj["latticesSession"] = .string(latticesSession)
        }
        if let x { obj["x"] = .double(x) }
        if let y { obj["y"] = .double(y) }
        return .object(obj)
    }
}

extension RunArtifact {
    var json: JSON {
        .object([
            "id": .string(id),
            "runId": .string(runId),
            "kind": .string(kind),
            "path": .string(path),
            "relativePath": .string(relativePath),
            "mimeType": .string(mimeType),
            "createdAt": .string(createdAt),
            "metadata": .object(metadata),
        ])
    }
}

extension RunTraceEvent {
    var json: JSON {
        .object([
            "id": .string(id),
            "runId": .string(runId),
            "time": .string(time),
            "kind": .string(kind),
            "summary": .string(summary),
            "data": .object(data),
        ])
    }
}
