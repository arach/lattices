import AppKit
import CryptoKit
import Foundation
import Security

struct TalkieDeckShortcutDefinition: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String
    let accentToken: String
}

struct TalkieDeckSnapshot {
    var isRunning: Bool
    var isReachable: Bool
    var activeShortcutIDs: Set<String>
    var detailByShortcutID: [String: String]
    var recentResultByShortcutID: [String: String]
    var lastError: String?

    static let unavailable = TalkieDeckSnapshot(
        isRunning: false,
        isReachable: false,
        activeShortcutIDs: [],
        detailByShortcutID: [:],
        recentResultByShortcutID: [:],
        lastError: nil
    )
}

struct TalkieDeckTriggerResult {
    let summary: String
    let detail: String?
    let shortcutID: String
}

enum TalkieDeckProviderError: LocalizedError {
    case notInstalled
    case notRunning
    case bridgeUnavailable(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Talkie is not installed on this Mac."
        case .notRunning:
            return "Talkie is not running on this Mac."
        case .bridgeUnavailable(let message):
            return "Talkie bridge unavailable: \(message)"
        case .requestFailed(let message):
            return message
        }
    }
}

private struct TalkieLocalClientAccessRequest: Encodable {
    let clientId: String
    let displayName: String
    let publicKey: String
    let requestedCapabilities: [String]
}

private struct TalkieLocalClientAccessResponse: Decodable {
    let ok: Bool
    let status: String
    let clientId: String?
    let grantedCapabilities: [String]
    let fingerprint: String?
    let message: String?
}

final class TalkieDeckProvider: @unchecked Sendable {
    static let shared = TalkieDeckProvider()

    static let talkiePageSlotIDs: [String] = [
        "talkie-dictate", "talkie-record", "talkie-settings", "talkie-search",
        "deck-app-previous", "deck-app-next", "deck-window-previous", "deck-window-next",
        "mac-claude", "talkie-agent", "talkie-ssh", "mac-sessions",
        "mac-windows", "talkie-keyboard", "talkie-command", "talkie-memos",
    ]

    static let shortcuts: [TalkieDeckShortcutDefinition] = [
        .init(id: "talkie-dictate", title: "Dictate", subtitle: "Start or stop Talkie dictation.", iconSystemName: "mic.fill", accentToken: "red"),
        .init(id: "talkie-record", title: "Record Memo", subtitle: "Start or stop a Talkie memo.", iconSystemName: "square.and.pencil", accentToken: "violet"),
        .init(id: "talkie-settings", title: "Voice Command", subtitle: "Start Talkie's voice command capture.", iconSystemName: "waveform.badge.mic", accentToken: "pink"),
        .init(id: "talkie-search", title: "Search", subtitle: "Open Talkie search on the Mac.", iconSystemName: "magnifyingglass", accentToken: "blue"),
        .init(id: "mac-claude", title: "Claude", subtitle: "Open Talkie's Claude console.", iconSystemName: "sparkles", accentToken: "violet"),
        .init(id: "talkie-agent", title: "Pi", subtitle: "Open Talkie's Pi console.", iconSystemName: "circle.grid.cross", accentToken: "blue"),
        .init(id: "talkie-ssh", title: "Shell", subtitle: "Open the Talkie Shell tab.", iconSystemName: "terminal", accentToken: "green"),
        .init(id: "mac-sessions", title: "Workflows", subtitle: "Open Talkie's workflow picker.", iconSystemName: "wand.and.stars", accentToken: "teal"),
        .init(id: "mac-windows", title: "Desktop Preview", subtitle: "Start Talkie's desktop capture flow.", iconSystemName: "display", accentToken: "green"),
        .init(id: "talkie-keyboard", title: "Record Screen", subtitle: "Start Talkie's screen recording flow.", iconSystemName: "record.circle", accentToken: "red"),
        .init(id: "talkie-command", title: "Palette", subtitle: "Open Talkie's command palette.", iconSystemName: "command", accentToken: "violet"),
        .init(id: "talkie-memos", title: "Memos", subtitle: "Open Talkie's memo library.", iconSystemName: "waveform", accentToken: "pink"),
        .init(id: "talkie-home", title: "Home", subtitle: "Bring Talkie home to the front.", iconSystemName: "house", accentToken: "violet"),
        .init(id: "talkie-pending", title: "Pending", subtitle: "Open Talkie's pending actions.", iconSystemName: "hourglass", accentToken: "amber"),
        .init(id: "talkie-recent", title: "Recents", subtitle: "Open Talkie's recent activity.", iconSystemName: "clock.arrow.circlepath", accentToken: "amber"),
        .init(id: "talkie-devices", title: "Pairing", subtitle: "Open Talkie's companion settings.", iconSystemName: "ipad.and.iphone", accentToken: "teal"),
        .init(id: "iterm-dictate", title: "New iTerm", subtitle: "Open iTerm, then arm Talkie dictation.", iconSystemName: "command.circle", accentToken: "amber"),
        .init(id: "deck-app-previous", title: "Prev App", subtitle: "Ask Talkie to switch to the previous app.", iconSystemName: "square.stack.3d.up", accentToken: "amber"),
        .init(id: "deck-app-next", title: "Next App", subtitle: "Ask Talkie to switch to the next app.", iconSystemName: "square.stack.3d.up.fill", accentToken: "amber"),
        .init(id: "deck-window-previous", title: "Prev Window", subtitle: "Ask Talkie to switch to the previous window.", iconSystemName: "rectangle.on.rectangle", accentToken: "teal"),
        .init(id: "deck-window-next", title: "Next Window", subtitle: "Ask Talkie to switch to the next window.", iconSystemName: "rectangle.on.rectangle", accentToken: "teal"),
        .init(id: "deck-tab-previous", title: "Prev Tab", subtitle: "Ask Talkie to switch to the previous tab.", iconSystemName: "arrow.left.square", accentToken: "violet"),
        .init(id: "deck-tab-next", title: "Next Tab", subtitle: "Ask Talkie to switch to the next tab.", iconSystemName: "arrow.right.square", accentToken: "violet"),
        .init(id: "deck-space-left", title: "Space Left", subtitle: "Ask Talkie to move one Space left.", iconSystemName: "arrow.left", accentToken: "teal"),
        .init(id: "deck-space-right", title: "Space Right", subtitle: "Ask Talkie to move one Space right.", iconSystemName: "arrow.right", accentToken: "teal"),
    ]

    private struct CompanionShortcutTriggerRequest: Encodable {
        let shortcutId: String
    }

    private struct CompanionShortcutTriggerResponse: Decodable {
        let ok: Bool
        let handledShortcutId: String?
        let message: String?
        let error: String?
        let runtimeState: CompanionShortcutRuntimeState?
    }

    private struct CompanionShortcutRuntimeState: Decodable {
        let shortcutId: String
        let phase: String
        let canStop: Bool
        let detail: String?
        let elapsedSeconds: Double?
        let signalLevel: Double?
    }

    private struct CompanionShortcutRecentResult: Decodable {
        let shortcutId: String
        let resultText: String
        let completedAt: String
    }

    private struct CompanionRuntimeStateResponse: Decodable {
        let shortcutStates: [CompanionShortcutRuntimeState]
        let recentResults: [CompanionShortcutRecentResult]
    }

    private let baseURL = URL(string: "http://127.0.0.1:8766/")!
    private let bundleIdentifiers = [
        "to.talkie.app.mac.dev",
        "to.talkie.app.mac",
    ]
    private let snapshotLock = NSLock()
    private var cachedSnapshot: TalkieDeckSnapshot = .unavailable
    private var cachedSnapshotAt: Date = .distantPast
    private let snapshotCacheLifetime: TimeInterval = 0.9
    private let authorizationLock = NSLock()
    private var localClientAccessDeniedUntil: Date?

    private init() {}

    static func shortcut(for id: String) -> TalkieDeckShortcutDefinition? {
        shortcuts.first(where: { $0.id == id })
    }

    func snapshot(timeout: TimeInterval = 0.28) -> TalkieDeckSnapshot {
        let now = Date()
        snapshotLock.lock()
        let cached = cachedSnapshot
        let cachedAt = cachedSnapshotAt
        snapshotLock.unlock()

        if now.timeIntervalSince(cachedAt) < snapshotCacheLifetime {
            return cached
        }

        let fresh = fetchSnapshot(timeout: timeout)
        snapshotLock.lock()
        cachedSnapshot = fresh
        cachedSnapshotAt = now
        snapshotLock.unlock()
        return fresh
    }

    func trigger(shortcutID: String) throws -> TalkieDeckTriggerResult {
        guard isTalkieRunning else {
            if openTalkie() {
                invalidateSnapshotCache()
                throw TalkieDeckProviderError.bridgeUnavailable("Talkie is opening. Try again in a moment.")
            }
            throw TalkieDeckProviderError.notRunning
        }

        let body = try JSONEncoder().encode(CompanionShortcutTriggerRequest(shortcutId: shortcutID))
        let data = try request(path: "companion/trigger", method: "POST", body: body, timeout: 1.8)
        let response = try JSONDecoder().decode(CompanionShortcutTriggerResponse.self, from: data)

        guard response.ok else {
            throw TalkieDeckProviderError.requestFailed(response.error ?? "Talkie could not run \(shortcutID).")
        }

        invalidateSnapshotCache()

        let handledID = response.handledShortcutId ?? shortcutID
        let detail = response.runtimeState.map { formattedDetail(for: $0) }

        return TalkieDeckTriggerResult(
            summary: response.message ?? "Ran \(title(for: handledID))",
            detail: detail,
            shortcutID: handledID
        )
    }

    @discardableResult
    func openTalkie() -> Bool {
        if let runningApp = runningTalkieApplication {
            runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return true
        }

        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
               NSWorkspace.shared.open(url) {
                return true
            }
        }

        for scheme in ["talkie-dev://", "talkie://"] {
            if let url = URL(string: scheme), NSWorkspace.shared.open(url) {
                return true
            }
        }

        return false
    }

    var isTalkieRunning: Bool {
        runningTalkieApplication != nil
    }

    private func fetchSnapshot(timeout: TimeInterval) -> TalkieDeckSnapshot {
        let running = isTalkieRunning
        guard running else {
            return .unavailable
        }

        do {
            let data = try request(path: "companion/runtime-state", timeout: timeout)
            let response = try JSONDecoder().decode(CompanionRuntimeStateResponse.self, from: data)
            var details: [String: String] = [:]
            var activeIDs = Set<String>()
            for state in response.shortcutStates {
                activeIDs.insert(state.shortcutId)
                details[state.shortcutId] = formattedDetail(for: state)
            }

            var recentResults: [String: String] = [:]
            for result in response.recentResults {
                recentResults[result.shortcutId] = result.resultText
            }

            return TalkieDeckSnapshot(
                isRunning: true,
                isReachable: true,
                activeShortcutIDs: activeIDs,
                detailByShortcutID: details,
                recentResultByShortcutID: recentResults,
                lastError: nil
            )
        } catch {
            return TalkieDeckSnapshot(
                isRunning: true,
                isReachable: false,
                activeShortcutIDs: [],
                detailByShortcutID: [:],
                recentResultByShortcutID: [:],
                lastError: error.localizedDescription
            )
        }
    }

    private var runningTalkieApplication: NSRunningApplication? {
        for bundleIdentifier in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                return app
            }
        }
        return nil
    }

    private func invalidateSnapshotCache() {
        snapshotLock.lock()
        cachedSnapshotAt = .distantPast
        snapshotLock.unlock()
    }

    private func title(for shortcutID: String) -> String {
        Self.shortcut(for: shortcutID)?.title ?? shortcutID
    }

    private func formattedDetail(for state: CompanionShortcutRuntimeState) -> String {
        var parts: [String] = []
        if let detail = state.detail, !detail.isEmpty {
            parts.append(detail)
        } else {
            parts.append(state.phase.capitalized)
        }

        if let elapsedSeconds = state.elapsedSeconds {
            let total = max(0, Int(elapsedSeconds.rounded(.down)))
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }

        if state.canStop {
            parts.append("tap again to stop")
        }

        return parts.joined(separator: " · ")
    }

    private func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval
    ) throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw TalkieDeckProviderError.requestFailed("Invalid Talkie bridge path: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        try signTalkieRequest(&request, method: method, url: url, body: body ?? Data())
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            return try perform(request, timeout: timeout)
        } catch TalkieDeckProviderError.bridgeUnavailable(let message)
            where message.contains("HTTP 401") || message.contains("HTTP 403") {
            try requestLocalClientAccess(timeout: 45)
            var retry = URLRequest(url: url)
            retry.httpMethod = method
            retry.timeoutInterval = timeout
            retry.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            try signTalkieRequest(&retry, method: method, url: url, body: body ?? Data())
            if let body {
                retry.httpBody = body
                retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            return try perform(retry, timeout: timeout)
        }
    }

    private func perform(_ request: URLRequest, timeout: TimeInterval) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>!
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            } else {
                result = .failure(TalkieDeckProviderError.bridgeUnavailable("empty response"))
            }
            semaphore.signal()
        }
        task.resume()

        guard semaphore.wait(timeout: .now() + timeout + 0.2) == .success else {
            task.cancel()
            throw TalkieDeckProviderError.bridgeUnavailable("request timed out")
        }

        let (data, response) = try result.get()
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TalkieDeckProviderError.bridgeUnavailable("HTTP \(http.statusCode): \(message)")
        }
        return data
    }

    private func signTalkieRequest(_ request: inout URLRequest, method: String, url: URL, body: Data) throws {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString
        let bodyHash = Self.sha256Hex(body)
        let canonical = "\(method)\n\(Self.pathWithQuery(for: url))\n\(timestamp)\n\(nonce)\n\(bodyHash)"
        let identity = TalkieLocalClientIdentity.shared

        request.setValue(identity.clientID, forHTTPHeaderField: "X-Talkie-Client-ID")
        request.setValue(timestamp, forHTTPHeaderField: "X-Talkie-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Talkie-Nonce")
        request.setValue(bodyHash, forHTTPHeaderField: "X-Talkie-Body-SHA256")
        request.setValue(try identity.signatureBase64(for: canonical), forHTTPHeaderField: "X-Talkie-Signature")
    }

    private func requestLocalClientAccess(timeout: TimeInterval) throws {
        authorizationLock.lock()
        let deniedUntil = localClientAccessDeniedUntil
        authorizationLock.unlock()

        if let deniedUntil, deniedUntil > Date() {
            throw TalkieDeckProviderError.bridgeUnavailable("Talkie local access was denied.")
        }

        let identity = TalkieLocalClientIdentity.shared
        let accessRequest = TalkieLocalClientAccessRequest(
            clientId: identity.clientID,
            displayName: identity.displayName,
            publicKey: identity.publicKeyBase64,
            requestedCapabilities: identity.requestedCapabilities
        )

        let body = try JSONEncoder().encode(accessRequest)
        guard let url = URL(string: "local-clients/request-access", relativeTo: baseURL)?.absoluteURL else {
            throw TalkieDeckProviderError.requestFailed("Invalid Talkie access request path")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let responseData: Data
        do {
            responseData = try perform(request, timeout: timeout)
        } catch {
            authorizationLock.lock()
            localClientAccessDeniedUntil = Date().addingTimeInterval(600)
            authorizationLock.unlock()
            throw error
        }

        let response = try JSONDecoder().decode(TalkieLocalClientAccessResponse.self, from: responseData)
        guard response.ok else {
            authorizationLock.lock()
            localClientAccessDeniedUntil = Date().addingTimeInterval(600)
            authorizationLock.unlock()
            throw TalkieDeckProviderError.bridgeUnavailable(response.message ?? "Talkie local access was not approved.")
        }

        authorizationLock.lock()
        localClientAccessDeniedUntil = nil
        authorizationLock.unlock()
    }

    private static func pathWithQuery(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.path.isEmpty ? "/" : url.path
        }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        guard let query = components.percentEncodedQuery, !query.isEmpty else {
            return path
        }
        return "\(path)?\(query)"
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class TalkieLocalClientIdentity: @unchecked Sendable {
    static let shared = TalkieLocalClientIdentity()

    let clientID = "dev.lattices.app.talkie-local-client"
    let displayName = "Lattices"
    let requestedCapabilities = [
        "companion.runtimeState",
        "companion.trigger",
    ]

    private let privateKey: P256.Signing.PrivateKey

    private init() {
        self.privateKey = Self.loadOrCreatePrivateKey()
    }

    var publicKeyBase64: String {
        Data(privateKey.publicKey.x963Representation).base64EncodedString()
    }

    func signatureBase64(for canonicalRequest: String) throws -> String {
        let signature = try privateKey.signature(for: Data(canonicalRequest.utf8))
        return signature.derRepresentation.base64EncodedString()
    }

    private static func loadOrCreatePrivateKey() -> P256.Signing.PrivateKey {
        if
            let stored = TalkieDeckKeychain.load(service: KeychainKey.service, account: KeychainKey.account),
            let key = try? P256.Signing.PrivateKey(rawRepresentation: stored)
        {
            return key
        }

        let key = P256.Signing.PrivateKey()
        _ = TalkieDeckKeychain.save(key.rawRepresentation, service: KeychainKey.service, account: KeychainKey.account)
        return key
    }

    private enum KeychainKey {
        static let service = "dev.lattices.app.talkie.local-client"
        static let account = "p256-signing-key-v1"
    }
}

private enum TalkieDeckKeychain {
    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func save(_ data: Data, service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        return addStatus == errSecSuccess
    }
}
