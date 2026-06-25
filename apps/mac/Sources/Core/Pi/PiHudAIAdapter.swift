import Foundation
import HudsonAI

// Bridges the local `pi --mode rpc` runtime into HudsonKit's HudAIClient as a
// first-class provider adapter. This is the architecture the workspace assistant
// is moving to: HudAIClient is the single chat surface, and pi — with its own
// multi-provider routing and auth — becomes "one of the many providers" behind
// it, exactly like the HTTP adapters (OpenAI/Anthropic/OpenRouter), only driven
// over RPC instead of a URL.
//
// Two impedance mismatches with the HTTP adapters, handled deliberately:
//   1. State. pi sessions are stateful (the session dir holds prior turns), but
//      HudAIRequest carries the full message history each call. We send only the
//      latest user turn as pi's `prompt`; pi already remembers the rest.
//   2. Auth. pi authenticates its own downstream providers (OAuth device-code,
//      API keys). So this adapter ignores HudAIAdapterContext credentials — the
//      HudAI credential vault is not in the loop for pi. (Surfacing pi's auth
//      through HudAI credentials is a separate, later step.)

extension HudAIProviderID {
    static let pi = HudAIProviderID(rawValue: "pi")
}

/// `HudAIClient` requires a credential source, but the pi adapter never queries
/// it — pi owns auth for its downstream providers. This satisfies the type
/// without putting the HudAI vault in the loop. (Replaced when pi's auth is
/// surfaced through HudAI credentials.)
struct NullHudAICredentialSource: HudAICredentialSource {
    func get(_ key: String) async throws -> Data? { nil }
}

struct PiHudAIAdapter: HudAIProviderAdapter, @unchecked Sendable {
    let providerID: HudAIProviderID
    let displayName: String
    let defaultModel: String
    let credentialKey: String

    /// Supplies a started/ready `PiRpcRuntime` configured for the desired
    /// provider/model/session. The lattices chat session owns runtime lifecycle,
    /// so the adapter asks for one on demand rather than constructing it.
    private let runtimeProvider: @Sendable () -> PiRpcRuntime

    init(
        providerID: HudAIProviderID = .pi,
        displayName: String = "Pi",
        defaultModel: String = "",
        credentialKey: String = "pi",
        runtimeProvider: @escaping @Sendable () -> PiRpcRuntime
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.defaultModel = defaultModel
        self.credentialKey = credentialKey
        self.runtimeProvider = runtimeProvider
    }

    // MARK: - HudAIProviderAdapter

    func complete(_ request: HudAIRequest, context: HudAIAdapterContext) async throws -> HudAIResponse {
        let model = request.model ?? defaultModel
        let prompt = Self.promptText(from: request)
        let runtime = runtimeProvider()
        let text: String = try await withCheckedThrowingContinuation { continuation in
            runtime.promptAndFetchAssistantText(prompt, timeout: context.defaults.timeout) { result in
                switch result {
                case .success(let text): continuation.resume(returning: text)
                case .failure(let error): continuation.resume(throwing: Self.map(error))
                }
            }
        }
        return Self.response(id: UUID().uuidString, model: model, text: text)
    }

    func stream(_ request: HudAIRequest, context: HudAIAdapterContext) -> AsyncThrowingStream<HudAIStreamEvent, Error> {
        let model = request.model ?? defaultModel
        let prompt = Self.promptText(from: request)
        let runtime = runtimeProvider()
        let requestID = UUID().uuidString

        return AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID, provider: providerID, model: model))

            // pi may emit either incremental `text_delta`s or full-text snapshots.
            // Normalize both into HudAI textDeltas; for snapshots we diff against
            // what we've already emitted so the consumer only ever sees forward
            // deltas (never a re-sent prefix).
            var emitted = ""

            runtime.promptAndFetchAssistantText(
                prompt,
                onEvent: { event in
                    if let delta = PiRpcRuntime.streamingDelta(from: event), !delta.isEmpty {
                        emitted += delta
                        continuation.yield(.textDelta(contentBlockID: "message_0", text: delta))
                    } else if let snapshot = PiRpcRuntime.streamingSnapshot(from: event) {
                        if snapshot.count > emitted.count, snapshot.hasPrefix(emitted) {
                            let delta = String(snapshot.dropFirst(emitted.count))
                            emitted = snapshot
                            continuation.yield(.textDelta(contentBlockID: "message_0", text: delta))
                        } else if snapshot != emitted {
                            emitted = snapshot
                        }
                    } else if event["type"] as? String == "tool_execution_start",
                              let toolName = event["toolName"] as? String {
                        let toolID = event["toolCallId"] as? String ?? event["id"] as? String ?? "pi_tool_\(toolName)"
                        continuation.yield(.toolCallStarted(toolCallID: toolID, name: toolName))
                    }
                },
                timeout: context.defaults.timeout
            ) { result in
                switch result {
                case .success(let text):
                    let final = text.isEmpty ? emitted : text
                    continuation.yield(.completed(Self.response(id: requestID, model: model, text: final)))
                    continuation.finish()
                case .failure(let error):
                    let mapped = Self.map(error)
                    continuation.yield(.failed(mapped))
                    continuation.finish(throwing: mapped)
                }
            }
        }
    }

    func listModels(context: HudAIAdapterContext) async throws -> [HudAIModelInfo] {
        // pi owns provider/model routing; HudAI-side model enumeration is not
        // wired yet. Surface the default so the picker has at least one entry.
        guard !defaultModel.isEmpty else { return [] }
        return [HudAIModelInfo(id: defaultModel, provider: providerID, displayName: displayName)]
    }

    // MARK: - Helpers

    /// pi is stateful per session, so a turn is just the latest user message.
    private static func promptText(from request: HudAIRequest) -> String {
        guard let lastUser = request.messages.last(where: { $0.role == .user }) else {
            return request.messages.flatMap { textParts($0.content) }.joined(separator: "\n")
        }
        return textParts(lastUser.content).joined(separator: "\n")
    }

    private static func textParts(_ content: [HudAIContentPart]) -> [String] {
        content.compactMap { part in
            if case .text(let text) = part { return text }
            return nil
        }
    }

    private static func response(id: String, model: String, text: String) -> HudAIResponse {
        HudAIResponse(
            id: id,
            provider: .pi,
            model: model,
            text: text,
            content: text.isEmpty ? [] : [.text(text)],
            toolCalls: [],
            usage: HudAIUsage(),
            finishReason: .stop
        )
    }

    private static func map(_ error: Error) -> HudAIError {
        if let error = error as? HudAIError { return error }
        if let runtimeError = error as? PiRpcRuntime.RuntimeError {
            switch runtimeError {
            case .timedOut(let detail):
                return .timeout(provider: .pi, message: detail)
            default:
                return .providerProtocolError(provider: .pi, requestID: nil, message: runtimeError.localizedDescription)
            }
        }
        return .providerProtocolError(provider: .pi, requestID: nil, message: error.localizedDescription)
    }
}
