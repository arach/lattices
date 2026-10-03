import Testing
@testable import BlinkCore

@Suite("TerminalText.clean")
struct TerminalTextTests {
    @Test("Claude Code turn: marker dropped, hard-wrapped prose rejoined")
    func claudeTurn() {
        let raw = """
        ⏺ The reader layer takes whatever you selected in the terminal and
          reflows it so long answers read like prose instead of a column of
          fixed-width rows.

          It keeps paragraphs apart.
        """
        #expect(TerminalText.clean(raw) == """
        The reader layer takes whatever you selected in the terminal and reflows it so long answers read like prose instead of a column of fixed-width rows.

        It keeps paragraphs apart.
        """)
    }

    @Test("short lines broken on purpose stay separate")
    func intentionalBreaks() {
        let raw = """
        Build finished with warnings in these packages today:
        core
        app
        """
        #expect(TerminalText.clean(raw) == raw)
    }

    @Test("narrow selections are never joined")
    func narrowSelection() {
        let raw = "src/a.swift\nsrc/b.swift\nsrc/c.swift"
        #expect(TerminalText.clean(raw) == raw)
    }

    @Test("bullets and headings start their own lines")
    func blocks() {
        let raw = """
        Here is a summary of what changed across the repository this week:
        - first item that is long enough to reach the edge of the column
        - second
        ## Next
        """
        #expect(TerminalText.clean(raw) == raw)
    }

    @Test("a wrapped bullet continuation joins its bullet")
    func wrappedBullet() {
        let raw = """
        - the first bullet is long enough that the program wrapped it right
          here onto a second row
        - second bullet
        """
        #expect(TerminalText.clean(raw) == """
        - the first bullet is long enough that the program wrapped it right here onto a second row
        - second bullet
        """)
    }

    @Test("fenced code is left alone")
    func fences() {
        let raw = """
        Run this to rebuild the editor bundle before launching the app again:
        ```
        cd web/editor && bun install && bun run build
        swift build
        ```
        """
        #expect(TerminalText.clean(raw) == raw)
    }

    @Test("a TUI box frame is peeled")
    func frame() {
        let raw = """
        ╭──────────────────────────────╮
        │ Welcome to the session       │
        │ cwd: ~/dev/lattices          │
        ╰──────────────────────────────╯
        """
        #expect(TerminalText.clean(raw) == "Welcome to the session\ncwd: ~/dev/lattices")
    }

    @Test("box-drawn tables are fenced")
    func table() {
        let raw = """
        Results
        ┌──────┬──────┐
        │ a    │ 1    │
        └──────┴──────┘
        """
        #expect(TerminalText.clean(raw) == """
        Results
        ```
        ┌──────┬──────┐
        │ a    │ 1    │
        └──────┴──────┘
        ```
        """)
    }

    @Test("ANSI escapes and CRLF are stripped")
    func ansi() {
        let raw = "\u{1B}[1;32mok\u{1B}[0m done   \r\n\u{1B}]0;title\u{07}next"
        #expect(TerminalText.clean(raw) == "ok done\nnext")
    }
}
