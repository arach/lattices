@testable import ActionCore
import CoreGraphics
import Foundation
import XCTest

final class ActionPointerEventLogTests: XCTestCase {
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) rethrows {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("action-pointer-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func makeLog(
        in directory: URL,
        feedbackEnabled: Bool = false,
        uptime: Double = 1_000
    ) throws -> ActionPointerEventLog {
        try ActionPointerEventLog.create(
            at: directory.appendingPathComponent("recording.pointer-events.jsonl").path,
            recordingId: "recording_test",
            sessionId: "session_test",
            feedback: ActionPointerFeedbackSettings(enabled: feedbackEnabled),
            now: Date(timeIntervalSince1970: 1_700_000_000),
            uptime: uptime
        )
    }

    func testHeaderIsTheFirstLineAndCarriesTheMonotonicReference() throws {
        try withTemporaryDirectory { directory in
            let log = try makeLog(in: directory, feedbackEnabled: true, uptime: 4_242.5)

            let contents = try String(contentsOfFile: log.path, encoding: .utf8)
            let lines = contents.split(separator: "\n")
            XCTAssertEqual(lines.count, 1)

            let header = try JSONDecoder().decode(
                ActionPointerEventLogHeader.self,
                from: Data(lines[0].utf8)
            )
            XCTAssertEqual(header.kind, "header")
            XCTAssertEqual(header.version, ActionPointerEventLogFormat.version)
            XCTAssertEqual(header.recordingId, "recording_test")
            XCTAssertEqual(header.sessionId, "session_test")
            XCTAssertEqual(header.startedAtUptime, 4_242.5)
            XCTAssertTrue(header.feedback.enabled)
            XCTAssertEqual(header.feedback.style, "pulse")
            // The wall clock is fractional so a viewer can line an event up with a video frame.
            XCTAssertTrue(header.startedAt.contains("."))
        }
    }

    func testElapsedIsMeasuredAgainstTheHeaderUptimeNotWallClock() throws {
        try withTemporaryDirectory { directory in
            let log = try makeLog(in: directory, uptime: 1_000)
            XCTAssertEqual(log.elapsedMs(atUptime: 1_000), 0, accuracy: 0.0001)
            XCTAssertEqual(log.elapsedMs(atUptime: 1_002.5), 2_500, accuracy: 0.0001)
        }
    }

    func testAppendedEventsRoundTripAndSkipTheHeaderOnDecode() throws {
        try withTemporaryDirectory { directory in
            let log = try makeLog(in: directory, uptime: 1_000)

            let down = log.makeEvent(
                correlationId: "pe_abc123",
                gesture: .click,
                phase: .down,
                button: .left,
                point: CGPoint(x: 812.5, y: 431),
                source: "click-point",
                now: Date(timeIntervalSince1970: 1_700_000_004),
                uptime: 1_004
            )
            let up = log.makeEvent(
                correlationId: "pe_abc123",
                gesture: .click,
                phase: .up,
                button: .left,
                point: CGPoint(x: 812.5, y: 431),
                source: "click-point",
                holdMs: 31.2,
                now: Date(timeIntervalSince1970: 1_700_000_004),
                uptime: 1_004.0312
            )
            try log.append(down)
            try log.append(up)

            let contents = try String(contentsOfFile: log.path, encoding: .utf8)
            let events = ActionPointerEventLog.decodeEvents(from: contents)
            XCTAssertEqual(events.count, 2, "the header line must not decode as an event")

            XCTAssertEqual(events[0].phase, .down)
            XCTAssertEqual(events[0].correlationId, "pe_abc123")
            XCTAssertEqual(events[0].recordingId, "recording_test")
            XCTAssertEqual(events[0].point.x, 812.5)
            XCTAssertEqual(events[0].point.y, 431)
            XCTAssertEqual(events[0].recordingElapsedMs, 4_000, accuracy: 0.0001)
            XCTAssertNil(events[0].holdMs)

            XCTAssertEqual(events[1].phase, .up)
            // The pair is rejoinable, which is what makes the hold duration meaningful.
            XCTAssertEqual(events[1].correlationId, events[0].correlationId)
            XCTAssertEqual(events[1].holdMs ?? 0, 31.2, accuracy: 0.0001)
        }
    }

    func testAppendIsAtomicPerLineUnderConcurrentWriters() throws {
        try withTemporaryDirectory { directory in
            let log = try makeLog(in: directory, uptime: 1_000)
            let total = 200

            // Separate host processes append to one log; interleaved writes must never produce a
            // half-line, or a reader would drop a real click.
            DispatchQueue.concurrentPerform(iterations: total) { index in
                let event = log.makeEvent(
                    correlationId: "pe_\(index)",
                    gesture: .click,
                    phase: .down,
                    button: .left,
                    point: CGPoint(x: Double(index), y: Double(index)),
                    source: "click-point",
                    uptime: 1_000 + Double(index) / 1_000
                )
                try? log.append(event)
            }

            let contents = try String(contentsOfFile: log.path, encoding: .utf8)
            let events = ActionPointerEventLog.decodeEvents(from: contents)
            XCTAssertEqual(events.count, total)
            XCTAssertEqual(Set(events.map(\.correlationId)).count, total)
        }
    }

    func testOpenReadsBackTheHeaderAndActiveResolvesFromEnvironment() throws {
        try withTemporaryDirectory { directory in
            let created = try makeLog(in: directory, feedbackEnabled: true, uptime: 77)

            let reopened = try XCTUnwrap(ActionPointerEventLog.open(path: created.path))
            XCTAssertEqual(reopened.header, created.header)

            let resolved = ActionPointerEventLog.active(
                environment: [ActionPointerEventLogFormat.environmentKey: created.path],
                markerPath: "/nonexistent/action-pointer-events/active.json"
            )
            XCTAssertEqual(resolved?.header.recordingId, "recording_test")

            // An explicit path wins over the environment, which is what lets a caller target one
            // recording while another is published process-wide.
            let other = try ActionPointerEventLog.create(
                at: directory.appendingPathComponent("other.jsonl").path,
                recordingId: "recording_other",
                sessionId: nil,
                feedback: ActionPointerFeedbackSettings(enabled: false)
            )
            let explicit = ActionPointerEventLog.active(
                explicitPath: other.path,
                environment: [ActionPointerEventLogFormat.environmentKey: created.path],
                markerPath: "/nonexistent/action-pointer-events/active.json"
            )
            XCTAssertEqual(explicit?.header.recordingId, "recording_other")
        }
    }

    func testActiveFallsBackToTheMarkerWhenTheEnvironmentIsNotCarriedAcross() throws {
        try withTemporaryDirectory { directory in
            let log = try makeLog(in: directory)
            let marker = directory.appendingPathComponent("active.json").path
            try ActionPointerEventLog.publishActive(path: log.path, markerPath: marker)

            // This is the `open -n` case: the host is launched by LaunchServices with none of the
            // caller's environment, so only the marker can name the recording.
            let resolved = ActionPointerEventLog.active(environment: [:], markerPath: marker)
            XCTAssertEqual(resolved?.header.recordingId, "recording_test")

            try ActionPointerEventLog.publishActive(path: nil, markerPath: marker)
            XCTAssertNil(ActionPointerEventLog.active(environment: [:], markerPath: marker))
        }
    }

    func testEnvironmentWinsOverTheMarker() throws {
        try withTemporaryDirectory { directory in
            let marked = try makeLog(in: directory)
            let marker = directory.appendingPathComponent("active.json").path
            try ActionPointerEventLog.publishActive(path: marked.path, markerPath: marker)

            let published = try ActionPointerEventLog.create(
                at: directory.appendingPathComponent("published.jsonl").path,
                recordingId: "recording_published",
                sessionId: nil,
                feedback: ActionPointerFeedbackSettings(enabled: false)
            )
            let resolved = ActionPointerEventLog.active(
                environment: [ActionPointerEventLogFormat.environmentKey: published.path],
                markerPath: marker
            )
            XCTAssertEqual(resolved?.header.recordingId, "recording_published")
        }
    }

    func testActiveReturnsNilWhenNothingIsRecording() {
        let absentMarker = "/nonexistent/action-pointer-events/active.json"
        XCTAssertNil(ActionPointerEventLog.active(environment: [:], markerPath: absentMarker))
        // A stale path must read as "not recording" rather than throwing into an action.
        XCTAssertNil(
            ActionPointerEventLog.active(
                environment: [ActionPointerEventLogFormat.environmentKey: "/nonexistent/pointer.jsonl"],
                markerPath: absentMarker
            )
        )
    }

    func testOpenRejectsAFutureFormatVersion() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("future.jsonl").path
            let line = """
            {"kind":"header","version":\(ActionPointerEventLogFormat.version + 1),\
            "recordingId":"r","startedAt":"2026-01-01T00:00:00.000Z","startedAtUptime":1,\
            "feedback":{"enabled":true,"style":"pulse","durationMs":320,"radius":34}}
            """
            try "\(line)\n".write(toFile: path, atomically: true, encoding: .utf8)

            XCTAssertThrowsError(try ActionPointerEventLog.open(path: path)) { error in
                guard case ActionPointerEventLogError.unsupportedVersion(let version) = error else {
                    return XCTFail("Expected an unsupported version error, got \(error)")
                }
                XCTAssertEqual(version, ActionPointerEventLogFormat.version + 1)
            }
        }
    }

    func testDecodeIgnoresTrailingPartialLines() throws {
        try withTemporaryDirectory { directory in
            let log = try makeLog(in: directory, uptime: 1_000)
            let event = log.makeEvent(
                correlationId: "pe_full",
                gesture: .drag,
                phase: .down,
                button: .left,
                point: .zero,
                source: "drag",
                uptime: 1_001
            )
            try log.append(event)

            let contents = try String(contentsOfFile: log.path, encoding: .utf8)
            // Simulates a reader that raced a writer mid-line.
            let truncated = contents + #"{"kind":"pointer","recordin"#
            let events = ActionPointerEventLog.decodeEvents(from: truncated)
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events[0].gesture, .drag)
        }
    }
}
