import XCTest
@testable import LatticesTerminalKit

final class LatticesTerminalKitTests: XCTestCase {
    func testNormalizesTTY() {
        XCTAssertEqual(TerminalQuery.normalizeTTY("/dev/ttys003"), "ttys003")
        XCTAssertEqual(TerminalQuery.normalizeTTY("ttys004"), "ttys004")
    }

    func testExtractsLatticesSessionTag() {
        XCTAssertEqual(
            LatticesTerminalTag.extractSessionName(from: "[lattices:myapp-a1b2c3] zsh"),
            "myapp-a1b2c3"
        )
        XCTAssertNil(LatticesTerminalTag.extractSessionName(from: "plain terminal"))
    }

    func testSynthesizerPrefersLatticesTagOverAppWindowIndex() {
        let processTable = [
            100: ProcessEntry(pid: 100, ppid: 1, pgid: 100, tty: "ttys001", comm: "zsh", args: "zsh"),
            101: ProcessEntry(pid: 101, ppid: 100, pgid: 100, tty: "ttys001", comm: "claude", args: "claude", cwd: "/repo")
        ]
        let sessions = [
            TmuxSession(
                name: "repo-a1b2c3",
                windowCount: 1,
                attached: true,
                panes: [
                    TmuxPane(
                        id: "%1",
                        windowIndex: 0,
                        windowName: "main",
                        title: "claude",
                        currentCommand: "claude",
                        pid: 100,
                        isActive: true
                    )
                ]
            )
        ]
        let tabs = [
            TerminalTab(
                app: .iterm2,
                windowIndex: 0,
                tabIndex: 0,
                tty: "ttys001",
                isActiveTab: true,
                title: "repo",
                sessionId: "iterm-session"
            )
        ]
        let windows = [
            TerminalWindow(
                wid: 10,
                app: "iTerm2",
                pid: 200,
                title: "unrelated",
                frame: TerminalFrame(x: 0, y: 0, w: 800, h: 600),
                isOnScreen: true,
                zIndex: 0
            ),
            TerminalWindow(
                wid: 11,
                app: "iTerm2",
                pid: 201,
                title: "[lattices:repo-a1b2c3] zsh",
                frame: TerminalFrame(x: 0, y: 0, w: 800, h: 600),
                isOnScreen: true,
                latticesSession: "repo-a1b2c3",
                zIndex: 1
            )
        ]

        let instances = TerminalSynthesizer.synthesize(
            processTable: processTable,
            interesting: [processTable[101]!],
            tmuxSessions: sessions,
            terminalTabs: tabs,
            terminalWindows: windows
        )

        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances[0].windowId, 11)
        XCTAssertEqual(instances[0].windowResolution, .latticesTag)
        XCTAssertEqual(instances[0].tmuxSession, "repo-a1b2c3")
        XCTAssertTrue(instances[0].hasClaude)
    }

    func testSynthesizerMapsGhosttyByProcessTreeTTY() {
        let processTable = [
            300: ProcessEntry(pid: 300, ppid: 1, pgid: 300, tty: "??", comm: "Ghostty", args: "Ghostty"),
            301: ProcessEntry(pid: 301, ppid: 300, pgid: 300, tty: "ttys009", comm: "zsh", args: "zsh", cwd: "/repo"),
            302: ProcessEntry(pid: 302, ppid: 301, pgid: 300, tty: "ttys009", comm: "node", args: "node server.js", cwd: "/repo")
        ]
        let windows = [
            TerminalWindow(
                wid: 42,
                app: "Ghostty",
                pid: 300,
                title: "repo",
                frame: TerminalFrame(x: 0, y: 0, w: 900, h: 600),
                isOnScreen: true,
                zIndex: 0
            )
        ]

        let instances = TerminalSynthesizer.synthesize(
            processTable: processTable,
            interesting: [processTable[302]!],
            tmuxSessions: [],
            terminalTabs: [],
            terminalWindows: windows
        )

        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances[0].tty, "ttys009")
        XCTAssertEqual(instances[0].app, .ghostty)
        XCTAssertEqual(instances[0].windowId, 42)
        XCTAssertEqual(instances[0].windowResolution, .processTreeTTY)
        XCTAssertEqual(instances[0].cwd, "/repo")
    }
}
