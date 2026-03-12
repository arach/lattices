import Foundation

struct ListWindowsIntent: LatticeIntent {
    static let name = "list_windows"
    static let title = "List all open windows"

    static let phrases = [
        "list windows",
        "list all windows",
        "list my windows",
        "what windows",
        "what windows are open",
        "what's open",
        "which windows",
        "which windows are visible",
        "show all windows",
        "show me all windows",
        "show me all the windows",
        "how many windows",
        "count windows",
        "what do i have open",
        "what's visible",
    ]

    static let slots: [SlotDef] = []

    func perform(slots: [String: JSON]) throws -> JSON {
        try LatticesApi.shared.dispatch(method: "windows.list", params: nil)
    }
}
