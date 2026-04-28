import DeckKit
import Foundation

enum InteractionMode: String {
    case learning = "learning"
    case auto = "auto"
}

class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum CompanionDefaultsKey {
        static let trackpadEnabled = "companion.trackpad.enabled"
        static let cockpitLayout = "companion.cockpit.layout"
    }

    @Published var terminal: Terminal {
        didSet { UserDefaults.standard.set(terminal.rawValue, forKey: "terminal") }
    }

    @Published var scanRoot: String {
        didSet { UserDefaults.standard.set(scanRoot, forKey: "scanRoot") }
    }

    @Published var mode: InteractionMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }

    @Published var dragSnapEnabled: Bool {
        didSet { UserDefaults.standard.set(dragSnapEnabled, forKey: "windowSnap.enabled") }
    }

    @Published var companionTrackpadEnabled: Bool {
        didSet { UserDefaults.standard.set(companionTrackpadEnabled, forKey: CompanionDefaultsKey.trackpadEnabled) }
    }

    @Published var companionCockpitLayout: LatticesCompanionCockpitLayout {
        didSet { persistCompanionCockpitLayout() }
    }

    // MARK: - AI / Claude

    @Published var claudePath: String {
        didSet { UserDefaults.standard.set(claudePath, forKey: "claude.path") }
    }

    @Published var advisorModel: String {
        didSet { UserDefaults.standard.set(advisorModel, forKey: "claude.advisorModel") }
    }

    @Published var advisorBudgetUSD: Double {
        didSet { UserDefaults.standard.set(advisorBudgetUSD, forKey: "claude.advisorBudget") }
    }

    /// Resolve claude CLI path: saved preference → well-known locations → `which`
    static func resolveClaudePath() -> String? {
        let saved = shared.claudePath
        if !saved.isEmpty, FileManager.default.isExecutableFile(atPath: saved) {
            return saved
        }

        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                // Save for next time
                DispatchQueue.main.async { shared.claudePath = path }
                return path
            }
        }

        // Last resort: `which claude`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "which claude 2>/dev/null"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
            DispatchQueue.main.async { shared.claudePath = output }
            return output
        }

        return nil
    }

    // MARK: - Search & OCR

    @Published var ocrEnabled: Bool {
        didSet { UserDefaults.standard.set(!ocrEnabled, forKey: "ocr.disabled") }
    }

    @Published var ocrQuickInterval: Double {
        didSet { UserDefaults.standard.set(ocrQuickInterval, forKey: "ocr.interval") }
    }

    @Published var ocrDeepInterval: Double {
        didSet { UserDefaults.standard.set(ocrDeepInterval, forKey: "ocr.deepInterval") }
    }

    @Published var ocrQuickLimit: Int {
        didSet { UserDefaults.standard.set(ocrQuickLimit, forKey: "ocr.quickLimit") }
    }

    @Published var ocrDeepLimit: Int {
        didSet { UserDefaults.standard.set(ocrDeepLimit, forKey: "ocr.deepLimit") }
    }

    @Published var ocrDeepBudget: Int {
        didSet { UserDefaults.standard.set(ocrDeepBudget, forKey: "ocr.deepBudget") }
    }

    @Published var ocrAccuracy: String {
        didSet { UserDefaults.standard.set(ocrAccuracy, forKey: "ocr.accuracy") }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "terminal"),
           let t = Terminal(rawValue: saved), t.isInstalled {
            self.terminal = t
        } else {
            self.terminal = Terminal.installed.first ?? .terminal
        }

        let savedRoot = UserDefaults.standard.string(forKey: "scanRoot") ?? ""
        if savedRoot.isEmpty {
            // Auto-detect a reasonable default
            let home = NSHomeDirectory()
            let candidates = ["\(home)/dev", "\(home)/Developer", "\(home)/projects", "\(home)/src"]
            self.scanRoot = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? ""
        } else {
            self.scanRoot = savedRoot
        }

        if let saved = UserDefaults.standard.string(forKey: "mode"),
           let m = InteractionMode(rawValue: saved) {
            self.mode = m
        } else {
            self.mode = .learning
        }

        if UserDefaults.standard.object(forKey: "windowSnap.enabled") != nil {
            self.dragSnapEnabled = UserDefaults.standard.bool(forKey: "windowSnap.enabled")
        } else {
            self.dragSnapEnabled = true
        }

        if UserDefaults.standard.object(forKey: CompanionDefaultsKey.trackpadEnabled) != nil {
            self.companionTrackpadEnabled = UserDefaults.standard.bool(forKey: CompanionDefaultsKey.trackpadEnabled)
        } else {
            self.companionTrackpadEnabled = true
        }

        self.companionCockpitLayout = Self.loadCompanionCockpitLayout()

        // AI / Claude
        self.claudePath = UserDefaults.standard.string(forKey: "claude.path") ?? ""
        self.advisorModel = UserDefaults.standard.string(forKey: "claude.advisorModel") ?? "haiku"
        let savedBudgetUSD = UserDefaults.standard.double(forKey: "claude.advisorBudget")
        self.advisorBudgetUSD = savedBudgetUSD > 0 ? savedBudgetUSD : 0.50

        // Search & OCR
        self.ocrEnabled = !UserDefaults.standard.bool(forKey: "ocr.disabled")

        let savedInterval = UserDefaults.standard.double(forKey: "ocr.interval")
        self.ocrQuickInterval = savedInterval > 0 ? savedInterval : 60

        let savedDeep = UserDefaults.standard.double(forKey: "ocr.deepInterval")
        self.ocrDeepInterval = savedDeep > 0 ? savedDeep : 7200

        let savedQL = UserDefaults.standard.integer(forKey: "ocr.quickLimit")
        self.ocrQuickLimit = savedQL > 0 ? savedQL : 5

        let savedDL = UserDefaults.standard.integer(forKey: "ocr.deepLimit")
        self.ocrDeepLimit = savedDL > 0 ? savedDL : 15

        let savedBudget = UserDefaults.standard.integer(forKey: "ocr.deepBudget")
        self.ocrDeepBudget = savedBudget > 0 ? savedBudget : 3

        let savedAcc = UserDefaults.standard.string(forKey: "ocr.accuracy") ?? "accurate"
        self.ocrAccuracy = savedAcc
    }

    func updateCompanionCockpitSlot(
        pageID: String,
        index: Int,
        shortcutID: String
    ) {
        var normalized = LatticesCompanionCockpitCatalog.normalized(companionCockpitLayout)
        guard let pageIndex = normalized.pages.firstIndex(where: { $0.id == pageID }),
              normalized.pages[pageIndex].slotIDs.indices.contains(index) else {
            return
        }
        normalized.pages[pageIndex].slotIDs[index] = shortcutID
        companionCockpitLayout = normalized
    }

    func resetCompanionCockpitLayout() {
        companionCockpitLayout = LatticesCompanionCockpitCatalog.defaultLayout
    }

    private static func loadCompanionCockpitLayout() -> LatticesCompanionCockpitLayout {
        guard let data = UserDefaults.standard.data(forKey: CompanionDefaultsKey.cockpitLayout),
              let decoded = try? JSONDecoder().decode(LatticesCompanionCockpitLayout.self, from: data) else {
            return LatticesCompanionCockpitCatalog.defaultLayout
        }
        return LatticesCompanionCockpitCatalog.normalized(decoded)
    }

    private func persistCompanionCockpitLayout() {
        let normalized = LatticesCompanionCockpitCatalog.normalized(companionCockpitLayout)
        if normalized != companionCockpitLayout {
            companionCockpitLayout = normalized
            return
        }

        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: CompanionDefaultsKey.cockpitLayout)
    }
}
