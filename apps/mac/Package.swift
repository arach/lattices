// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lattices",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../swift"),
        // HudsonKit spike — local path for fast iteration. Mirror vox/app's
        // git dependency (git@github.com:arach/hudson.git, branch: main) for
        // real adoption. HudsonVoice requires HUDSONKIT_WITH_VOICE=1 at build time.
        .package(path: "../../../hudson"),
    ],
    targets: [
        .executableTarget(
            name: "Lattices",
            dependencies: [
                .product(name: "DeckKit", package: "swift"),
                .product(name: "HudsonUI", package: "hudson"),
                .product(name: "HudsonAI", package: "hudson"),
                .product(name: "HudsonVoice", package: "hudson"),
                .product(name: "HudsonShell", package: "hudson"),
            ],
            path: "Sources",
            resources: [
                .copy("../Resources/tap.wav"),
                .copy("../Resources/Pets"),
            ]
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
