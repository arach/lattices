import QuartzCore
import SwiftUI

// MARK: - Hyperspace load instrumentation
//
// Structured timing for Hyper+Space / Hyper+G open paths. Marks are relative to the
// hotkey trigger (`loadStart`). Read summaries in Activity Log or ~/.lattices/lattices.log.

final class HyperspaceLoadTrace {
    private let origin: CFTimeInterval
    private var marks: [(name: String, at: CFTimeInterval)] = []
    private var counters: [String: Int] = [:]
    private var durations: [(label: String, ms: Double)] = []

    init(origin: CFTimeInterval) {
        self.origin = origin
    }

    func mark(_ name: String) {
        marks.append((name, CACurrentMediaTime()))
    }

    func bump(_ key: String, by amount: Int = 1) {
        counters[key, default: 0] += amount
    }

    func record(_ label: String, ms: Double, warnAbove: Double = 32) {
        durations.append((label, ms))
        if ms >= warnAbove {
            DiagnosticLog.shared.warn(String(format: "Hyperspace slow — %@ %.0fms", label, ms))
        }
    }

    func logSummary(mode: String, windows: Int, screens: Int, firstPaintMs: Int?, capturesMs: Int?) {
        let parts = marks.map { mark in
            String(format: "%@ %.0fms", mark.name, (mark.at - origin) * 1000)
        }
        let markLine = parts.isEmpty ? "—" : parts.joined(separator: " · ")

        let counterLine = counters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        let durationLine = durations
            .sorted { $0.ms > $1.ms }
            .prefix(6)
            .map { String(format: "%@ %.0fms", $0.label, $0.ms) }
            .joined(separator: " · ")

        let paint = firstPaintMs.map(String.init) ?? "…"
        let caps = capturesMs.map(String.init) ?? "…"
        DiagnosticLog.shared.success(
            "Hyperspace profile [\(mode)] \(windows)w \(screens)d — paint \(paint)ms caps \(caps)ms"
        )
        DiagnosticLog.shared.info("  marks: \(markLine)")
        if !counterLine.isEmpty {
            DiagnosticLog.shared.info("  counts: \(counterLine)")
        }
        if !durationLine.isEmpty {
            DiagnosticLog.shared.info("  slow-path: \(durationLine)")
        }
    }
}

// MARK: - Calm motion presets
//
// Shared animation curves for Hyperspace UI. Prefer short easeOut over spring bounce
// so state changes feel smooth rather than flashy.

enum HyperspaceMotion {
    static let panel = Animation.easeOut(duration: 0.18)
    static let hover = Animation.easeOut(duration: 0.12)
    static let drag = Animation.easeOut(duration: 0.14)
    static let focus = Animation.easeOut(duration: 0.16)
    static let badge = Animation.easeOut(duration: 0.14)
    static let inspector = Animation.easeOut(duration: 0.2)
    static let pulse = Animation.easeOut(duration: 0.22)

    static let pileHoverScale: CGFloat = 1.02
    static let canvasFocusScale: CGFloat = 1.015
    static let tileLinkScale: CGFloat = 1.02
    static let gridCellLitScale: CGFloat = 1.04
    static let gridCellWarmScale: CGFloat = 1.01
    static let ghostArmedScale: CGFloat = 0.78
}