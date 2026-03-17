import Foundation

struct ListSessionsIntent: LatticeIntent {
    static let name = "list_sessions"
    static let title = "List running tmux sessions"

    static let phrases = [
        "list sessions",
        "list all sessions",
        "list my sessions",
        "what sessions",
        "what sessions are running",
        "what's running",
        "whats running",
        "what is running",
        "which projects",
        "which projects are active",
        "show sessions",
        "show my sessions",
        "show my projects",
        "show me what's running",
        "show me whats running",
        "how many sessions",
        "any sessions running",
    ]

    static let slots: [SlotDef] = []

    func perform(slots: [String: JSON]) throws -> JSON {
        try LatticesApi.shared.dispatch(method: "sessions.list", params: nil)
    }
}
