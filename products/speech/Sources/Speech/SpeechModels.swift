import Foundation

enum SpeechJobState: String, Equatable, Sendable {
    case queued
    case generating
    case playing
    case paused
    case completed
    case cancelled
    case failed
}

enum SpeechCachePolicy: String, Equatable, Sendable {
    case reuse
    case fresh
}

enum SpeechAudioFormat: String, Equatable, Sendable {
    case mp3
    case wav
    case caf
}

struct SpeechSourceMetadata: Equatable, Sendable {
    var kind: String?
    var label: String?
    var taskId: String?
    var sessionId: String?
}

struct SpeechVoiceSettings: Equatable, Sendable {
    var stability: Double?
    var similarityBoost: Double?
    var style: Double?
    var useSpeakerBoost: Bool?
}

struct SpeechEnqueueRequest: Equatable, Sendable {
    var text: String
    var provider: String
    var model: String?
    var voice: String?
    var rate: Double
    var instructions: String?
    var voiceSettings: SpeechVoiceSettings?
    var cachePolicy: SpeechCachePolicy
    var source: SpeechSourceMetadata?
}

struct SpeechSynthesisRequest: Equatable, Sendable {
    var text: String
    var provider: String
    var model: String?
    var voice: String?
    var rate: Double
    var instructions: String?
    var voiceSettings: SpeechVoiceSettings?
    var cachePolicy: SpeechCachePolicy
}

struct SpeechAudioPayload: Equatable, Sendable {
    var data: Data
    var format: SpeechAudioFormat
    var provider: String
    var voice: String
}

struct SpeechJob: Equatable, Identifiable {
    var id: String
    var state: SpeechJobState
    var text: String
    var provider: String
    var model: String?
    var voice: String?
    var rate: Double
    var instructions: String?
    var voiceSettings: SpeechVoiceSettings?
    var cachePolicy: SpeechCachePolicy
    var source: SpeechSourceMetadata?
    var error: String?
    var currentTime: TimeInterval
    var duration: TimeInterval
    var createdAt: Date
    var generation: UInt64
    var playbackDeadline: Date? = nil

    var progress: Double? {
        guard duration > 0 else { return nil }
        return min(max(currentTime / duration, 0), 1)
    }
}

struct SpeechSnapshot: Equatable {
    var current: SpeechJob?
    var queued: [SpeechJob]
    var recent: [SpeechJob]
    var failure: SpeechJob? = nil
}

struct SpeechVoiceInfo: Equatable, Identifiable {
    var id: String
    var label: String
    var provider: String
    var available: Bool
    var isDefault: Bool
}

struct SpeechQueueLimits: Equatable, Sendable {
    var maxJobs: Int
    var maxTextCharacters: Int
    var maxInstructionsCharacters: Int
    var maxSourceFieldCharacters: Int
    var maxRecentJobs: Int

    static let `default` = SpeechQueueLimits(
        maxJobs: 32,
        maxTextCharacters: 8_000,
        maxInstructionsCharacters: 1_000,
        maxSourceFieldCharacters: 200,
        maxRecentJobs: 8
    )
}

enum SpeechQueueError: LocalizedError, Equatable {
    case emptyText
    case textTooLong(limit: Int)
    case instructionsTooLong(limit: Int)
    case queueFull(limit: Int)
    case unknownProvider(String)
    case invalidCachePolicy(String)
    case remoteAudioForbidden
    case sourceLinkForbidden
    case runtimeUnavailable
    case nothingToPause
    case nothingToResume
    case nothingToSeek
    case jobMismatch(String)
    case providerFailed(String)
    case invalidRate

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Speech text is required"
        case .textTooLong(let limit):
            return "Speech text exceeds \(limit) characters"
        case .instructionsTooLong(let limit):
            return "Speech instructions exceed \(limit) characters"
        case .queueFull(let limit):
            return "Speech queue is full (\(limit) jobs)"
        case .unknownProvider(let provider):
            return "Unknown speech provider: \(provider)"
        case .invalidCachePolicy(let value):
            return "Invalid cachePolicy: \(value). Use reuse or fresh"
        case .remoteAudioForbidden:
            return "Speech enqueue does not fetch remote audio"
        case .sourceLinkForbidden:
            return "Speech enqueue does not open source links"
        case .runtimeUnavailable:
            return "Speech runtime is not installed"
        case .nothingToPause:
            return "Nothing is playing"
        case .nothingToResume:
            return "Nothing is paused"
        case .nothingToSeek:
            return "Nothing is playing or paused"
        case .jobMismatch(let id):
            return "Speech job \(id) is not the active job"
        case .providerFailed(let message):
            return message
        case .invalidRate:
            return "Speech rate must be between 0.25 and 4.0"
        }
    }
}

extension SpeechJob {
    func json() -> JSON {
        var fields: [String: JSON] = [
            "id": .string(id),
            "state": .string(state.rawValue),
            "text": .string(text),
            "provider": .string(provider),
            "rate": .double(rate),
            "cachePolicy": .string(cachePolicy.rawValue),
            "currentTime": .double(currentTime),
            "duration": .double(duration),
            "createdAt": .double(createdAt.timeIntervalSince1970),
        ]
        if let model { fields["model"] = .string(model) }
        if let voice { fields["voice"] = .string(voice) }
        if let error { fields["error"] = .string(error) }
        if let progress { fields["progress"] = .double(progress) }
        if let source {
            var sourceFields: [String: JSON] = [:]
            if let kind = source.kind { sourceFields["kind"] = .string(kind) }
            if let label = source.label { sourceFields["label"] = .string(label) }
            if let taskId = source.taskId { sourceFields["taskId"] = .string(taskId) }
            if let sessionId = source.sessionId { sourceFields["sessionId"] = .string(sessionId) }
            if !sourceFields.isEmpty {
                fields["source"] = .object(sourceFields)
            }
        }
        return .object(fields)
    }
}

extension SpeechSnapshot {
    func json() -> JSON {
        .object([
            "current": current?.json() ?? .null,
            "failure": failure?.json() ?? .null,
            "queued": .array(queued.map { $0.json() }),
            "recent": .array(recent.map { $0.json() }),
        ])
    }
}

extension SpeechVoiceInfo {
    func json() -> JSON {
        .object([
            "id": .string(id),
            "label": .string(label),
            "provider": .string(provider),
            "available": .bool(available),
            "default": .bool(isDefault),
        ])
    }
}

enum SpeechErrorRedactor {
    static func message(from error: Error) -> String {
        redact(error.localizedDescription)
    }

    static func redact(_ raw: String) -> String {
        var message = raw
        let patterns = [
            #"Bearer\s+[A-Za-z0-9._\-]+"#,
            #"sk-[A-Za-z0-9_\-]+"#,
            #"sk-ant-[A-Za-z0-9_\-]+"#,
            #"sk-or-[A-Za-z0-9_\-]+"#,
            #"xi-api-key:\s*\S+"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(message.startIndex..<message.endIndex, in: message)
                message = regex.stringByReplacingMatches(in: message, options: [], range: range, withTemplate: "[redacted]")
            }
        }
        return message
    }
}
