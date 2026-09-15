import XCTest
@testable import Lattices

final class CompanionAppCatalogTests: XCTestCase {
    func testFirstPartyOrderAndIndependentIdentities() {
        XCTAssertEqual(CompanionAppCatalog.firstParty.map(\.id), [.blink, .action, .speech])
        XCTAssertEqual(CompanionAppCatalog.firstParty.compactMap(\.bundleIdentifier),
            ["dev.arach.blink", "dev.lattices.Action", "dev.lattices.Speech"])
        XCTAssertTrue(CompanionAppCatalog.firstParty.allSatisfy { $0.distribution == .standaloneApp })
    }
    func testEveryMissingCompanionOffersInstall() {
        for product in CompanionAppCatalog.firstParty {
            XCTAssertEqual(CompanionAppCatalog.action(for: product, installState: .missing), .get)
        }
        XCTAssertEqual(CompanionAppAction.get.menuTitle, "Install")
    }
    func testEveryInstalledCompanionOffersOpen() {
        for product in CompanionAppCatalog.firstParty {
            XCTAssertEqual(CompanionAppCatalog.action(for: product,
                installState: .installed(url: URL(fileURLWithPath: "/fixture/\(product.displayName).app"))), .open)
        }
        XCTAssertEqual(CompanionAppAction.open.menuTitle, "Open")
    }
}
