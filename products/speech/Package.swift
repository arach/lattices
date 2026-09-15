// swift-tools-version: 6.2
import PackageDescription
import Foundation
let env = ProcessInfo.processInfo.environment
let hudson: Package.Dependency = env["SPEECH_HUDSON_PATH"].map { .package(name: "hudson", path: $0) }
    ?? .package(url: "git@github.com:arach/hudson.git", branch: "main")
let vox: Package.Dependency = env["SPEECH_VOX_PATH"].map { .package(name: "vox", path: $0) }
    ?? .package(url: "https://github.com/arach/vox.git", branch: "main")
let package = Package(name: "Speech", platforms: [.macOS(.v26)],
    products: [.executable(name: "Speech", targets: ["SpeechAppRuntime"])],
    dependencies: [hudson, vox], targets: [
        .executableTarget(name: "SpeechAppRuntime", dependencies: [
            .product(name: "HudsonUI", package: "hudson"),
            .product(name: "HudsonUIAudio", package: "hudson"),
            .product(name: "HudsonSpeechEngine", package: "vox"),
            .product(name: "VoxCore", package: "vox"),
            .product(name: "VoxService", package: "vox")], path: "Sources/Speech"),
        .testTarget(name: "SpeechTests", dependencies: ["SpeechAppRuntime"], swiftSettings: [.define("SPEECH_FORWARDING_TESTS")])
    ], swiftLanguageModes: [.v5])
