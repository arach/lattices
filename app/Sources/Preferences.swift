import Foundation

enum InteractionMode: String {
    case learning = "learning"
    case auto = "auto"
}

class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var terminal: Terminal {
        didSet { UserDefaults.standard.set(terminal.rawValue, forKey: "terminal") }
    }

    @Published var scanRoot: String {
        didSet { UserDefaults.standard.set(scanRoot, forKey: "scanRoot") }
    }

    @Published var mode: InteractionMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
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
}
