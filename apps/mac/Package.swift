// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lattices",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../swift")
    ],
    targets: [
        .executableTarget(
            name: "Lattices",
            dependencies: [
                .product(name: "DeckKit", package: "swift")
            ],
            path: "Sources",
            resources: [
                .copy("../Resources/tap.wav"),
            ]
        ),
        .testTarget(
            name: "LatticesTests",
            path: "Tests"
        )
    ]
)
