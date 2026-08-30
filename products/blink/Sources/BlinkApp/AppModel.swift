import BlinkCore
import Foundation
import HudsonObservability
import SwiftUI

/// The live desktop boundary. Durable membership remains in each note's
/// frontmatter; this device-local selection only decides which group the
/// popover browses and which already-open panels are visible right now.
enum WorkspaceScope: Hashable {
    case all
    case unfiled
    case workspace(String)

    private static let allKey = "scope:all"
    private static let unfiledKey = "scope:unfiled"

    init(storageValue: String?) {
        switch storageValue {
        case Self.unfiledKey:
            self = .unfiled
        case let value? where value.hasPrefix("workspace:"):
            let id = String(value.dropFirst("workspace:".count))
            self = id.isEmpty ? .all : .workspace(id)
        default:
            self = .all
        }
    }

    var storageValue: String {
        switch self {
        case .all: Self.allKey
        case .unfiled: Self.unfiledKey
        case .workspace(let id): "workspace:\(id)"
        }
    }

    var workspaceIDForNewNote: String? {
        guard case .workspace(let id) = self else { return nil }
        return id
    }

    func includes(workspace: String?) -> Bool {
        switch self {
        case .all: true
        case .unfiled: workspace == nil
        case .workspace(let id): workspace == id
        }
    }

    static func containing(workspace: String?) -> WorkspaceScope {
        workspace.map(Self.workspace) ?? .unfiled
    }
}

/// The single observable source of truth for every UI surface (popover, panels,
/// future palette). Mirrors the `NoteStore` actor into a @Published snapshot,
/// refreshed on every store notification — so any surface that mutates notes
/// automatically updates every other surface.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var workspaceScope: WorkspaceScope

    private let store: NoteStore
    private let panelManager: PanelManager
    private var observers: [NSObjectProtocol] = []
    private let log = HudLogger(category: "blink.model")

    init(store: NoteStore, panelManager: PanelManager) {
        self.store = store
        self.panelManager = panelManager
        workspaceScope = WorkspaceScope(
            storageValue: UserDefaults.standard.string(forKey: ConfigKeys.activeWorkspaceScope)
        )
        panelManager.configureWorkspaceScope(workspaceScope)
    }

    /// Register for store notifications and take the initial snapshot.
    /// Call after `PanelManager.restoreSession()` so the store is loaded.
    func start() async {
        let names: [Notification.Name] = [.blinkNoteCreated, .blinkNoteUpdated, .blinkNoteDeleted]
        for name in names {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in await self?.refresh() }
                }
            )
        }
        await refresh()
    }

    func refresh() async {
        let snapshot = await store.all()
        notes = snapshot
        panelManager.applyWorkspaceScope(workspaceScope, notes: snapshot, animated: false)
    }

    /// Activate a device-local workspace view. Panels outside the selection are
    /// hidden, never closed, so their pending text, exact frames, and open-set
    /// membership remain untouched for the next switch.
    func selectWorkspace(_ scope: WorkspaceScope) {
        workspaceScope = scope
        UserDefaults.standard.set(scope.storageValue, forKey: ConfigKeys.activeWorkspaceScope)
        panelManager.applyWorkspaceScope(scope, notes: notes, animated: true, activate: true)
    }

    /// Create a note (optionally seeded with captured text) and open its panel.
    func createNote(content: String = "") async {
        do {
            var presentation = NotePresentation()
            presentation.workspace = workspaceScope.workspaceIDForNewNote
            let note = try await store.create(
                content: content,
                presentation: presentation,
                writer: "user"
            )
            // New notes always open in edit — you just created it to type.
            panelManager.openPanel(for: note, initialMode: "edit")
        } catch {
            log.error("[BLINK] create failed", metadata: ["error": "\(error)"])
        }
    }

    /// Open (or focus) the panel for an existing note.
    @discardableResult
    func openNote(id: String, deskFrame: DeskFrameRequest? = nil) async -> Bool {
        var note = await store.note(id: id)
        if note == nil {
            // A CLI can create and open in immediate succession, beating the
            // directory watcher's coalesced event by a few milliseconds.
            // Reconcile once at this explicit boundary rather than making the
            // caller guess a sleep duration.
            _ = await store.reconcile()
            note = await store.note(id: id)
        }
        guard let note else {
            log.error("[BLINK] open failed", metadata: ["id": id, "error": "note not found"])
            return false
        }
        if !workspaceScope.includes(workspace: note.presentation.workspace) {
            selectWorkspace(.containing(workspace: note.presentation.workspace))
        }
        panelManager.openPanel(for: note, deskFrame: deskFrame)
        return true
    }

    /// Delete a note: close its panel (discarding pending edits for it) and
    /// remove the file.
    func deleteNote(id: String) async {
        panelManager.handleNoteDeleted(id: id)
        do {
            try await store.delete(id: id, writer: "user")
        } catch {
            log.error("[BLINK] delete failed", metadata: ["id": id, "error": "\(error)"])
        }
    }
}
