import Combine
import Foundation

final class RunStore: ObservableObject {
    static let shared = RunStore()

    @Published private(set) var runs: [RunSession] = []

    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var runsById: [String: RunSession] = [:]
    private var runOrder: [String] = []

    let rootDirectory: URL
    private let indexURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        rootDirectory = support.appendingPathComponent("Lattices/Runs", isDirectory: true)
        indexURL = rootDirectory.appendingPathComponent("runs.json", isDirectory: false)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func createRun(title: String, source: String, surfaces: [RunSurface] = []) throws -> RunSession {
        try ensureRoot()
        let id = Self.makeRunId()
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var run = RunSession(
            id: id,
            title: title.isEmpty ? "Untitled run" : title,
            source: source.isEmpty ? "daemon" : source,
            state: "created",
            startedAt: Self.timestamp(),
            completedAt: nil,
            artifactDirectoryPath: directory.path,
            surfaces: surfaces,
            artifacts: [],
            trace: []
        )
        let event = makeTraceEvent(
            runId: id,
            kind: "run.created",
            summary: "Created run",
            data: ["source": .string(run.source)]
        )
        run.trace.append(event)
        try upsert(run)
        return run
    }

    func list(limit: Int = 20) -> [RunSession] {
        lock.lock()
        defer { lock.unlock() }
        return runOrder.prefix(max(0, limit)).compactMap { runsById[$0] }
    }

    func get(id: String) -> RunSession? {
        lock.lock()
        defer { lock.unlock() }
        return runsById[id]
    }

    func artifacts(for id: String) -> [RunArtifact]? {
        get(id: id)?.artifacts
    }

    func delete(id: String) throws {
        lock.lock()
        guard let run = runsById.removeValue(forKey: id) else {
            lock.unlock()
            throw RouterError.notFound("run \(id)")
        }
        runOrder.removeAll { $0 == id }
        let snapshot = orderedRunsLocked()
        lock.unlock()

        try persist(snapshot)
        publish(snapshot)
        try? FileManager.default.removeItem(atPath: run.artifactDirectoryPath)
    }

    func markRunning(id: String, summary: String, data: [String: JSON] = [:]) throws -> RunSession {
        try mutate(id: id) { run in
            run.state = "running"
            run.trace.append(makeTraceEvent(
                runId: id,
                kind: "run.running",
                summary: summary,
                data: data
            ))
        }
    }

    func complete(id: String, summary: String, data: [String: JSON] = [:]) throws -> RunSession {
        try mutate(id: id) { run in
            run.state = "completed"
            run.completedAt = Self.timestamp()
            run.trace.append(makeTraceEvent(
                runId: id,
                kind: "run.completed",
                summary: summary,
                data: data
            ))
        }
    }

    func fail(id: String, summary: String, data: [String: JSON] = [:]) throws -> RunSession {
        try mutate(id: id) { run in
            run.state = "failed"
            run.completedAt = Self.timestamp()
            run.trace.append(makeTraceEvent(
                runId: id,
                kind: "run.failed",
                summary: summary,
                data: data
            ))
        }
    }

    @discardableResult
    func appendTrace(id: String, kind: String, summary: String, data: [String: JSON] = [:]) throws -> RunSession {
        try mutate(id: id) { run in
            run.trace.append(makeTraceEvent(
                runId: id,
                kind: kind,
                summary: summary,
                data: data
            ))
        }
    }

    @discardableResult
    func appendSurfaces(id: String, surfaces: [RunSurface]) throws -> RunSession {
        try mutate(id: id) { run in
            let existing = Set(run.surfaces.map(\.id))
            let fresh = surfaces.filter { !existing.contains($0.id) }
            guard !fresh.isEmpty else { return }
            run.surfaces.append(contentsOf: fresh)
            run.trace.append(makeTraceEvent(
                runId: id,
                kind: "run.surfaces.attached",
                summary: "Attached run surfaces",
                data: ["surfaces": .array(fresh.map(\.json))]
            ))
        }
    }

    @discardableResult
    func appendArtifact(_ artifact: RunArtifact) throws -> RunSession {
        try mutate(id: artifact.runId) { run in
            run.artifacts.append(artifact)
            run.trace.append(makeTraceEvent(
                runId: artifact.runId,
                kind: "artifact.created",
                summary: "Created \(artifact.kind) artifact",
                data: [
                    "artifactId": .string(artifact.id),
                    "path": .string(artifact.path),
                    "mimeType": .string(artifact.mimeType),
                ]
            ))
        }
    }

    func artifactURL(for run: RunSession, filename: String) -> URL {
        URL(fileURLWithPath: run.artifactDirectoryPath, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    func makeArtifact(
        run: RunSession,
        kind: String,
        url: URL,
        mimeType: String,
        metadata: [String: JSON]
    ) -> RunArtifact {
        RunArtifact(
            id: "art_\(UUID().uuidString.prefix(10).lowercased())",
            runId: run.id,
            kind: kind,
            path: url.path,
            relativePath: url.lastPathComponent,
            mimeType: mimeType,
            createdAt: Self.timestamp(),
            metadata: metadata
        )
    }

    private func mutate(id: String, _ block: (inout RunSession) -> Void) throws -> RunSession {
        lock.lock()
        guard var run = runsById[id] else {
            lock.unlock()
            throw RouterError.notFound("run \(id)")
        }
        block(&run)
        runsById[id] = run
        runOrder.removeAll { $0 == id }
        runOrder.insert(id, at: 0)
        let snapshot = orderedRunsLocked()
        lock.unlock()
        try persist(snapshot)
        publish(snapshot)
        return run
    }

    private func upsert(_ run: RunSession) throws {
        lock.lock()
        runsById[run.id] = run
        runOrder.removeAll { $0 == run.id }
        runOrder.insert(run.id, at: 0)
        let snapshot = orderedRunsLocked()
        lock.unlock()
        try persist(snapshot)
        publish(snapshot)
    }

    private func orderedRunsLocked() -> [RunSession] {
        runOrder.compactMap { runsById[$0] }
    }

    private func ensureRoot() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    private func load() {
        do {
            try ensureRoot()
            guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
            let data = try Data(contentsOf: indexURL)
            let runs = try decoder.decode([RunSession].self, from: data)
            runsById = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
            runOrder = runs.sorted { $0.startedAt > $1.startedAt }.map(\.id)
            self.runs = orderedRunsLocked()
        } catch {
            DiagnosticLog.shared.warn("RunStore: failed to load index — \(error.localizedDescription)")
        }
    }

    private func publish(_ runs: [RunSession]) {
        DispatchQueue.main.async {
            self.runs = runs
        }
    }

    private func persist(_ runs: [RunSession]) throws {
        try ensureRoot()
        let data = try encoder.encode(runs)
        try data.write(to: indexURL, options: .atomic)
    }

    private func makeTraceEvent(runId: String, kind: String, summary: String, data: [String: JSON]) -> RunTraceEvent {
        RunTraceEvent(
            id: "trace_\(UUID().uuidString.prefix(10).lowercased())",
            runId: runId,
            time: Self.timestamp(),
            kind: kind,
            summary: summary,
            data: data
        )
    }

    static func timestamp(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func makeRunId() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "run_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6).lowercased())"
    }
}
