import Foundation
import CryptoKit

/// The Blink namespace UUID, ported verbatim from v1
/// (`src-tauri/src/utils/uuid_from_slug.rs`). Both v1 and v2 must use the same
/// namespace so a given slug derives the same UUIDv5 in either app.
///
/// `6ba7b810-9dad-11d1-80b4-00c04fd430c8`
private let blinkNamespaceBytes: [UInt8] = [
    0x6b, 0xa7, 0xb8, 0x10,
    0x9d, 0xad,
    0x11, 0xd1,
    0x80, 0xb4,
    0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
]

/// Generate a deterministic RFC-4122 UUID version 5 (SHA-1) from a slug, using the
/// Blink namespace. The same slug always produces the same UUID, matching v1.
public func uuidFromSlug(_ slug: String) -> UUID {
    var input = blinkNamespaceBytes
    input.append(contentsOf: Array(slug.utf8))

    let digest = Insecure.SHA1.hash(data: Data(input))
    var bytes = Array(digest.prefix(16)) // first 16 bytes of the 20-byte SHA-1

    // Set version to 5: high nibble of byte 6.
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    // Set variant to RFC 4122: two high bits of byte 8 → 10.
    bytes[8] = (bytes[8] & 0x3F) | 0x80

    let uuidBytes: uuid_t = (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    )
    return UUID(uuid: uuidBytes)
}
