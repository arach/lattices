import Foundation

struct ScanIntent: LatticeIntent {
    static let name = "scan"
    static let title = "Rescan screen text (OCR)"

    static let phrases = [
        // Primary operator: scan
        "scan",
        "scan the screen",
        "scan everything",
        "scan all",
        "scan my screen",
        "scan my windows",
        "scan all windows",
        // rescan
        "rescan",
        "rescan the screen",
        "rescan everything",
        // read
        "read the screen",
        "read my screen",
        "read all windows",
        // ocr
        "ocr",
        "ocr scan",
        "run ocr",
        // update / refresh / capture
        "update screen text",
        "refresh screen text",
        "capture screen text",
        "capture text",
        // natural
        "what's on my screen",
        "what's on screen",
        "what is on my screen",
        "show me what's on the screen",
        "show me what is on the screen",
        "index the screen",
        "do a scan",
        "give me a scan",
        "give me a fresh scan",
        "quick scan",
        "a fresh scan",
    ]

    static let slots: [SlotDef] = []

    func perform(slots: [String: JSON]) throws -> JSON {
        try LatticesApi.shared.dispatch(method: "ocr.scan", params: nil)
    }
}
