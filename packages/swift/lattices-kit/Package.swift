// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lattices-kit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LatticesKit", targets: ["LatticesKit"]),
    ],
    targets: [
        .target(name: "LatticesKit"),
        .testTarget(
            name: "LatticesKitTests",
            dependencies: ["LatticesKit"]
        ),
    ]
)
