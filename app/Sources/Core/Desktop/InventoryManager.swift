import Foundation

class InventoryManager: ObservableObject {
    static let shared = InventoryManager()

    @Published var orphans: [TmuxSession] = []
    @Published var allSessions: [TmuxSession] = []

    func refresh() {
        // Always query fresh — this is called on explicit user refresh
        let sessions = TmuxQuery.listSessions()

        // Build set of managed session names
        var managed = Set<String>()

        // From scanned projects
        for project in ProjectScanner.shared.projects {
            managed.insert(project.sessionName)
        }

        // From workspace tab groups
        if let groups = WorkspaceManager.shared.config?.groups {
            for group in groups {
                for tab in group.tabs {
                    managed.insert(WorkspaceManager.sessionName(for: tab.path))
                }
            }
        }

        DispatchQueue.main.async {
            self.allSessions = sessions
            self.orphans = sessions.filter { !managed.contains($0.name) }
        }
    }
}
