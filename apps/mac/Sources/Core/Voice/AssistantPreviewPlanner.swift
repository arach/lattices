import Foundation

final class AssistantPreviewPlanner {
    static let shared = AssistantPreviewPlanner()

    private let timeoutSeconds: TimeInterval = 30
    private let tracePath = NSHomeDirectory() + "/.lattices/assistant-preview-debug.jsonl"

    private init() {}

    enum PreviewError: LocalizedError {
        case bunUnavailable
        case workerRootUnavailable
        case scriptUnavailable(String)
        case invalidInput
        case timedOut
        case emptyResponse(String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .bunUnavailable:
                return "Assistant preview could not find bun."
            case .workerRootUnavailable:
                return "Assistant preview could not find the lattices CLI root."
            case .scriptUnavailable(let path):
                return "Assistant preview script not found at \(path)."
            case .invalidInput:
                return "Assistant preview could not encode the planner request."
            case .timedOut:
                return "Assistant preview timed out waiting for the planner."
            case .emptyResponse(let stderr):
                return stderr.isEmpty ? "Assistant preview returned no output." : "Assistant preview returned no output: \(stderr)"
            case .invalidResponse(let message):
                return "Assistant preview returned invalid JSON: \(message)"
            }
        }
    }

    func preview(
        transcript: String,
        snapshotOverride: [String: Any]? = nil,
        history: [[String: String]] = [],
        trace: Bool = false
    ) throws -> JSON {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PreviewError.invalidInput }

        let snapshot = snapshotOverride ?? AssistantSnapshotBuilder.build()
        let snapshotSource = snapshotOverride == nil ? "live" : "override"
        let request: [String: Any] = [
            "transcript": trimmed,
            "snapshot": snapshot,
            "history": history,
        ]

        let startedAt = Date()
        let run = try runInfer(request: request)
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let plan = try parsePlan(stdout: run.stdout, stderr: run.stderr)
        let traceFile = trace ? writeTrace(
            transcript: trimmed,
            snapshotSource: snapshotSource,
            request: request,
            response: plan,
            stderr: run.stderr,
            exitCode: run.exitCode,
            durationMs: durationMs
        ) : nil

        let preview: [String: Any] = [
            "durationMs": durationMs,
            "exitCode": Int(run.exitCode),
            "tracePath": traceFile ?? NSNull(),
        ]

        var response: [String: Any] = [
            "ok": run.exitCode == 0,
            "dryRun": true,
            "transcript": trimmed,
            "snapshotSource": snapshotSource,
            "data": plan,
            "preview": preview,
        ]
        if run.exitCode != 0 {
            response["error"] = (plan["_meta"] as? [String: Any])?["error"] ?? run.stderr
        }

        return try Self.json(fromJSONObject: response)
    }

    private func runInfer(request: [String: Any]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let bunPath = Self.bunPath else {
            throw PreviewError.bunUnavailable
        }
        guard let root = Self.workerRoot else {
            throw PreviewError.workerRootUnavailable
        }

        let scriptPath = root + "/bin/handsoff-infer.ts"
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw PreviewError.scriptUnavailable(scriptPath)
        }

        guard let inputData = try? JSONSerialization.data(withJSONObject: request) else {
            throw PreviewError.invalidInput
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bunPath)
        proc.arguments = ["run", scriptPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: root)

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let semaphore = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in semaphore.signal() }

        try proc.run()
        inPipe.fileHandleForWriting.write(inputData)
        inPipe.fileHandleForWriting.write(Data("\n".utf8))
        try? inPipe.fileHandleForWriting.close()

        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            proc.terminate()
            throw PreviewError.timedOut
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, proc.terminationStatus)
    }

    private func parsePlan(stdout: String, stderr: String) throws -> [String: Any] {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PreviewError.emptyResponse(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw PreviewError.invalidResponse("stdout was not UTF-8")
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw PreviewError.invalidResponse("root value was not an object")
            }
            return object
        } catch let error as PreviewError {
            throw error
        } catch {
            throw PreviewError.invalidResponse(error.localizedDescription)
        }
    }

    private func writeTrace(
        transcript: String,
        snapshotSource: String,
        request: [String: Any],
        response: [String: Any],
        stderr: String,
        exitCode: Int32,
        durationMs: Int
    ) -> String? {
        let record: [String: Any] = [
            "kind": "assistant.preview",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "transcript": transcript,
            "snapshotSource": snapshotSource,
            "request": request,
            "response": response,
            "stderr": stderr,
            "exitCode": Int(exitCode),
            "durationMs": durationMs,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              var line = String(data: data, encoding: .utf8) else { return nil }
        line += "\n"

        let url = URL(fileURLWithPath: tracePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = FileHandle(forWritingAtPath: tracePath) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: tracePath, contents: Data(line.utf8))
        }
        return tracePath
    }

    static func foundationObject(from json: JSON) throws -> Any {
        let data = try JSONEncoder().encode(json)
        return try JSONSerialization.jsonObject(with: data)
    }

    static func json(fromJSONObject object: Any) throws -> JSON {
        switch object {
        case let value as String:
            return .string(value)
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .int(value)
        case let value as UInt32:
            return .int(Int(value))
        case let value as Int32:
            return .int(Int(value))
        case let value as Double:
            return .double(value)
        case let value as Float:
            return .double(Double(value))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            let double = value.doubleValue
            if double.rounded() == double {
                return .int(value.intValue)
            }
            return .double(double)
        case let value as [Any]:
            return .array(try value.map(json(fromJSONObject:)))
        case let value as [String: Any]:
            return .object(try value.reduce(into: [String: JSON]()) { dict, pair in
                dict[pair.key] = try json(fromJSONObject: pair.value)
            })
        case _ as NSNull:
            return .null
        case Optional<Any>.none:
            return .null
        default:
            return .string(String(describing: object))
        }
    }

    private static var bunPath: String? {
        [
            NSHomeDirectory() + "/.bun/bin/bun",
            "/usr/local/bin/bun",
            "/opt/homebrew/bin/bun",
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private static var workerRoot: String? {
        if let idx = CommandLine.arguments.firstIndex(of: "--lattices-cli-root"),
           CommandLine.arguments.indices.contains(idx + 1) {
            return CommandLine.arguments[idx + 1]
        }

        let devRoot = NSHomeDirectory() + "/dev/lattices"
        return FileManager.default.fileExists(atPath: devRoot) ? devRoot : nil
    }
}
