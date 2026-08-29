import AppKit
import Foundation
import SwiftUI

// MARK: - The painted palette

/// One theme, flattened and resolved, ready to paint from.
///
/// Colours are built once per theme change rather than per access. The app
/// reads a token roughly five hundred times per pass over a dense screen, and
/// building a dynamic `NSColor` at each of those would allocate through a
/// scroll.
final class ActionThemeSnapshot: Sendable {
    let definition: ActionThemeDefinition
    /// Indexed by `ActionToken.slot`.
    let colors: [Color]
    /// The same table for the AppKit side — window backgrounds, menu-bar
    /// artwork, overlay panels. Built alongside rather than converted on demand
    /// so both sides of the app are looking at one resolved theme.
    let nsColors: [NSColor]

    init(_ definition: ActionThemeDefinition) {
        self.definition = definition
        let tokens = definition.tokens()
        let resolved = ActionToken.allCases.map { tokens[$0] ?? ActionThemeColor(ActionRGBA(0, 0, 0, 0)) }
        colors = resolved.map(\.color)
        nsColors = resolved.map(\.nsColor)
    }

    var identity: ActionThemeIdentity { definition.theme.identity }
    var metrics: ActionThemeMetrics { definition.theme.metrics }
    var type: ActionThemeType { definition.theme.type }
}

/// The globally installed theme.
///
/// Separate from `ActionThemeStore` on purpose: the store is main-actor UI
/// state, while this is read from anywhere a colour is needed, including
/// AppKit controllers that are not views. The lock is uncontended in practice —
/// installs happen on the main thread, and a read is a pointer copy.
enum ActionThemePalette {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var snapshot = ActionThemeSnapshot(.action)

    static var current: ActionThemeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    static func install(_ definition: ActionThemeDefinition) {
        let next = ActionThemeSnapshot(definition)
        lock.lock()
        snapshot = next
        lock.unlock()
    }

    static func color(_ token: ActionToken) -> Color {
        current.colors[token.slot]
    }

    static func nsColor(_ token: ActionToken) -> NSColor {
        current.nsColors[token.slot]
    }

    /// Posted after a new theme is installed, for the AppKit surfaces that hold
    /// a resolved colour rather than asking for one each time they draw.
    static let didChangeNotification = Notification.Name("ActionThemeDidChange")

    static var metrics: ActionThemeMetrics { current.metrics }
    static var type: ActionThemeType { current.type }
}

// MARK: - Store

/// Enough of a resolved theme to draw it at thumbnail size.
///
/// A theme picker that lists names is asking the operator to remember what
/// "Porcelain" looked like. Eight colours is enough to draw the thing itself:
/// the band across the top, the page under it, a card on the page, two weights
/// of ink on the card, and the accent. That is the same arrangement every
/// screen in the app is made of, at 130 points wide.
struct ActionThemePreview: Equatable, Sendable {
    var band: Color
    var canvas: Color
    var panel: Color
    var edge: Color
    var ink: Color
    var inkSecondary: Color
    var accent: Color
    var deep: Color

    init(tokens: [ActionToken: ActionThemeColor]) {
        func color(_ token: ActionToken) -> Color {
            tokens[token]?.color ?? .clear
        }
        band = color(.railBackground)
        canvas = color(.fieldCanvas)
        panel = color(.fieldPanel)
        edge = color(.fieldPanelEdge)
        ink = color(.fieldInk)
        inkSecondary = color(.fieldInkSecondary)
        accent = color(.fieldAccent)
        deep = color(.fieldDeep)
    }
}

/// What the app knows about one theme on disk.
struct ActionThemeCatalogEntry: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var summary: String?
    var author: String?
    var isBuiltin: Bool
    var url: URL?
    var issues: [ActionThemeIssue]
    var preview: ActionThemePreview

    var isUsable: Bool { ActionThemeValidator.isUsable(issues) }
}

/// Loads themes, keeps the catalogue, and installs the selected one.
///
/// The agent-facing contract is the directory, not an API: drop a `.json` file
/// in `~/Library/Application Support/Action/Themes`, and the app picks it up
/// without being restarted or told. That is deliberate — an agent driving this
/// Mac already has a filesystem and a text editor, and a theme it can iterate on
/// by writing a file and looking at the result is a far shorter loop than one
/// that needs a protocol round-trip per attempt.
@MainActor
final class ActionThemeStore: ObservableObject {
    static let shared = ActionThemeStore()

    static let selectionKey = "Action.ThemeID"

    /// Bumped on every install. Views that paint through the static token
    /// façade have nothing to observe, so they hang an `.id(revision)` off this
    /// and rebuild when it changes.
    @Published private(set) var revision = 0
    @Published private(set) var selectedID: String
    @Published private(set) var catalog: [ActionThemeCatalogEntry] = []
    /// Issues from the theme currently installed. Empty is the good case.
    @Published private(set) var issues: [ActionThemeIssue] = []

    private var watcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: CInt = -1

    /// Where an operator — or an agent — drops a theme.
    var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/Themes", isDirectory: true)
    }

    /// Themes that ship inside the app. Read-only, and searched *after* the
    /// operator's folder, so putting a file with the same id in Application
    /// Support overrides the shipped one rather than colliding with it.
    var bundledDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Themes", isDirectory: true)
    }

    private init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectionKey)
            ?? ActionTheme.action.identity.id
        reload()
        startWatching()
    }

    // MARK: Selection

    func select(_ id: String) {
        selectedID = id
        UserDefaults.standard.set(id, forKey: Self.selectionKey)
        install()
    }

    /// Rereads the directory and reinstalls the selected theme.
    func reload() {
        catalog = loadCatalog()
        install()
    }

    private func install() {
        let resolved = resolveSelected()
        issues = resolved.issues
        guard ActionThemePalette.current.definition != resolved.definition else { return }
        ActionThemePalette.install(resolved.definition)
        revision &+= 1
        NotificationCenter.default.post(name: ActionThemePalette.didChangeNotification, object: nil)
    }

    private func resolveSelected() -> (definition: ActionThemeDefinition, issues: [ActionThemeIssue]) {
        if let builtin = ActionTheme.builtin(id: selectedID) {
            let definition = ActionThemeDefinition(theme: builtin)
            return (definition, ActionThemeValidator.check(definition))
        }
        guard let entry = catalog.first(where: { $0.id == selectedID }), let url = entry.url else {
            // The selected theme was deleted or renamed out from under the
            // preference. Fall back rather than paint nothing.
            return (.action, [])
        }
        guard let spec = try? Self.decode(contentsOf: url) else {
            return (.action, [.init(severity: .error, message: "Could not read \(url.lastPathComponent).")])
        }
        let resolved = spec.resolve()
        guard ActionThemeValidator.isUsable(resolved.issues) else {
            // A theme with an unreadable pair is not installed. It stays in the
            // catalogue with its errors attached so the reason is visible.
            return (.action, resolved.issues)
        }
        return resolved
    }

    // MARK: Catalogue

    private func loadCatalog() -> [ActionThemeCatalogEntry] {
        var entries = ActionTheme.builtins.map { theme in
            ActionThemeCatalogEntry(
                id: theme.identity.id,
                name: theme.identity.name,
                summary: theme.identity.summary,
                author: theme.identity.author,
                isBuiltin: true,
                url: nil,
                issues: ActionThemeValidator.check(ActionThemeDefinition(theme: theme)),
                preview: ActionThemePreview(tokens: theme.tokens())
            )
        }

        var files: [URL] = []
        for folder in [directory, bundledDirectory].compactMap({ $0 }) {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            files.append(contentsOf: contents.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }

        for url in files where url.pathExtension.lowercased() == "json" {
            do {
                let spec = try Self.decode(contentsOf: url)
                let resolved = spec.resolve()
                if let collision = entries.firstIndex(where: { $0.id == spec.id }) {
                    entries[collision].issues.append(.init(
                        severity: .warning,
                        message: "Ignored \(url.lastPathComponent) because its id \"\(spec.id)\" collides with an earlier theme."
                    ))
                    continue
                }
                entries.append(ActionThemeCatalogEntry(
                    id: spec.id,
                    name: spec.name ?? spec.id,
                    summary: spec.summary,
                    author: spec.author,
                    isBuiltin: false,
                    url: url,
                    issues: resolved.issues,
                    preview: ActionThemePreview(tokens: resolved.definition.tokens())
                ))
            } catch {
                entries.append(ActionThemeCatalogEntry(
                    id: url.deletingPathExtension().lastPathComponent,
                    name: url.deletingPathExtension().lastPathComponent,
                    summary: nil,
                    author: nil,
                    isBuiltin: false,
                    url: url,
                    issues: [.init(severity: .error, message: Self.describe(error))],
                    preview: ActionThemePreview(tokens: ActionTheme.action.tokens())
                ))
            }
        }

        return entries
    }

    private static func decode(contentsOf url: URL) throws -> ActionThemeSpec {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ActionThemeSpec.self, from: data)
    }

    /// Decoding errors from `JSONDecoder` name a coding path that means nothing
    /// to whoever wrote the file. This turns one into a sentence that points at
    /// the key.
    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return error.localizedDescription
        }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch decoding {
        case let .keyNotFound(key, context):
            return "Missing \"\(key.stringValue)\"\(path(context).isEmpty ? "" : " in \(path(context))")."
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            return "\(path(context).isEmpty ? "Value" : path(context)): \(context.debugDescription)"
        case let .dataCorrupted(context):
            return "\(path(context).isEmpty ? "File" : path(context)): \(context.debugDescription)"
        @unknown default:
            return decoding.localizedDescription
        }
    }

    // MARK: Watching

    /// Watches the themes directory so an agent's edit lands without a relaunch.
    ///
    /// A write is usually a rename over the top of the old file, which fires
    /// `.rename`/`.delete` on the *directory*, so the directory is what is
    /// watched. Coalesced through a short debounce because a single save can
    /// produce several events.
    private func startWatching() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stopWatching()

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watchedDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedDescriptor = -1
    }

    private var reloadWorkItem: DispatchWorkItem?

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reload()
        }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
