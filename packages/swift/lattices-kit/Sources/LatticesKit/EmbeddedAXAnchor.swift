import ApplicationServices
import CoreGraphics
import Foundation

/// One node of an accessibility tree, reduced to what anchoring needs. The
/// live implementation wraps `AXUIElement`; tests supply synthetic trees.
protocol EmbeddedAXAnchorNode {
    var anchorRole: String? { get }
    var anchorValue: String? { get }
    /// `.failed` means the children couldn't be read, so the subtree is
    /// unknown — distinct from a leaf, which has none.
    func anchorChildren() -> EmbeddedAXChildren<Self>
}

enum EmbeddedAXChildren<Node> {
    case leaf
    case children([Node])
    case failed
}

/// The application side of anchoring: its tree root, the
/// `AXEnhancedUserInterface` flag, and focusing a found node.
protocol EmbeddedAXAnchorApplication {
    associatedtype Node: EmbeddedAXAnchorNode
    var root: Node { get }
    /// `nil` when the flag can't be read.
    func enhancedUserInterface() -> Bool?
    /// Returns whether the write succeeded.
    func setEnhancedUserInterface(_ enabled: Bool) -> Bool
    /// Whether `node` belongs to this application's process.
    func owns(_ node: Node) -> Bool
    func focus(_ node: Node) -> Bool
}

struct EmbeddedAXAnchorLimits: Equatable, Sendable {
    var maxDepth: Int
    var maxElements: Int

    static let standard = EmbeddedAXAnchorLimits(maxDepth: 64, maxElements: 20_000)
}

enum EmbeddedAXAnchorSearch<Node> {
    case unique(Node, depth: Int)
    case none
    case ambiguous
    /// The tree wasn't fully read, so a lone match can't be proven unique.
    case incomplete(String)
}

enum EmbeddedAXAnchor {
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// Breadth-first search for text elements whose normalized value equals
    /// `expected`. Answers `.unique` only after reading the whole tree within
    /// `limits`; stops early at a second match.
    static func search<Node: EmbeddedAXAnchorNode>(
        from root: Node,
        holding expected: String,
        roles: Set<String>,
        limits: EmbeddedAXAnchorLimits
    ) -> EmbeddedAXAnchorSearch<Node> {
        var queue: [(node: Node, depth: Int)] = [(root, 0)]
        var head = 0
        var hit: (node: Node, depth: Int)?

        while head < queue.count {
            guard head < limits.maxElements else {
                return .incomplete("The accessibility tree has more than \(limits.maxElements) elements.")
            }
            let (node, depth) = queue[head]
            head += 1

            if let role = node.anchorRole, roles.contains(role),
               let value = node.anchorValue, normalized(value) == expected {
                if hit != nil { return .ambiguous }
                hit = (node, depth)
            }

            switch node.anchorChildren() {
            case .leaf:
                continue
            case .failed:
                return .incomplete("Couldn't read part of the accessibility tree.")
            case .children(let children):
                guard !children.isEmpty else { continue }
                guard depth < limits.maxDepth else {
                    return .incomplete("The accessibility tree is deeper than \(limits.maxDepth) levels.")
                }
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }

        guard let hit else { return .none }
        return .unique(hit.node, depth: hit.depth)
    }

    /// Focuses the single text element in `app` holding `value`. When nothing
    /// matches and `AXEnhancedUserInterface` is off, turns it on so Chromium
    /// and Electron publish their web content, polls up to `exposeTimeout`,
    /// and turns it back off before returning or throwing.
    static func focusUnique<App: EmbeddedAXAnchorApplication>(
        holding value: String,
        in app: App,
        roles: Set<String>,
        limits: EmbeddedAXAnchorLimits,
        exposeTimeout: TimeInterval,
        pollInterval: TimeInterval = 0.25,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) throws -> (node: App.Node, depth: Int) {
        let expected = normalized(value)
        guard !expected.isEmpty else {
            throw EmbeddedLatticesError.elementNotFound("An empty value can't anchor an element.")
        }
        guard !roles.isEmpty else {
            throw EmbeddedLatticesError.elementNotFound("No element roles to match.")
        }

        var result = search(from: app.root, holding: expected, roles: roles, limits: limits)

        var exposed = false
        defer {
            if exposed { _ = app.setEnhancedUserInterface(false) }
        }
        if case .none = result, app.enhancedUserInterface() == false {
            exposed = app.setEnhancedUserInterface(true)
            if exposed {
                let deadline = now().addingTimeInterval(max(0, exposeTimeout))
                while case .none = result, now() < deadline {
                    sleep(pollInterval)
                    result = search(from: app.root, holding: expected, roles: roles, limits: limits)
                }
            }
        }

        switch result {
        case .unique(let node, let depth):
            guard app.owns(node) else {
                throw EmbeddedLatticesError.elementNotFound("The matching element belongs to another process.")
            }
            guard app.focus(node) else {
                throw EmbeddedLatticesError.elementNotFound("Couldn't focus the element holding that text.")
            }
            return (node, depth)
        case .none:
            throw EmbeddedLatticesError.elementNotFound("No text element holds that text.")
        case .ambiguous:
            throw EmbeddedLatticesError.elementNotFound("More than one text element holds that text; expected exactly 1.")
        case .incomplete(let reason):
            throw EmbeddedLatticesError.elementNotFound(reason)
        }
    }
}

struct LiveAXAnchorNode: EmbeddedAXAnchorNode {
    let element: AXUIElement

    var anchorRole: String? { string(kAXRoleAttribute) }
    var anchorValue: String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref) == .success,
              let string = ref as? String
        else { return nil }
        return string
    }

    func anchorChildren() -> EmbeddedAXChildren<LiveAXAnchorNode> {
        var ref: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) {
        case .success:
            guard let children = ref as? [AXUIElement] else { return .failed }
            return .children(children.map(LiveAXAnchorNode.init(element:)))
        case .noValue, .attributeUnsupported:
            return .leaf
        default:
            return .failed
        }
    }

    private func string(_ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}

struct LiveAXAnchorApplication: EmbeddedAXAnchorApplication {
    let pid: pid_t
    let root: LiveAXAnchorNode

    init(pid: pid_t) {
        self.pid = pid
        self.root = LiveAXAnchorNode(element: AXUIElementCreateApplication(pid))
    }

    private static let enhanced = "AXEnhancedUserInterface" as CFString

    func enhancedUserInterface() -> Bool? {
        var ref: CFTypeRef?
        switch AXUIElementCopyAttributeValue(root.element, Self.enhanced, &ref) {
        case .success:
            return ref as? Bool
        case .noValue, .attributeUnsupported:
            return false
        default:
            return nil
        }
    }

    func setEnhancedUserInterface(_ enabled: Bool) -> Bool {
        AXUIElementSetAttributeValue(
            root.element,
            Self.enhanced,
            enabled ? kCFBooleanTrue : kCFBooleanFalse
        ) == .success
    }

    func owns(_ node: LiveAXAnchorNode) -> Bool {
        var owner: pid_t = 0
        return AXUIElementGetPid(node.element, &owner) == .success && owner == pid
    }

    func focus(_ node: LiveAXAnchorNode) -> Bool {
        AXUIElementSetAttributeValue(node.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }
}

/// Builds a key press and hands it to `post` addressed to one process. There
/// is deliberately no path to a session- or HID-wide tap here.
enum EmbeddedProcessKeyPress {
    static func press(
        _ shortcut: String,
        pid: pid_t,
        post: (CGEvent, pid_t) -> Void = { $0.postToPid($1) }
    ) throws {
        guard pid > 0 else {
            throw EmbeddedLatticesError.invalidConfig("A key press needs a target process; got pid \(pid).")
        }
        let parsed = try EmbeddedShortcut.parse(shortcut)
        // A private source keeps the user's held modifiers out of the event.
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: parsed.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: parsed.keyCode, keyDown: false)
        else {
            throw EmbeddedLatticesError.accessibilityUnavailable
        }
        down.flags = parsed.flags
        up.flags = parsed.flags
        post(down, pid)
        post(up, pid)
    }
}
