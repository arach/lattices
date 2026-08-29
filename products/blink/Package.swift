// swift-tools-version: 6.0
import PackageDescription

// Hudson is consumed from the sibling checkout by default (same convention as
// Scout). Set BLINK_HUDSON_SOURCE=git to resolve it from GitHub instead.
let hudsonSource = Context.environment["BLINK_HUDSON_SOURCE"] ?? "path"
let hudsonDependency: Package.Dependency = hudsonSource == "git"
    ? .package(url: "git@github.com:arach/hudson.git", branch: "main")
    : .package(path: "../hudson")

let package = Package(
    name: "Blink",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .executable(name: "BlinkApp", targets: ["BlinkApp"]),
        .executable(name: "blink", targets: ["BlinkCLI"]),
        .library(name: "BlinkCore", targets: ["BlinkCore"]),
        .library(name: "BlinkPeer", targets: ["BlinkPeer"]),
    ],
    dependencies: [
        hudsonDependency,
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "BlinkApp",
            dependencies: [
                "BlinkCore",
                "BlinkPeer",
                .product(name: "HudsonUI", package: "hudson"),
                .product(name: "HudsonShell", package: "hudson"),
                .product(name: "HudsonObservability", package: "hudson"),
            ],
            path: "Sources/BlinkApp"
        ),
        .executableTarget(
            name: "BlinkCLI",
            dependencies: [
                "BlinkCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/BlinkCLI"
        ),
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "BlinkCore",
            dependencies: ["CSQLite"],
            path: "Sources/BlinkCore"
        ),
        .target(
            name: "BlinkPeer",
            dependencies: ["BlinkCore"],
            path: "Sources/BlinkPeer"
        ),
        .testTarget(
            name: "BlinkCoreTests",
            dependencies: ["BlinkCore"],
            path: "Tests/BlinkCoreTests"
        ),
        .testTarget(
            name: "BlinkPeerTests",
            dependencies: ["BlinkCore", "BlinkPeer"],
            path: "Tests/BlinkPeerTests"
        ),
    ]
)
