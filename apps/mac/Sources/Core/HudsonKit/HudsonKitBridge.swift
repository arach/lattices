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
    /// Canonical path for the in-app chat: the HudAIClient route gives a truly
    /// cancellable stream (stop/steer), so it's on by default. Opt out at runtime:
    /// `defaults write dev.lattices.app useHudAIChat -bool NO`
    static var useHudAIChat: Bool {
        UserDefaults.standard.object(forKey: "useHudAIChat") as? Bool ?? true
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
/// session against the embedded runtime hosted by Lattices.
struct HudsonVoiceSurface: View {
    var onClose: () -> Void

    var body: some View {
        if let runtime = HudsonVoiceRuntimeResolver.resolve(clientId: "lattices") {
            HudVoicePanel(
                endpoint: runtime.endpoint,
                options: runtime.options
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Voice runtime unavailable")
                    .font(.headline)
                Text("Restart Lattices and try again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }
}
#endif
