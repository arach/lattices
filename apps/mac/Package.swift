// swift-tools-version: 6.2
import PackageDescription
import Foundation

// HudsonKit source: a local sibling checkout for fast local iteration, or the
// git dependency for CI/release builds that have no sibling repo. Set
// LATTICES_HUDSON_SOURCE=git in CI (and rewrite git@ → token HTTPS for the
// private repo). HudsonVoice requires HUDSONKIT_WITH_VOICE=1 at build time.
let hudsonSource = Context.environment["LATTICES_HUDSON_SOURCE"] ?? "path"
let hudsonDependency: Package.Dependency = hudsonSource == "git"
    ? .package(url: "git@github.com:arach/hudson.git", branch: "main")
    : .package(path: "../../../hudson")

let voiceEnabled = Context.environment["HUDSONKIT_WITH_VOICE"] == "1"

var latticesDependencies: [Target.Dependency] = [
    .product(name: "DeckKit", package: "swift"),
    .product(name: "HudsonUI", package: "hudson"),
    .product(name: "HudsonAI", package: "hudson"),
    .product(name: "HudsonShell", package: "hudson"),
]
if voiceEnabled {
    latticesDependencies.append(.product(name: "HudsonVoice", package: "hudson"))
}

let package = Package(
    name: "Lattices",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../swift"),
        hudsonDependency,
    ],
    targets: [
        .executableTarget(
            name: "Lattices",
            dependencies: latticesDependencies,
            path: "Sources",
            resources: [
                .copy("../Resources/tap.wav"),
                .copy("../Resources/Pets"),
            ],
            swiftSettings: voiceEnabled ? [.define("LATTICES_VOICE")] : []
        ),
        .testTarget(
            name: "LatticesTests",
            path: "Tests"
        )
    ],
    // Stay in Swift 5 language mode: adopt macOS 26 / the 6.2 toolchain without
    // forcing a Swift 6 strict-concurrency migration across the existing app.
    swiftLanguageModes: [.v5]
)