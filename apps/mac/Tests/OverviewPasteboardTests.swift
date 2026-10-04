import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Lattices

final class OverviewPasteboardTests: XCTestCase {
    func testNativeTypesConformToSwiftUIDestinationRegistration() throws {
        for identifier in [OverviewMembershipDrag.type, OverviewWindowDragPayload.type] {
            let type = try XCTUnwrap(UTType(identifier))
            XCTAssertTrue(type.conforms(to: .data), "SwiftUI registers its native destination for public.data/public.item")
        }
    }
    func testBundleExportsBothNativeTypes() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plist)
        let value = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(value["UTExportedTypeDeclarations"] as? [[String: Any]])
        for identifier in [OverviewMembershipDrag.type, OverviewWindowDragPayload.type] {
            let entry = try XCTUnwrap(types.first { $0["UTTypeIdentifier"] as? String == identifier })
            XCTAssertTrue((entry["UTTypeConformsTo"] as? [String])?.contains("public.data") == true)
        }
    }
    func testPreviewPreservesMiddleAndOffCenterGrabOffsets() {
        typealias Source = OverviewImmediateDragSource.Source
        let cursor = CGPoint(x: 500, y: 200)
        let size = CGSize(width: 300, height: 38)
        let center = Source.previewFrame(cursor: cursor, grab: .init(x: 250, y: 16), source: .init(width: 500, height: 32), preview: size)
        XCTAssertEqual(CGPoint(x: center.midX, y: center.midY), cursor)
        let corner = Source.previewFrame(cursor: cursor, grab: .init(x: 50, y: 8), source: .init(width: 500, height: 32), preview: size)
        XCTAssertEqual(corner.minX + size.width * 0.1, cursor.x)
        XCTAssertEqual(corner.minY + size.height * 0.25, cursor.y)
    }
}
