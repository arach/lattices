// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeckKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "DeckKit", targets: ["DeckKit"])
    ],
    targets: [
        .target(name: "DeckKit"),
        .testTarget(
            name: "DeckKitTests",
            dependencies: ["DeckKit"]
        )
    ]
)
