// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LatticeApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LatticeApp",
            path: "Sources"
        )
    ]
)
