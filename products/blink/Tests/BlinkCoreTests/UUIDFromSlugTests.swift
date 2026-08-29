import Testing
import Foundation
@testable import BlinkCore

@Suite("UUID from slug")
struct UUIDFromSlugTests {
    @Test("Same slug always produces the same UUID")
    func deterministic() {
        let slug = "my-awesome-note"
        #expect(uuidFromSlug(slug) == uuidFromSlug(slug))
    }

    @Test("Different slugs produce different UUIDs")
    func distinct() {
        #expect(uuidFromSlug("note-one") != uuidFromSlug("note-two"))
    }

    // Exact expected values computed from the ported namespace
    // 6ba7b810-9dad-11d1-80b4-00c04fd430c8 (RFC 4122 UUIDv5 / SHA-1). These must
    // match v1, which uses the same namespace.
    @Test("Exact UUIDv5 values match the ported namespace")
    func exactValues() {
        #expect(uuidFromSlug("my-awesome-note").uuidString == "1F2391D2-759D-5E0A-8016-06F84F9CA17B")
        #expect(uuidFromSlug("note-one").uuidString == "D02DB6DE-11E6-5E5E-9F9C-911AEC0DF756")
        #expect(uuidFromSlug("note-two").uuidString == "F7F07373-1347-56A7-A032-3C3B07EA0CEF")
        #expect(uuidFromSlug("hello-world").uuidString == "3A9A08E0-C529-596C-821B-1F223CBE1835")
    }

    @Test("Version bits are 5 and variant bits are RFC 4122")
    func versionAndVariant() {
        let bytes = withUnsafeBytes(of: uuidFromSlug("any-slug").uuid) { Array($0) }
        // Version: high nibble of byte 6 must be 5.
        #expect((bytes[6] & 0xF0) == 0x50)
        // Variant: two high bits of byte 8 must be 10 (0x80..0xBF).
        #expect((bytes[8] & 0xC0) == 0x80)
    }
}
