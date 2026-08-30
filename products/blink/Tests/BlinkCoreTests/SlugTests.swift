import Testing
import Foundation
@testable import BlinkCore

@Suite("Slug generation")
struct SlugTests {
    // Ported from v1 src-tauri/src/tests/slug_test.rs so v1 and v2 agree.
    @Test("Basic slug generation matches v1")
    func basicGeneration() {
        #expect(Slug.generate(from: "Hello World") == "hello-world")
        #expect(Slug.generate(from: "Test  Multiple   Spaces") == "test-multiple-spaces")
        #expect(Slug.generate(from: "Special!@#$%^&*()Characters") == "special-characters")
        #expect(Slug.generate(from: "Mix123Numbers") == "mix123numbers")
        #expect(Slug.generate(from: "UPPERCASE") == "uppercase")
    }

    // NOTE: The v1 *test* asserts generate_slug("") == "", but the v1 *code*
    // (verified by running it standalone) returns "untitled" for empty/all-special
    // input. We match the actual v1 runtime behavior, not the stale test assertion.
    @Test("Empty and all-special input falls back to untitled (matches v1 code)")
    func emptyFallback() {
        #expect(Slug.generate(from: "") == "untitled")
        #expect(Slug.generate(from: "!@#$") == "untitled")
        #expect(Slug.generate(from: "   ") == "untitled")
    }

    @Test("Deterministic slugs match v1")
    func deterministic() {
        let title = "My Amazing Note Title!"
        #expect(Slug.generate(from: title) == Slug.generate(from: title))
        #expect(Slug.generate(from: title) == "my-amazing-note-title")
    }

    // Ported from v1 test_generate_unique_slug.
    @Test("Unique slug appends numeric suffixes")
    func uniqueSuffixing() {
        let existing: Set<String> = ["hello-world", "hello-world-2"]
        #expect(Slug.unique(Slug.generate(from: "Hello World"), existing: existing) == "hello-world-3")
        #expect(Slug.unique(Slug.generate(from: "New Title"), existing: existing) == "new-title")
    }

    @Test("Unique returns base when unused")
    func uniqueBase() {
        #expect(Slug.unique("fresh", existing: []) == "fresh")
    }

    @Test("Unique skips consecutive taken suffixes")
    func uniqueSkips() {
        let existing: Set<String> = ["note", "note-2", "note-3", "note-4"]
        #expect(Slug.unique("note", existing: existing) == "note-5")
    }
}
