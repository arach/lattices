import Foundation

struct HelpIntent: LatticeIntent {
    static let name = "help"
    static let title = "Show available commands and usage"

    static let phrases = [
        "help",
        "help me",
        "what can i do",
        "what can you do",
        "what commands are there",
        "what are the commands",
        "how does this work",
        "how do i use this",
        "show me the commands",
        "what can i say",
        "what are my options",
    ]

    static let slots: [SlotDef] = []

    func perform(slots: [String: JSON]) throws -> JSON {
        let commands = [
            "find <query> — search windows by name, title, or content",
            "show <app> — focus an app window",
            "open <project> — launch a project or app",
            "tile <position> — tile the current window (left, right, top-left, etc.)",
            "maximize — make the current window full screen",
            "distribute — arrange all visible windows in a grid",
            "scan — OCR all visible windows",
            "kill <session> — stop a tmux session",
            "list windows — show all open windows",
            "list sessions — show running tmux sessions",
        ]
        return .object([
            "commands": .array(commands.map { .string($0) }),
            "hint": .string("You can also say things naturally — 'where's my Slack?' or 'tidy up the windows'"),
        ])
    }
}
