import SwiftUI

/// Which build this is. `LATTICES_BUNDLE=1` at build time compiles
/// `Sources/Bundle` and defines `LATTICES_BUNDLE`; the free build leaves both
/// out. Core code never names a bundle type: bundle features register a
/// `BundleModule` at launch and core drives them through `BundleModules`.
enum LatticesTier: String {
    case free
    case bundle

    static let current: LatticesTier = {
        #if LATTICES_BUNDLE
        return .bundle
        #else
        return .free
        #endif
    }()

    static var isBundle: Bool { current == .bundle }
}

/// A bundle feature's lifecycle, as core sees it. Every hook is optional;
/// core calls them on the main thread, like the controllers they wrap.
protocol BundleModule: AnyObject {
    var id: String { get }
    /// UI-level features, alongside the app's own controllers at launch.
    func start()
    /// Background services, alongside the daemon's models at boot.
    func startServices()
    /// Daemon endpoints, after the core ones.
    func registerEndpoints(_ api: LatticesApi)
    /// The page for a Settings section this module owns, by section id.
    func settingsPane(section: String) -> AnyView?
    func stop()
    func resetForSystemInputBoundary(reason: String)
}

extension BundleModule {
    func start() {}
    func startServices() {}
    func registerEndpoints(_ api: LatticesApi) {}
    func settingsPane(section: String) -> AnyView? { nil }
    func stop() {}
    func resetForSystemInputBoundary(reason: String) {}
}

enum BundleModules {
    private(set) static var installed: [BundleModule] = []

    static func register(_ module: BundleModule) {
        guard !installed.contains(where: { $0.id == module.id }) else { return }
        installed.append(module)
    }

    static var ids: [String] { installed.map(\.id) }

    static func start() { installed.forEach { $0.start() } }
    static func startServices() { installed.forEach { $0.startServices() } }
    static func registerEndpoints(_ api: LatticesApi) { installed.forEach { $0.registerEndpoints(api) } }

    static func settingsPane(section: String) -> AnyView? {
        installed.lazy.compactMap { $0.settingsPane(section: section) }.first
    }
    static func stop() { installed.reversed().forEach { $0.stop() } }

    static func resetForSystemInputBoundary(reason: String) {
        installed.forEach { $0.resetForSystemInputBoundary(reason: reason) }
    }
}
