import XCTest
@testable import Lattices

final class SpaceAssignmentsTests: XCTestCase {
    private let uuids = ["": 1, "AAA": 5, "EDA": 6, "U32": 46]

    private func display(_ index: Int, _ ids: [Int]) -> DisplaySpaces {
        DisplaySpaces(displayIndex: index, displayId: "d\(index)",
                      spaces: ids.enumerated().map { SpaceInfo(id: $0.element, index: $0.offset + 1, display: index, isCurrent: $0.offset == 0) },
                      currentSpaceId: ids[0], orderedSpaceIds: ids)
    }

    func testParsesDesktopAllAndMissingBindings() {
        let parsed = SpaceAssignments.parse([
            "com.google.chrome": "EDA",
            "com.apple.finder": "",
            "com.openai.chat": "AllSpaces",
            "to.talkie.app.mac.dev": "GONE",
        ], spaceIdsByUUID: uuids)
        XCTAssertEqual(SpaceAssignments.binding(forBundleId: "com.google.Chrome", in: parsed), .desktop(spaceId: 6))
        XCTAssertEqual(SpaceAssignments.binding(forBundleId: "com.apple.finder", in: parsed), .desktop(spaceId: 1))
        XCTAssertEqual(SpaceAssignments.binding(forBundleId: "com.openai.chat", in: parsed), .allDesktops)
        XCTAssertEqual(SpaceAssignments.binding(forBundleId: "to.talkie.app.mac.dev", in: parsed), .missing(uuid: "GONE"))
        XCTAssertNil(SpaceAssignments.binding(forBundleId: "com.apple.calculator", in: parsed))
    }

    func testConflictOnlyOnTheAssignedDisplay() {
        let displays = [display(0, [1, 5, 6]), display(1, [46])]
        let chrome = SpaceAssignments.Binding.desktop(spaceId: 6)
        XCTAssertEqual(SpaceAssignments.conflict(chrome, destinationSpaceId: 1, displays: displays), 6)
        XCTAssertNil(SpaceAssignments.conflict(chrome, destinationSpaceId: 6, displays: displays))
        XCTAssertNil(SpaceAssignments.conflict(chrome, destinationSpaceId: 46, displays: displays))
        XCTAssertNil(SpaceAssignments.conflict(.allDesktops, destinationSpaceId: 1, displays: displays))
        XCTAssertNil(SpaceAssignments.conflict(nil, destinationSpaceId: 1, displays: displays))
    }
}
