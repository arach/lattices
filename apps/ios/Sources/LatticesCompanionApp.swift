import SwiftUI

@main
struct LatticesCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--fleet-design") {
                // The design source's own data, for comparison against the artifact.
                // Add --fleet-focus to boot into the design's second layout.
                FleetDeckPreviewHost(
                    machineCount: 4,
                    useDesignFixture: true,
                    fixtureLayout: ProcessInfo.processInfo.arguments.contains("--fleet-focus") ? .focus : .ops
                )
            } else if ProcessInfo.processInfo.arguments.contains("--fleet-preview") {
                FleetDeckPreviewHost(machineCount: 4)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
