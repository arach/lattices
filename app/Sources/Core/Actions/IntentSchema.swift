import Foundation

struct IntentDef {
    let name: String
    let description: String
    let examples: [String]
    let slots: [IntentSlot]
    let handler: (IntentRequest) throws -> JSON
}

struct IntentSlot {
    let name: String
    let type: String
    let required: Bool
    let description: String
    let enumValues: [String]?
    let defaultValue: JSON?

    init(
        name: String,
        type: String,
        required: Bool,
        description: String,
        enumValues: [String]? = nil,
        defaultValue: JSON? = nil
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
        self.enumValues = enumValues
        self.defaultValue = defaultValue
    }
}

struct IntentRequest {
    let intent: String
    let slots: [String: JSON]
    let rawText: String?
    let confidence: Double?
    let source: String?
}

enum SlotType {
    case string
    case int
    case bool
    case position
    case query
    case app
    case session
    case layer
    case enumerated([String])

    var typeLabel: String {
        switch self {
        case .string: return "string"
        case .int: return "int"
        case .bool: return "bool"
        case .position: return "position"
        case .query: return "query"
        case .app: return "app"
        case .session: return "session"
        case .layer: return "layer"
        case .enumerated: return "string"
        }
    }

    var enumValues: [String]? {
        guard case .enumerated(let values) = self else { return nil }
        return values
    }
}

typealias SlotDef = IntentSlot

extension IntentSlot {
    init(
        name: String,
        type: SlotType,
        required: Bool = true,
        description: String = "",
        defaultValue: JSON? = nil
    ) {
        self.init(
            name: name,
            type: type.typeLabel,
            required: required,
            description: description,
            enumValues: type.enumValues,
            defaultValue: defaultValue
        )
    }
}
