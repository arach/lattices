import Foundation

/// Owns only installer helpers. Companion apps are launched separately through
/// NSWorkspace, so quitting Lattices does not terminate them.
final class CompanionInstallerBridge {
    static let shared = CompanionInstallerBridge()
    struct State: Equatable {
        var phase: String
        var active: Bool
        var message: String?
    }
    private(set) var states: [CompanionProductID: State] = [:]
    private var processes: [CompanionProductID: Process] = [:]
    var onChange: (() -> Void)?

    func cancel(_ product: CompanionProductID) {
        // SIGINT invokes the helper's cancellation/cleanup path; never signal an app.
        processes[product]?.interrupt()
    }

    func install(_ product: CompanionProductID) {
        guard processes[product] == nil else { return }
        let process = Process()
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "CompanionInstaller") {
            process.executableURL = bundled
            process.arguments = [product.rawValue]
        } else if let root = LatticesRuntime.cliRoot, let bun = LatticesRuntime.bunPath {
            process.executableURL = URL(fileURLWithPath: bun)
            process.arguments = [root + "/bin/companion-installer.ts", product.rawValue]
        } else {
            states[product] = State(phase: "failed", active: false, message: "The installer is missing from this Lattices build.")
            onChange?()
            return
        }
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() }
        catch {
            states[product] = State(phase: "failed", active: false, message: error.localizedDescription)
            onChange?()
            return
        }
        processes[product] = process
        states[product] = State(phase: "checking", active: true)
        onChange?()
        let group = DispatchGroup()
        let collector = CompanionInstallerOutput()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            var pending = Data()
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: newline)
                    pending.removeSubrange(...newline)
                    guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    if let phase = event["phase"] as? String {
                        DispatchQueue.main.async {
                            self.states[product] = State(phase: phase, active: true)
                            self.onChange?()
                        }
                    }
                    if let status = event["status"] as? String {
                        collector.status = status
                        collector.message = event["message"] as? String
                        collector.cleanup = (event["cleanupErrors"] as? [String] ?? []).joined(separator: "\n")
                    }
                }
                if pending.count > 65536 { pending.removeAll() }
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = errors.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                if collector.errorData.count < 65536 { collector.errorData.append(chunk.prefix(65536 - collector.errorData.count)) }
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async { process.waitUntilExit(); group.leave() }
        group.notify(queue: .main) {
            self.processes.removeValue(forKey: product)
            let status = collector.status ?? "failed"
            let detail = collector.message ?? String(data: collector.errorData, encoding: .utf8)
            self.states[product] = State(phase: status, active: false,
                message: [detail, collector.cleanup].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n"))
            self.onChange?()
        }
    }
}

/// Each field is written by one pipe reader and read after DispatchGroup joins.
private final class CompanionInstallerOutput: @unchecked Sendable {
    var status: String?
    var message: String?
    var cleanup = ""
    var errorData = Data()
}
