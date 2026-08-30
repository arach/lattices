import Testing
import Foundation
@testable import BlinkCore

@Suite("Title extraction")
struct TitleTests {
    @Test("Empty content falls back to Untitled")
    func emptyContent() {
        #expect(Note.extractTitle(from: "") == "Untitled")
        #expect(Note.extractTitle(from: "   \n\t  ") == "Untitled")
    }

    @Test("Heading markers are stripped")
    func headingStrip() {
        #expect(Note.extractTitle(from: "# Hello") == "Hello")
        #expect(Note.extractTitle(from: "### Deep Heading") == "Deep Heading")
        #expect(Note.extractTitle(from: "#NoSpace") == "NoSpace")
    }

    @Test("Bold and italic markers are stripped")
    func emphasisStrip() {
        #expect(Note.extractTitle(from: "**Bold Title**") == "Bold Title")
        #expect(Note.extractTitle(from: "*Italic Title*") == "Italic Title")
        #expect(Note.extractTitle(from: "__Bold Underscore__") == "Bold Underscore")
        #expect(Note.extractTitle(from: "_Italic Underscore_") == "Italic Underscore")
    }

    @Test("List markers are stripped")
    func listMarkers() {
        #expect(Note.extractTitle(from: "- Bullet item") == "Bullet item")
        #expect(Note.extractTitle(from: "* Star item") == "Star item")
        #expect(Note.extractTitle(from: "+ Plus item") == "Plus item")
        #expect(Note.extractTitle(from: "1. Numbered item") == "Numbered item")
        #expect(Note.extractTitle(from: "12) Paren numbered") == "Paren numbered")
    }

    @Test("Blockquote markers are stripped")
    func blockquote() {
        #expect(Note.extractTitle(from: "> Quoted line") == "Quoted line")
        #expect(Note.extractTitle(from: ">> Double quoted") == "Double quoted")
    }

    @Test("Inline backticks are stripped")
    func backticks() {
        #expect(Note.extractTitle(from: "`code` title") == "code title")
    }

    @Test("Title is capped at 50 characters")
    func fiftyCharCap() {
        let long = String(repeating: "a", count: 80)
        let title = Note.extractTitle(from: long)
        #expect(title.count == 50)
        #expect(title == String(repeating: "a", count: 50))
    }

    @Test("Whitespace-only leading lines are skipped")
    func skipBlankLines() {
        let content = "\n   \n\t\n# Real Title\nbody"
        #expect(Note.extractTitle(from: content) == "Real Title")
    }

    @Test("Only the first non-empty line is used")
    func firstLineOnly() {
        #expect(Note.extractTitle(from: "First line\nSecond line") == "First line")
    }

    @Test("Combined markers strip to plain text")
    func combined() {
        #expect(Note.extractTitle(from: "# **Bold Heading**") == "Bold Heading")
        #expect(Note.extractTitle(from: "> # Quoted heading") == "Quoted heading")
    }

    @Test("title computed property matches extractTitle")
    func computedProperty() {
        let note = Note(id: "x", content: "# Hi", createdAt: .now, updatedAt: .now)
        #expect(note.title == "Hi")
    }
}
