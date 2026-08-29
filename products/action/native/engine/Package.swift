// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ActionHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ActionCore",
            targets: ["ActionCore"]
        ),
        .executable(
            name: "ActionHost",
            targets: ["ActionHost"]
        ),
        .executable(
            name: "ActionAgent",
            targets: ["ActionAgent"]
        ),
        .executable(
            name: "ActionAgentCLI",
            targets: ["ActionAgentCLI"]
        ),
        .executable(
            name: "WebKitProbe",
            targets: ["WebKitProbe"]
        )
    ],
    targets: [
        .target(
            name: "ActionCore",
            path: "CoreSources"
        ),
        .executableTarget(
            name: "ActionHost",
            dependencies: ["ActionCore"],
            path: "Sources"
        ),
        .executableTarget(
            name: "ActionAgent",
            dependencies: ["ActionCore"],
            path: "AgentSources"
        ),
        .executableTarget(
            name: "ActionAgentCLI",
            dependencies: ["ActionCore"],
            path: "AgentCLISources"
        ),
        .executableTarget(
            name: "WebKitProbe",
            path: "ProbeSources"
        ),
        .testTarget(
            name: "ActionCoreTests",
            dependencies: ["ActionCore"],
            path: "CoreTests"
        )
    ]
)
