import Foundation

// MARK: - Catalog root

/// Declarative tactile catalog: named sound patches + semantic event bindings.
public struct DeckTactileCatalog: Codable, Equatable, Sendable {
    public var version: Int
    public var meta: DeckTactileMeta?
    public var sounds: [String: DeckSoundPatch]
    public var events: [String: DeckTactileEventBinding]

    public init(
        version: Int = 1,
        meta: DeckTactileMeta? = nil,
        sounds: [String: DeckSoundPatch] = [:],
        events: [String: DeckTactileEventBinding] = [:]
    ) {
        self.version = version
        self.meta = meta
        self.sounds = sounds
        self.events = events
    }
}

public struct DeckTactileMeta: Codable, Equatable, Sendable {
    public var name: String?
    public var description: String?
}

// MARK: - Event bindings

public struct DeckTactileEventBinding: Codable, Equatable, Sendable {
    public var sound: DeckTactileSoundRef?
    public var haptic: DeckHapticStyle?
    public var hapticOnly: Bool?
    public var soundOnly: Bool?

    public init(
        sound: DeckTactileSoundRef? = nil,
        haptic: DeckHapticStyle? = nil,
        hapticOnly: Bool? = nil,
        soundOnly: Bool? = nil
    ) {
        self.sound = sound
        self.haptic = haptic
        self.hapticOnly = hapticOnly
        self.soundOnly = soundOnly
    }
}

public enum DeckTactileSoundRef: Codable, Equatable, Sendable {
    case id(String)
    case resolved(ref: String, params: [String: DeckTactileParamValue])

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let id = try? single.decode(String.self) {
            self = .id(id)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ref = try container.decode(String.self, forKey: .ref)
        let params = try container.decodeIfPresent([String: DeckTactileParamValue].self, forKey: .params) ?? [:]
        self = .resolved(ref: ref, params: params)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .id(let id):
            var container = encoder.singleValueContainer()
            try container.encode(id)
        case .resolved(let ref, let params):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(ref, forKey: .ref)
            if !params.isEmpty {
                try container.encode(params, forKey: .params)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case ref, params
    }

    public var patchID: String {
        switch self {
        case .id(let id): return id
        case .resolved(let ref, _): return ref
        }
    }

    public var params: [String: DeckTactileParamValue] {
        switch self {
        case .id: return [:]
        case .resolved(_, let params): return params
        }
    }
}

public enum DeckTactileParamValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported tactile param value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    public var intValue: Int? {
        switch self {
        case .bool(let value): return value ? 1 : 0
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        case .double(let value): return value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
    }
}

public enum DeckHapticStyle: String, Codable, CaseIterable, Sendable {
    case rigid
    case heavy
    case medium
    case light
    case selection
    case success
    case warning
    case generic
    case alignment
}

// MARK: - Sound patches

public struct DeckSoundPatch: Codable, Equatable, Sendable {
    public var duration: Double
    public var volume: Double?
    public var layers: [DeckSoundLayer]

    public init(duration: Double, volume: Double? = nil, layers: [DeckSoundLayer]) {
        self.duration = duration
        self.volume = volume
        self.layers = layers
    }
}

public enum DeckSoundLayer: Codable, Equatable, Sendable {
    case oscillator(DeckOscillatorLayer)
    case noise(DeckNoiseLayer)

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "oscillator":
            self = .oscillator(try DeckOscillatorLayer(from: decoder))
        case "noise":
            self = .noise(try DeckNoiseLayer(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown layer kind: \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .oscillator(let layer):
            try layer.encode(to: encoder)
        case .noise(let layer):
            try layer.encode(to: encoder)
        }
    }
}

public struct DeckOscillatorLayer: Codable, Equatable, Sendable {
    public var kind: String = "oscillator"
    public var waveform: DeckWaveform
    public var frequency: DeckFrequencySpec
    public var gain: DeckGainSpec
    public var filter: DeckFilterSpec?

    public init(
        waveform: DeckWaveform,
        frequency: DeckFrequencySpec,
        gain: DeckGainSpec,
        filter: DeckFilterSpec? = nil
    ) {
        self.waveform = waveform
        self.frequency = frequency
        self.gain = gain
        self.filter = filter
    }
}

public struct DeckNoiseLayer: Codable, Equatable, Sendable {
    public var kind: String = "noise"
    public var duration: Double
    public var gain: DeckGainSpec

    public init(duration: Double, gain: DeckGainSpec) {
        self.duration = duration
        self.gain = gain
    }
}

public enum DeckWaveform: String, Codable, Sendable {
    case sine
    case triangle
    case square
}

public struct DeckFrequencySpec: Codable, Equatable, Sendable {
    public var start: DeckFrequencyValue
    public var end: Double?
    public var time: Double?
    public var curve: DeckCurve?

    public init(start: DeckFrequencyValue, end: Double? = nil, time: Double? = nil, curve: DeckCurve? = nil) {
        self.start = start
        self.end = end
        self.time = time
        self.curve = curve
    }
}

public enum DeckFrequencyValue: Codable, Equatable, Sendable {
    case fixed(Double)
    case parameterized(base: Double, detune: DeckFrequencyDetune)

    public init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(Double.self) {
            self = .fixed(value)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = try container.decode(Double.self, forKey: .base)
        let detune = try container.decode(DeckFrequencyDetune.self, forKey: .detune)
        self = .parameterized(base: base, detune: detune)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .fixed(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .parameterized(let base, let detune):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(base, forKey: .base)
            try container.encode(detune, forKey: .detune)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case base, detune
    }
}

public struct DeckFrequencyDetune: Codable, Equatable, Sendable {
    public var param: String
    public var step: Double
    public var modulo: Int

    public init(param: String, step: Double, modulo: Int) {
        self.param = param
        self.step = step
        self.modulo = modulo
    }
}

public struct DeckFilterSpec: Codable, Equatable, Sendable {
    public var type: String
    public var start: Double
    public var end: Double
    public var time: Double
    public var curve: DeckCurve?

    public init(type: String = "lowpass", start: Double, end: Double, time: Double, curve: DeckCurve? = nil) {
        self.type = type
        self.start = start
        self.end = end
        self.time = time
        self.curve = curve
    }
}

public enum DeckGainSpec: Codable, Equatable, Sendable {
    case envelope(DeckEnvelope)
    case segments([DeckEnvelope])

    public init(from decoder: Decoder) throws {
        if let envelope = try? DeckEnvelope(from: decoder) {
            self = .envelope(envelope)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let segments = try container.decode([DeckEnvelope].self, forKey: .segments)
        self = .segments(segments)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .envelope(let envelope):
            try envelope.encode(to: encoder)
        case .segments(let segments):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(segments, forKey: .segments)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case segments
    }
}

public struct DeckEnvelope: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var time: Double
    public var curve: DeckCurve?
    public var delay: Double?

    public init(start: Double, end: Double, time: Double, curve: DeckCurve? = nil, delay: Double? = nil) {
        self.start = start
        self.end = end
        self.time = time
        self.curve = curve
        self.delay = delay
    }
}

public enum DeckCurve: String, Codable, Sendable {
    case linear
    case exponential
}

public enum DeckTactileEventID: String, CaseIterable, Sendable {
    case deckKey = "deck.key"
    case deckKeyAccent = "deck.key.accent"
    case deckRotary = "deck.rotary"
    case deckToggle = "deck.toggle"
    case deckButton = "deck.button"
    case deckDecisionApproved = "deck.decision.approved"
    case deckDecisionDeferred = "deck.decision.deferred"
    case pointerAim = "pointer.aim"
    case pointerCommit = "pointer.commit"
}
