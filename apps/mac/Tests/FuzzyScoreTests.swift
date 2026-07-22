import XCTest
@testable import Lattices

/// Tier ordering and edge cases for the command bar's fuzzy scorer.
final class FuzzyScoreTests: XCTestCase {

    func testExactBeatsEverything() {
        XCTAssertEqual(FuzzyScore.score(query: "safari", candidate: "Safari"), 120)
    }

    func testPrefixTier() {
        XCTAssertEqual(FuzzyScore.score(query: "saf", candidate: "Safari"), 100)
    }

    func testWordPrefixTier() {
        XCTAssertEqual(FuzzyScore.score(query: "chr", candidate: "Google Chrome"), 85)
        XCTAssertEqual(FuzzyScore.score(query: "win", candidate: "Tile Window"), 85)
    }

    func testInitialsTier() {
        XCTAssertEqual(FuzzyScore.score(query: "tw", candidate: "Tile Window"), 80)
        XCTAssertEqual(FuzzyScore.score(query: "cb", candidate: "CommandBar"), 80)
    }

    func testSubstringTier() {
        XCTAssertEqual(FuzzyScore.score(query: "far", candidate: "Safari"), 60)
    }

    func testSubstringBeatsLooseSubsequence() {
        // "safari" contains "sai" only as a subsequence, "far" as a substring —
        // the substring tier must always outrank a subsequence hit.
        let substring = FuzzyScore.score(query: "far", candidate: "Safari")
        let subsequence = FuzzyScore.score(query: "sai", candidate: "Safari")
        XCTAssertGreaterThan(subsequence, 0)
        XCTAssertGreaterThan(substring, subsequence)
        XCTAssertLessThanOrEqual(subsequence, 55)
    }

    func testSubsequenceMatch() {
        XCTAssertGreaterThan(FuzzyScore.score(query: "gc", candidate: "Google Chrome"), 0)
    }

    func testNoMatch() {
        XCTAssertEqual(FuzzyScore.score(query: "xyz", candidate: "Safari"), 0)
    }

    func testDiacriticFolding() {
        XCTAssertEqual(FuzzyScore.score(query: "cafe", candidate: "Café"), 120)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(FuzzyScore.score(query: "SAF", candidate: "safari"), 100)
    }

    func testEmptyInputs() {
        XCTAssertEqual(FuzzyScore.score(query: "", candidate: "Safari"), 0)
        XCTAssertEqual(FuzzyScore.score(query: "saf", candidate: ""), 0)
    }

    func testSeparatorWordStarts() {
        XCTAssertEqual(FuzzyScore.score(query: "win", candidate: "tile_window"), 85)
        XCTAssertEqual(FuzzyScore.score(query: "win", candidate: "tile-window"), 85)
    }
}
