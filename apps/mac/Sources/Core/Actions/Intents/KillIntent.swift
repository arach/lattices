import Foundation

struct KillIntent: LatticeIntent {
    static let name = "kill"
    static let title = "Stop a running session"

    static let phrases = [
        // Primary operator: kill
        "kill {session}",
        "kill the {session}",
        "kill the {session} session",
        "kill that",
        // stop
        "stop {session}",
        "stop the {session}",
        "stop the {session} session",
        // shut down
        "shut down {session}",
        "shut down the {session}",
        "shut it down",
        // close
        "close {session}",
        "close the {session}",
        "close the {session} session",
        // terminate
        "terminate {session}",
        "terminate the {session}",
        // end
        "end {session}",
        "end the {session}",
        "end the {session} session",
    ]

    static let slots = [
        SlotDef(name: "session", type: .session, required: true),
    ]

    func perform(slots: [String: JSON]) throws -> JSON {
        guard let session = slots["session"]?.stringValue else {
            throw IntentError.missingSlot("session")
        }
        return try LatticesApi.shared.dispatch(
            method: "session.kill",
            params: .object(["name": .string(session)])
        )
    }
}
