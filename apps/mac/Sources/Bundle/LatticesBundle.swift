import Foundation

/// Everything the bundle tier adds, registered once at launch. Compiled only
/// with LATTICES_BUNDLE=1; core reaches these features through `BundleModules`.
enum LatticesBundle {
    static func register() {
        BundleModules.register(SpatialLensModule())
        BundleModules.register(ScreenTextModule())
        BundleModules.register(CompanionModule())
    }
}

/// Spatial Lens: the Ctrl+Option hold that previews and places the window
/// under the pointer.
final class SpatialLensModule: BundleModule {
    let id = "spatial-lens"

    func start() { SpatialLensController.shared.start() }
    func stop() { SpatialLensController.shared.stop() }

    func resetForSystemInputBoundary(reason: String) {
        SpatialLensController.shared.resetForSystemInputBoundary(reason: reason)
    }
}
