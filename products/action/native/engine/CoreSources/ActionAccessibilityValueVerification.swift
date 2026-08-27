import Foundation

/// What a `kAXValue` write actually did, judged by reading the value back.
public enum ActionAccessibilityValueVerdict: String, Sendable {
    /// The element now holds the requested text.
    case matched
    /// The write was accepted and changed nothing — the element is not the live input.
    case unchanged
    /// The value moved, but not to the requested text.
    case mismatched
    /// The element exposes no readable value, so the write cannot be verified either way.
    case unreadable
}

/// Judges a value write from what the element held before and what it holds after.
///
/// `AXUIElementSetAttributeValue` returning `.success` only says the app accepted the message.
/// A terminal's text area accepts a value write and ignores it, so the return code alone reported
/// a `type` action as succeeded with nothing typed. The read-back is the only real evidence.
///
/// Kept separate from the AX calls so the decision is testable without a live application.
public func actionAccessibilityValueVerdict(
    requested: String,
    before: String?,
    observed: String?
) -> ActionAccessibilityValueVerdict {
    guard let observed else {
        return .unreadable
    }

    if observed == requested {
        return .matched
    }

    // Fields that own their formatting commonly re-emit the value with surrounding whitespace
    // stripped or a trailing newline added. That is the same text, not a failed write.
    let trimmedObserved = observed.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedRequested = requested.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedObserved == trimmedRequested {
        return .matched
    }

    // A text view that inserts into existing content holds more than what was written. Requiring
    // the value to have moved keeps this from passing on text that was already there.
    if observed != before, !trimmedRequested.isEmpty, observed.contains(requested) {
        return .matched
    }

    if observed == before {
        return .unchanged
    }

    return .mismatched
}

/// Builds the operator-facing explanation for a write that could not be confirmed.
///
/// Each case names what was observed and what to do instead, because the caller's next move
/// differs: an ignored write needs the HID path, a changed-but-different value is usually the
/// app reformatting, and an unreadable element cannot be confirmed by any amount of retrying.
public func actionAccessibilityValueFailureDetail(
    verdict: ActionAccessibilityValueVerdict,
    requested: String,
    observed: String?,
    describing target: String
) -> String {
    let requestedText = actionAccessibilityValueExcerpt(requested)
    let observedText = actionAccessibilityValueExcerpt(observed)

    switch verdict {
    case .matched:
        return "Accessibility value write to \(target) applied \(requestedText)."
    case .unchanged:
        return "Accessibility value write to \(target) was accepted but changed nothing — the value is still \(observedText). This element is not the live input for \(requestedText); send the text through the HID path (type-text) instead of a semantic target."
    case .mismatched:
        return "Accessibility value write to \(target) left \(observedText), not the requested \(requestedText). The app rewrote the value; confirm the element is the intended field before retrying."
    case .unreadable:
        return "Accessibility value write to \(target) reported success, but the element exposes no readable value, so \(requestedText) could not be confirmed as applied. Send the text through the HID path (type-text) when the result must be verified."
    }
}

/// Quotes a value for an error message, shortened so a whole document body cannot bury the point.
public func actionAccessibilityValueExcerpt(_ value: String?, limit: Int = 120) -> String {
    guard let value else {
        return "no value"
    }

    let singleLine = value
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
    if singleLine.count <= limit {
        return "\"\(singleLine)\""
    }

    return "\"\(singleLine.prefix(limit))…\" (\(value.count) characters)"
}
