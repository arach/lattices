// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeckKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "DeckKit", targets: ["DeckKit"]),
        .library(name: "LatticesTerminalKit", targets: ["LatticesTerminalKit"])
    ],
    targets: [
        .target(name: "DeckKit"),
        .target(name: "LatticesTerminalKit"),
        .testTarget(
            name: "DeckKitTests",
            dependencies: ["DeckKit"]
        ),
        .testTarget(
            name: "LatticesTerminalKitTests",
            dependencies: ["LatticesTerminalKit"]
        )
    ]
)
