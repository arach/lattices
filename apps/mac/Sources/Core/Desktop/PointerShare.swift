import AppKit

/// Shares the pointer with lan-mouse on a trial, the way macOS asks "Keep
/// these display settings?": unless someone says Keep before the deadline,
/// sharing goes off, the cursor comes home and the desktop goes back to the
/// map recorded just before. While a trial is armed, a watchdog checks that
/// lan-mouse still answers and reverts early when it doesn't. Nothing polls
/// outside a trial.
final class PointerShare {
    static let shared = PointerShare()

    static let trial: TimeInterval = 300
    static let watchEvery: TimeInterval = 15
    /// Unanswered checks in a row before the watchdog reverts.
    static let misses = 2
    static let startWait: TimeInterval = 4

    struct Status {
        var lanMouse: Bool
        var running: Bool
        var clients: [PointerHome.Client]
        var until: Date?
        var sharing: Bool { clients.contains(where: \.active) }
    }

    enum ShareError: Error, CustomStringConvertible {
        case noLanMouse, noAnswer, noClients
        var description: String {
            switch self {
            case .noLanMouse: return "lan-mouse isn't installed"
            case .noAnswer: return "lan-mouse didn't start"
            case .noClients: return "lan-mouse has no clients configured"
            }
        }
    }

    /// Main thread only.
    private(set) var until: Date?
    private var deadline: DispatchWorkItem?
    private var watch: DispatchSourceTimer?
    private var missed = 0
    private var before: String?
    /// Whether the running daemon is one Lattices started, so turning
    /// sharing off can stop it again.
    private(set) var startedDaemon = false
    private let checks = DispatchQueue(label: "com.arach.lattices.pointer-share", qos: .utility)

    // MARK: Share / keep

    /// Records the desktop, starts lan-mouse if needed, activates every
    /// client and arms the deadline. `done` runs on main.
    func share(for duration: TimeInterval = trial, done: ((Result<Date, ShareError>) -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        disarm()
        before = StateHistory.shared.record(name: "before-pointer-share")?.id
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Self.start()
            DispatchQueue.main.async {
                switch outcome {
                case .failure(let error):
                    DiagnosticLog.shared.warn("Pointer share: \(error)")
                    done?(.failure(error))
                case .success(let (hosts, started)):
                    self.startedDaemon = self.startedDaemon || started
                    let until = Date().addingTimeInterval(duration)
                    self.arm(until: until)
                    DiagnosticLog.shared.info("Pointer shared with \(hosts.joined(separator: ", ")) until \(Self.clock(until)) unless kept")
                    done?(.success(until))
                }
            }
        }
    }

    /// Keeps sharing on: cancels the deadline and the watchdog.
    func keep() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard until != nil else { return }
        disarm()
        DiagnosticLog.shared.success("Pointer sharing kept")
    }

    /// Hands back whether Lattices started the daemon, and forgets it.
    func takeStartedDaemon() -> Bool {
        let work = { () -> Bool in defer { self.startedDaemon = false }; return self.startedDaemon }
        return Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    /// Cancels a trial without touching lan-mouse. Bring Cursor Home calls
    /// this first, so turning sharing off never fires a late revert.
    func disarm() {
        let work = {
            self.deadline?.cancel()
            self.deadline = nil
            self.watch?.cancel()
            self.watch = nil
            self.until = nil
            self.missed = 0
        }
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    var armed: Bool { until != nil }

    // MARK: Revert

    private func arm(until: Date) {
        self.until = until
        let expire = DispatchWorkItem { [weak self] in self?.revert(because: "trial ended") }
        deadline = expire
        DispatchQueue.main.asyncAfter(deadline: .now() + until.timeIntervalSinceNow, execute: expire)

        let timer = DispatchSource.makeTimerSource(queue: checks)
        timer.schedule(deadline: .now() + Self.watchEvery, repeating: Self.watchEvery)
        timer.setEventHandler { [weak self] in
            guard let bin = PointerHome.binary() else { return }
            let answered = PointerHome.run(bin, ["cli", "list"]) != nil
            DispatchQueue.main.async {
                guard let self, self.watch === timer else { return }
                self.missed = answered ? 0 : self.missed + 1
                if self.missed >= Self.misses { self.revert(because: "lan-mouse stopped answering") }
            }
        }
        watch = timer
        timer.resume()
    }

    /// Sharing off and cursor home (which stops lan-mouse if Lattices started
    /// it), then the desktop restored to the map from just before sharing if
    /// anything moved.
    private func revert(because reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard until != nil else { return }
        DiagnosticLog.shared.warn("Pointer share reverting: \(reason)")
        let before = self.before
        PointerHome.bringHome { _ in Self.restore(before) }
    }

    private static func restore(_ id: String?) {
        guard let id, let map = try? StateHistory.shared.load(id) else { return }
        let plan = StateRestore.plan(map, live: StateRestore.live())
        if plan.moves.isEmpty { return }
        StateRestore.apply(plan, map: map)
    }

    // MARK: lan-mouse

    /// Starts the daemon when it doesn't answer, then activates every client.
    /// Returns the hosts and whether it started the daemon.
    private static func start() -> Result<([String], Bool), ShareError> {
        guard let bin = PointerHome.binary() else { return .failure(.noLanMouse) }
        var started = false
        var list = PointerHome.run(bin, ["cli", "list"])
        if list == nil {
            guard launchDaemon(bin) else { return .failure(.noAnswer) }
            started = true
            let give = Date().addingTimeInterval(startWait)
            while list == nil && Date() < give {
                Thread.sleep(forTimeInterval: 0.3)
                list = PointerHome.run(bin, ["cli", "list"])
            }
        }
        guard let list else { return .failure(.noAnswer) }
        let clients = PointerHome.parseClients(list)
        guard !clients.isEmpty else { return .failure(.noClients) }
        for client in clients where !client.active {
            _ = PointerHome.run(bin, ["cli", "activate", String(client.id)])
        }
        return .success((clients.map(\.host), started))
    }

    /// Runs `lan-mouse daemon` on its own, logging next to its config.
    private static func launchDaemon(_ bin: String) -> Bool {
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/lan-mouse/daemon.log")
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["daemon"]
        process.standardInput = FileHandle.nullDevice
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile()
            process.standardOutput = handle
            process.standardError = handle
        }
        do { try process.run() } catch { return false }
        return true
    }

    /// Reads lan-mouse's clients. Blocks up to `PointerHome.timeout`; call off main.
    static func status() -> Status {
        let until = Thread.isMainThread ? shared.until : DispatchQueue.main.sync { shared.until }
        guard let bin = PointerHome.binary() else { return Status(lanMouse: false, running: false, clients: [], until: until) }
        guard let list = PointerHome.run(bin, ["cli", "list"]) else { return Status(lanMouse: true, running: false, clients: [], until: until) }
        return Status(lanMouse: true, running: true, clients: PointerHome.parseClients(list), until: until)
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
