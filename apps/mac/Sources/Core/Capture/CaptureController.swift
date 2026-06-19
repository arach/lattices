import AppKit
import CoreGraphics
import Foundation

final class CaptureController {
    static let shared = CaptureController()

    private init() {}

    private final class CaptureBox {
        private let lock = NSLock()
        private var image: CGImage?

        func set(_ image: CGImage?) {
            lock.lock()
            self.image = image
            lock.unlock()
        }

        func value() -> CGImage? {
            lock.lock()
            defer { lock.unlock() }
            return image
        }
    }

    func screenshotWindow(params: JSON?) throws -> JSON {
        let source = params?["source"]?.stringValue ?? "daemon"
        let target = try resolveWindow(params: params)
        let ownsRun = params?["runId"]?.stringValue?.isEmpty ?? true
        let run = try resolveRun(
            params: params,
            title: params?["title"]?.stringValue ?? "Screenshot \(target.app)",
            source: source,
            surfaces: [.window(target)]
        )

        if ownsRun {
            _ = try RunStore.shared.markRunning(
                id: run.id,
                summary: "Capturing window screenshot",
                data: ["wid": .int(Int(target.wid)), "app": .string(target.app)]
            )
        } else {
            _ = try RunStore.shared.appendTrace(
                id: run.id,
                kind: "capture.screenshot.started",
                summary: "Capturing window screenshot",
                data: ["wid": .int(Int(target.wid)), "app": .string(target.app)]
            )
        }

        let filename = sanitizedFilename(
            params?["filename"]?.stringValue
                ?? "screenshot-window-\(target.wid)-\(Self.fileTimestamp()).png"
        )
        let outputURL = RunStore.shared.artifactURL(for: run, filename: filename)
        let startedAt = Date()

        do {
            let cgImage = try captureWindowImage(wid: target.wid, timeoutSeconds: 15)
            let data = try pngData(from: cgImage)
            try data.write(to: outputURL, options: .atomic)

            let artifact = RunStore.shared.makeArtifact(
                run: run,
                kind: "screenshot",
                url: outputURL,
                mimeType: "image/png",
                metadata: [
                    "wid": .int(Int(target.wid)),
                    "app": .string(target.app),
                    "title": .string(target.title),
                    "width": .int(cgImage.width),
                    "height": .int(cgImage.height),
                    "byteSize": .int(data.count),
                    "elapsedMs": .int(Int(Date().timeIntervalSince(startedAt) * 1000)),
                    "frame": .object([
                        "x": .double(target.frame.x),
                        "y": .double(target.frame.y),
                        "w": .double(target.frame.w),
                        "h": .double(target.frame.h),
                    ]),
                ]
            )
            let updated = try RunStore.shared.appendArtifact(artifact)
            let responseRun: RunSession
            if ownsRun {
                responseRun = try RunStore.shared.complete(
                    id: updated.id,
                    summary: "Saved window screenshot",
                    data: ["artifactId": .string(artifact.id), "path": .string(artifact.path)]
                )
            } else {
                responseRun = try RunStore.shared.appendTrace(
                    id: updated.id,
                    kind: "capture.screenshot.saved",
                    summary: "Saved window screenshot",
                    data: ["artifactId": .string(artifact.id), "path": .string(artifact.path)]
                )
            }

            return .object([
                "ok": .bool(true),
                "run": responseRun.json,
                "artifact": artifact.json,
                "target": Encoders.window(target),
            ])
        } catch {
            let data: [String: JSON] = [
                "wid": .int(Int(target.wid)),
                "error": .string(error.localizedDescription),
            ]
            if ownsRun {
                _ = try? RunStore.shared.fail(
                    id: run.id,
                    summary: "Window screenshot failed",
                    data: data
                )
            } else {
                _ = try? RunStore.shared.appendTrace(
                    id: run.id,
                    kind: "capture.screenshot.failed",
                    summary: "Window screenshot failed",
                    data: data
                )
            }
            throw error
        }
    }

    func resolveWindow(params: JSON?) throws -> WindowEntry {
        DesktopModel.shared.forcePoll()

        if let wid = params?["wid"]?.uint32Value {
            guard let window = DesktopModel.shared.windows[wid] else {
                throw RouterError.notFound("window \(wid)")
            }
            return window
        }

        if let session = params?["session"]?.stringValue, !session.isEmpty {
            guard let window = DesktopModel.shared.windowForSession(session) else {
                throw RouterError.notFound("window for session \(session)")
            }
            return window
        }

        if let app = params?["app"]?.stringValue, !app.isEmpty {
            guard let window = DesktopModel.shared.windowForApp(app: app, title: params?["title"]?.stringValue) else {
                throw RouterError.notFound("window for app \(app)")
            }
            return window
        }

        if let window = DesktopModel.shared.allWindows().first(where: { candidate in
            candidate.isOnScreen &&
                candidate.app != "Lattices" &&
                !candidate.app.localizedCaseInsensitiveContains("lattices")
        }) {
            return window
        }

        guard let frontmost = DesktopModel.shared.frontmostWindow() else {
            throw RouterError.notFound("frontmost window")
        }
        return frontmost
    }

    func resolveRun(params: JSON?, title: String, source: String, surfaces: [RunSurface]) throws -> RunSession {
        if let runId = params?["runId"]?.stringValue, !runId.isEmpty {
            guard let run = RunStore.shared.get(id: runId) else {
                throw RouterError.notFound("run \(runId)")
            }
            return run
        }
        return try RunStore.shared.createRun(title: title, source: source, surfaces: surfaces)
    }

    private func captureWindowImage(wid: UInt32, timeoutSeconds: Int) throws -> CGImage {
        let semaphore = DispatchSemaphore(value: 0)
        let box = CaptureBox()

        Task.detached(priority: .userInitiated) {
            let captured = await WindowCapture.image(
                listOption: .optionIncludingWindow,
                windowID: CGWindowID(wid),
                imageOption: [.boundsIgnoreFraming, .bestResolution]
            )
            box.set(captured)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            throw RouterError.custom("Timed out capturing window \(wid)")
        }
        guard let captured = box.value() else {
            throw RouterError.custom("Unable to capture window \(wid). Check Screen Recording permission.")
        }
        return captured
    }

    private func pngData(from cgImage: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw RouterError.custom("Unable to encode screenshot as PNG")
        }
        return data
    }

    private func sanitizedFilename(_ raw: String) -> String {
        let fallback = "screenshot-window-\(Self.fileTimestamp()).png"
        let name = raw.isEmpty ? fallback : raw
        let safe = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.lowercased().hasSuffix(".png") ? safe : "\(safe).png"
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
