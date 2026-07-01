import Foundation

public struct LatticesFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct LatticesWindow: Codable, Identifiable, Equatable, Sendable {
    public var wid: Int
    public var app: String
    public var pid: Int
    public var title: String
    public var frame: LatticesFrame
    public var spaceIds: [Int]
    public var isOnScreen: Bool
    public var latticesSession: String?
    public var axVerified: Bool?
    public var layerTag: String?

    public var id: Int { wid }
}

public struct LatticesProject: Codable, Identifiable, Equatable, Sendable {
    public var path: String
    public var name: String
    public var sessionName: String
    public var isRunning: Bool
    public var hasConfig: Bool
    public var paneCount: Int
    public var paneNames: [String]
    public var devCommand: String?
    public var packageManager: String?

    public var id: String { path }
}

public struct LatticesTmuxSession: Codable, Identifiable, Equatable, Sendable {
    public var name: String
    public var windowCount: Int
    public var attached: Bool
    public var panes: [LatticesTmuxPane]

    public var id: String { name }
}

public struct LatticesTmuxPane: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var windowIndex: Int
    public var windowName: String
    public var title: String
    public var currentCommand: String
    public var pid: Int
    public var isActive: Bool
    public var children: [LatticesPaneChild]?
}

public struct LatticesPaneChild: Codable, Identifiable, Equatable, Sendable {
    public var pid: Int
    public var command: String
    public var args: String
    public var cwd: String?

    public var id: Int { pid }
}

public struct LatticesDaemonStatus: Codable, Equatable, Sendable {
    public var uptime: Double
    public var clientCount: Int
    public var version: String
    public var windowCount: Int
    public var tmuxSessionCount: Int
}

public struct LatticesAPISchema: Codable, Equatable, Sendable {
    public var version: String
    public var models: [LatticesAPIModel]
    public var methods: [LatticesAPIMethod]
}

public struct LatticesAPIModel: Codable, Equatable, Sendable {
    public var name: String
    public var fields: [LatticesAPIField]
}

public struct LatticesAPIField: Codable, Equatable, Sendable {
    public var name: String
    public var type: String
    public var required: Bool
    public var description: String
}

public struct LatticesAPIMethod: Codable, Equatable, Sendable {
    public var method: String
    public var description: String
    public var access: String
    public var params: [LatticesAPIParam]
    public var returns: JSONValue
}

public struct LatticesAPIParam: Codable, Equatable, Sendable {
    public var name: String
    public var type: String
    public var required: Bool
    public var description: String
}

public struct LatticesWindowTarget: Codable, Equatable, Sendable {
    public var wid: Int?
    public var session: String?
    public var app: String?
    public var title: String?

    public init(wid: Int? = nil, session: String? = nil, app: String? = nil, title: String? = nil) {
        self.wid = wid
        self.session = session
        self.app = app
        self.title = title
    }

    public static func window(_ wid: Int) -> LatticesWindowTarget {
        LatticesWindowTarget(wid: wid)
    }

    public static func session(_ session: String) -> LatticesWindowTarget {
        LatticesWindowTarget(session: session)
    }

    public static func app(_ app: String, title: String? = nil) -> LatticesWindowTarget {
        LatticesWindowTarget(app: app, title: title)
    }

    var jsonFields: [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        fields.set("wid", wid.map { .int($0) })
        fields.set("session", session.map { .string($0) })
        fields.set("app", app.map { .string($0) })
        fields.set("title", title.map { .string($0) })
        return fields
    }

    var json: JSONValue {
        .object(jsonFields)
    }
}

public enum LatticesTilePosition: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case top
    case bottom
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    case maximize
    case center
}

public enum LatticesComputerTreatment: String, Codable, Sendable {
    case observe
    case stage
    case present
    case execute
}
