import AppKit

/// Who asked the daemon for something. The CLI client sends it as one
/// base64 JSON header on the WebSocket upgrade.
struct CaptureCaller: Codable, Equatable {
    var agent: String?
    var client: String?
    var origin: String?
    var cwd: String?
    var pid: Int?

    static let header = "x-lattices-caller"

    nonisolated static func parse(handshake: String) -> CaptureCaller? {
        for line in handshake.components(separatedBy: "\r\n").dropFirst() {
            if line.isEmpty { break }
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces).lowercased() == header,
                  let data = Data(base64Encoded: pair[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            return try? JSONDecoder().decode(CaptureCaller.self, from: data)
        }
        return nil
    }

    var agentLabel: String {
        if let agent, !agent.isEmpty { return agent }
        if let client, !client.isEmpty { return client }
        return "unknown"
    }

    var originLabel: String {
        guard let origin, !origin.isEmpty, origin != "local" else { return "this Mac" }
        return origin
    }

    var projectLabel: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty || name == NSUserName() ? nil : name
    }
}

/// Screenshots requested over the daemon socket: appended to
/// ~/.lattices/audit/captures.jsonl and flagged on screen. In-app captures
/// don't pass through here.
enum CaptureAudit {
    static let methods: Set<String> = [
        "capture.screenshotWindow",
        "capture.screenshotRegion",
        "capture.screenshotDisplay",
    ]

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".lattices/audit/captures.jsonl")

    private static let writeQueue = DispatchQueue(label: "com.arach.lattices.capture-audit")

    static func record(method: String, caller: CaptureCaller?, result: JSON?) {
        let kind = method.replacingOccurrences(of: "capture.screenshot", with: "").lowercased()
        let target = result?["target"]
        let rect = cgRect(result?["region"])
            ?? cgRect(result?["display"]?["frame"])
            ?? cgRect(target?["frame"])

        var entry: [String: JSON] = [
            "ts": .string(ISO8601DateFormatter().string(from: Date())),
            "method": .string(method),
            "kind": .string(kind),
        ]
        if let caller, let data = try? JSONEncoder().encode(caller),
           let json = try? JSONDecoder().decode(JSON.self, from: data) {
            entry["caller"] = json
        }
        if let target {
            entry["target"] = .object([
                "app": target["app"] ?? .null,
                "title": target["title"] ?? .null,
                "wid": target["wid"] ?? .null,
            ])
        }
        if let display = result?["display"] { entry["display"] = display["name"] ?? .null }
        if let rect {
            entry["rect"] = .object([
                "x": .double(rect.origin.x), "y": .double(rect.origin.y),
                "w": .double(rect.width), "h": .double(rect.height),
            ])
        }
        if let path = result?["artifact"]?["path"] { entry["artifact"] = path }
        if let runId = result?["run"]?["id"] { entry["runId"] = runId }
        append(.object(entry))

        let who = caller ?? CaptureCaller()
        DiagnosticLog.shared.info("CaptureAudit: \(who.agentLabel) from \(who.originLabel) took a \(kind) screenshot")

        guard let rect else { return }
        var subject = kind
        if let app = target?["app"]?.stringValue, !app.isEmpty { subject += " · \(app)" }
        DispatchQueue.main.async {
            CaptureCueOverlay.shared.show(cgRect: rect, caller: who, subject: subject)
        }
    }

    private static func append(_ entry: JSON) {
        writeQueue.async {
            guard var line = try? JSONEncoder().encode(entry) else { return }
            line.append(0x0A)
            let fm = FileManager.default
            try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: logURL.path) {
                fm.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    private static func number(_ json: JSON?) -> Double? {
        switch json {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    private static func cgRect(_ json: JSON?) -> CGRect? {
        guard let x = number(json?["x"]), let y = number(json?["y"]),
              let w = number(json?["w"]), let h = number(json?["h"]), w > 0, h > 0
        else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// A coral hairline around what was captured, plus an ink tag naming who
/// asked. Shown after the shot, so it never lands in the image, and kept out
/// of later shots with `sharingType = .none`.
@MainActor
final class CaptureCueOverlay {
    static let shared = CaptureCueOverlay()

    private static let coral = NSColor(srgbRed: 0xef / 255, green: 0x6a / 255, blue: 0x47 / 255, alpha: 1)
    private static let ink = NSColor(srgbRed: 0x10 / 255, green: 0x15 / 255, blue: 0x18 / 255, alpha: 0.92)
    private static let paper = NSColor(srgbRed: 0xf2 / 255, green: 0xf2 / 255, blue: 0xf2 / 255, alpha: 1)

    private var panel: NSPanel?
    private var generation = 0

    func show(cgRect: CGRect, caller: CaptureCaller, subject: String) {
        guard let primary = NSScreen.screens.first else { return }
        let appKitRect = CGRect(
            x: cgRect.minX,
            y: primary.frame.height - cgRect.maxY,
            width: cgRect.width,
            height: cgRect.height
        )
        let screen = NSScreen.screens.first { $0.frame.intersects(appKitRect) } ?? primary
        let frame = appKitRect.intersection(screen.frame).insetBy(dx: -2, dy: -2)
        guard !frame.isEmpty else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: false)

        let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
        root.wantsLayer = true

        let border = NSView(frame: root.bounds.insetBy(dx: 1, dy: 1))
        border.wantsLayer = true
        border.layer?.borderColor = Self.coral.cgColor
        border.layer?.borderWidth = 1.5
        border.layer?.cornerRadius = 10
        root.addSubview(border)

        // Keep the tag clear of the menu bar on full-display shots.
        let visibleTop = screen.visibleFrame.maxY - frame.minY
        let tag = makeTag(caller: caller, subject: subject)
        let tagY = min(frame.height, visibleTop) - tag.frame.height - 10
        tag.setFrameOrigin(CGPoint(x: 10, y: max(10, tagY)))
        root.addSubview(tag)

        panel.contentView = root
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        generation += 1
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.generation == current, let panel = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.panel?.orderOut(nil)
                }
            })
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        return panel
    }

    private func makeTag(caller: CaptureCaller, subject: String) -> NSView {
        var parts = [caller.agentLabel, caller.originLabel]
        if let project = caller.projectLabel { parts.append(project) }
        parts.append(subject)

        let label = NSTextField(labelWithString: parts.joined(separator: "  ·  "))
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = Self.paper
        label.lineBreakMode = .byTruncatingMiddle
        label.sizeToFit()

        let dot = NSView(frame: CGRect(x: 10, y: 0, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = Self.coral.cgColor
        dot.layer?.cornerRadius = 3

        let height: CGFloat = 24
        let labelWidth = min(label.frame.width, 520)
        let tag = NSView(frame: CGRect(x: 0, y: 0, width: labelWidth + 34, height: height))
        tag.wantsLayer = true
        tag.layer?.backgroundColor = Self.ink.cgColor
        tag.layer?.cornerRadius = height / 2
        dot.setFrameOrigin(CGPoint(x: 10, y: (height - 6) / 2))
        label.frame = CGRect(x: 22, y: (height - label.frame.height) / 2, width: labelWidth, height: label.frame.height)
        tag.addSubview(dot)
        tag.addSubview(label)
        return tag
    }
}
