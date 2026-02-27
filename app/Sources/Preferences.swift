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
    }
}
