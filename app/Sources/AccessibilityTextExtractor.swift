import AppKit

// Private API: get CGWindowID from an AXUIElement (already declared in WindowTiler.swift)
// We reuse the same _AXUIElementGetWindow binding.

struct AXTextResult {
    let wid: UInt32
    let texts: [String]
    let fullText: String
}

final class AccessibilityTextExtractor {
    static let timeoutSeconds: TimeInterval = 0.2
    static let maxDepth: Int = 4
    static let maxChildrenPerNode: Int = 30

    /// Extract text from a window's AX element tree.
    /// Returns nil if AX fails or yields fewer than `minChars` characters.
    func extract(pid: Int32, wid: UInt32, minChars: Int = 12) -> AXTextResult? {
        let appRef = AXUIElementCreateApplication(pid)

        // Find the AXUIElement matching this wid
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let axWindows = windowsRef as? [AXUIElement] else { return nil }

        var targetWindow: AXUIElement?
        for axWin in axWindows {
            var winID: CGWindowID = 0
            if _AXUIElementGetWindow(axWin, &winID) == .success, winID == CGWindowID(wid) {
                targetWindow = axWin
                break
            }
        }

        guard let window = targetWindow else { return nil }

        let deadline = Date().addingTimeInterval(Self.timeoutSeconds)
        var collected: [String] = []

        walkChildren(element: window, depth: 0, deadline: deadline, collected: &collected)

        let fullText = collected.joined(separator: "\n")
        guard fullText.count >= minChars else { return nil }

        return AXTextResult(wid: wid, texts: collected, fullText: fullText)
    }

    // MARK: - Tree Walker

    private func walkChildren(
        element: AXUIElement,
        depth: Int,
        deadline: Date,
        collected: inout [String]
    ) {
        guard depth < Self.maxDepth, Date() < deadline else { return }

        // Extract text attributes from this element
        extractText(from: element, into: &collected)

        // Get children — prefer visible children, fall back to all children
        var childrenRef: CFTypeRef?
        var gotChildren = false

        let visErr = AXUIElementCopyAttributeValue(element, kAXVisibleChildrenAttribute as CFString, &childrenRef)
        if visErr == .success, let children = childrenRef as? [AXUIElement], !children.isEmpty {
            gotChildren = true
            let capped = children.prefix(Self.maxChildrenPerNode)
            for child in capped {
                guard Date() < deadline else { return }
                walkChildren(element: child, depth: depth + 1, deadline: deadline, collected: &collected)
            }
        }

        if !gotChildren {
            childrenRef = nil
            let childErr = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            if childErr == .success, let children = childrenRef as? [AXUIElement] {
                let capped = children.prefix(Self.maxChildrenPerNode)
                for child in capped {
                    guard Date() < deadline else { return }
                    walkChildren(element: child, depth: depth + 1, deadline: deadline, collected: &collected)
                }
            }
        }
    }

    private func extractText(from element: AXUIElement, into collected: inout [String]) {
        // kAXValueAttribute — text field contents, labels, etc.
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let str = valueRef as? String, !str.isEmpty, str.count > 1 {
            collected.append(str)
        }

        // kAXTitleAttribute — window/button titles
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let str = titleRef as? String, !str.isEmpty, str.count > 1 {
            collected.append(str)
        }

        // kAXDescriptionAttribute — accessible descriptions
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let str = descRef as? String, !str.isEmpty, str.count > 1 {
            collected.append(str)
        }
    }
}
