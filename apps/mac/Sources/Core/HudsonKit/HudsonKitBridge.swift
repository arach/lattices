import Foundation
import SwiftUI

#if canImport(HudsonVoice)
import HudsonVoice
#endif

/// Spike switch for migrating Lattices surfaces onto HudsonKit.
///
/// HudsonKit (git@github.com:arach/hudson.git) was extracted from Lattices'
/// own surface patterns, so its `HudsonShell` / `HudsonUI` / `HudsonVoice` /
/// `HudAI` modules map almost 1:1 onto Lattices' local overlays. This flag lets
/// us bring those up one surface at a time without a big-bang cutover.
///
/// Flip at runtime:  `defaults write dev.lattices.app useHudsonKit -bool YES`
enum HudsonKitSwitch {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "useHudsonKit")
    }

    /// Route the workspace-assistant chat through HudsonKit's `HudAIClient`
    /// (with pi as a `HudAIProviderAdapter`) instead of driving `PiRpcRuntime`
    /// directly. Independent of the voice switch so each surface can be cut over
    /// on its own.
    ///
    /// Flip at runtime:  `defaults write dev.lattices.app useHudAIChat -bool YES`
    static var useHudAIChat: Bool {
        UserDefaults.standard.bool(forKey: "useHudAIChat")
    }

    /// Whether the HudsonKit voice surface is compiled in
    /// (the `HudsonVoice` product only exists when the app is built with
    /// `HUDSONKIT_WITH_VOICE=1`).
    static var voiceAvailable: Bool {
        #if canImport(HudsonVoice)
        return true
        #else
        return false
        #endif
    }
}

#if canImport(HudsonVoice)
/// The HudsonKit-backed voice surface. `HudVoicePanel` manages its own live
/// session against the local voxd daemon. We hand it the endpoint discovered from
/// `~/.vox/runtime.json` (via `VoxEndpointResolver`) rather than letting it trust
/// the SDK default port (42138), which doesn't match the running voxd (42137).
struct HudsonVoiceSurface: View {
    var onClose: () -> Void

    var body: some View {
        HudVoicePanel(endpoint: VoxEndpointResolver.resolve())
    }
}
#endif
