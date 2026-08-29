import Foundation

/// Slug generation and uniquification.
///
/// Ported from the v1 Tauri implementation
/// (`src-tauri/src/utils/slug.rs`) so that v1 and v2 produce identical slugs.
///
/// Rules:
/// 1. Trim, lowercase.
/// 2. Map `a-z`, `0-9` to themselves; everything else (spaces, punctuation,
///    non-ASCII) becomes a hyphen. (v1 keeps `_` mapped to `-` as well.)
/// 3. Collapse runs of hyphens, drop empty segments, join with a single hyphen.
/// 4. If nothing is left, fall back to "untitled".
///
/// Note: v1 has no length cap, so neither does this port.
public enum Slug {
    public static func generate(from title: String) -> String {
        let lowered = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var mapped = String()
        mapped.reserveCapacity(lowered.count)
        for ch in lowered {
            if (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") {
                mapped.append(ch)
            } else {
                // spaces, '-', '_', and any other character all become '-'
                mapped.append("-")
            }
        }

        let parts = mapped.split(separator: "-", omittingEmptySubsequences: true)
        if parts.isEmpty {
            return "untitled"
        }
        return parts.joined(separator: "-")
    }

    /// Return `base` if unused, otherwise append `-2`, `-3`, … until unique.
    /// Mirrors v1's `generate_unique_slug` numeric-suffix scheme.
    public static func unique(_ base: String, existing: Set<String>) -> String {
        if !existing.contains(base) {
            return base
        }
        var counter = 2
        while true {
            let candidate = "\(base)-\(counter)"
            if !existing.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }
}
