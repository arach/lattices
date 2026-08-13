import XCTest
@testable import Lattices

final class TmuxPaneCaptureTests: XCTestCase {
    private func session(_ name: String, panes: [(id: String, title: String)]) -> TmuxSession {
        TmuxSession(
            id: name,
            name: name,
            windowCount: 1,
            attached: true,
            panes: panes.map { pane in
                TmuxPane(
                    id: pane.id,
                    windowIndex: 0,
                    windowName: name,
                    title: pane.title,
                    currentCommand: "zsh",
                    pid: 1,
                    isActive: pane.id == panes.first?.id
                )
            }
        )
    }

    func testResolveByPaneId() throws {
        let sessions = [
            session("lattices-aaaaaa", panes: [("%3", "claude"), ("%4", "dev")]),
        ]
        let target = try TmuxPaneCapture.resolve(
            session: nil,
            pane: nil,
            paneId: "3",
            tty: nil,
            sessions: sessions,
            ttyIndex: [:]
        )
        XCTAssertEqual(target.paneId, "%3")
        XCTAssertEqual(target.session, "lattices-aaaaaa")
    }

    func testAmbiguousSessionThrows() {
        let sessions = [
            session("lattices-aaaaaa", panes: [("%3", "claude"), ("%4", "dev")]),
        ]
        XCTAssertThrowsError(
            try TmuxPaneCapture.resolve(
                session: "lattices-aaaaaa",
                pane: nil,
                paneId: nil,
                tty: nil,
                sessions: sessions,
                ttyIndex: [:]
            )
        )
    }

    func testResolveSessionPlusPaneName() throws {
        let sessions = [
            session("lattices-aaaaaa", panes: [("%3", "claude"), ("%4", "dev")]),
        ]
        let target = try TmuxPaneCapture.resolve(
            session: "lattices-aaaaaa",
            pane: "dev",
            paneId: nil,
            tty: nil,
            sessions: sessions,
            ttyIndex: [:]
        )
        XCTAssertEqual(target.paneId, "%4")
    }

    func testResolveByTTY() throws {
        let sessions = [
            session("lattices-aaaaaa", panes: [("%3", "claude")]),
        ]
        let target = try TmuxPaneCapture.resolve(
            session: nil,
            pane: nil,
            paneId: nil,
            tty: "/dev/ttys012",
            sessions: sessions,
            ttyIndex: ["ttys012": (session: "lattices-aaaaaa", paneId: "%3")]
        )
        XCTAssertEqual(target.paneId, "%3")
        XCTAssertEqual(target.tty, "/dev/ttys012")
    }
}
