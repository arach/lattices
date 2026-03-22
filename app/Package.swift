// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lattices",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Lattices",
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
