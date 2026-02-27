import SwiftUI

@main
struct LatticeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var scanner = ProjectScanner.shared

    var body: some Scene {
        MenuBarExtra("Lattice", systemImage: "terminal") {
            MainView(scanner: scanner)
        }
        .menuBarExtraStyle(.window)
    }
}
