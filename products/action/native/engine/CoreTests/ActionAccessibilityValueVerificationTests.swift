@testable import ActionCore
import Foundation
import XCTest

final class ActionAccessibilityValueVerificationTests: XCTestCase {
    func testExactEchoMatches() {
        XCTAssertEqual(
            actionAccessibilityValueVerdict(requested: "hello", before: "", observed: "hello"),
            .matched
        )
    }

    /// The reported failure: a terminal accepts the write, keeps its own content, and the write
    /// used to be reported as a success.
    func testAcceptedButIgnoredWriteIsUnchanged() {
        XCTAssertEqual(
            actionAccessibilityValueVerdict(
                requested: "claude --resume",
                before: "arach@mac ~ %",
                observed: "arach@mac ~ %"
            ),
            .unchanged
        )
    }

    func testTrailingWhitespaceNormalizationStillMatches() {
        XCTAssertEqual(
            actionAccessibilityValueVerdict(requested: "note body", before: "", observed: "note body\n"),
            .matched
        )
    }

    func testInsertionIntoExistingContentMatches() {
        XCTAssertEqual(
            actionAccessibilityValueVerdict(
                requested: "world",
                before: "hello ",
                observed: "hello world"
            ),
            .matched
        )
    }

    /// Text already present before the write must not be read as evidence that the write landed.
    func testPreexistingTextIsNotTreatedAsAWrite() {
        XCTAssertEqual(
            actionAccessibilityValueVerdict(
                requested: "world",
                before: "hello world",
                observed: "hello world"
            ),
            .unchanged
        )
    }

    func testValueRewrittenByTheAppIsMismatched() {
        XCTAssertEqual(
            actionAccessibilityValueVerdict(requested: "1234", before: "$0.00", observed: "$1,234.00"),
            .mismatched
        )
    }

    func testElementWithNoReadableValueIsUnreadable() {
        XCTAssertEqual(
            actionAccessibilityValueVerdict(requested: "hello", before: nil, observed: nil),
            .unreadable
        )
    }

    func testClearingAFieldIsVerified() {
        XCTAssertEqual(
            actionAccessibilityValueVerdict(requested: "", before: "stale", observed: ""),
            .matched
        )
        XCTAssertEqual(
            actionAccessibilityValueVerdict(requested: "", before: "stale", observed: "stale"),
            .unchanged
        )
    }

    func testFailureDetailNamesTheObservedValueAndTheWayOut() {
        let detail = actionAccessibilityValueFailureDetail(
            verdict: .unchanged,
            requested: "claude --resume",
            observed: "arach@mac ~ %",
            describing: "com.googlecode.iterm2 element Terminal"
        )

        XCTAssertTrue(detail.contains("com.googlecode.iterm2 element Terminal"))
        XCTAssertTrue(detail.contains("arach@mac ~ %"))
        XCTAssertTrue(detail.contains("type-text"))
    }

    func testExcerptShortensLongValues() {
        let excerpt = actionAccessibilityValueExcerpt(String(repeating: "a", count: 400))

        XCTAssertTrue(excerpt.contains("…"))
        XCTAssertTrue(excerpt.contains("400 characters"))
    }

    func testExcerptKeepsNewlinesOnOneLine() {
        XCTAssertEqual(actionAccessibilityValueExcerpt("a\nb"), "\"a\\nb\"")
    }
}
