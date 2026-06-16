import Foundation

#if canImport(HudsonVoice)
import HudsonVoice
#endif

enum LatticesVoiceRuntime {
    static func start() {
        #if canImport(HudsonVoice)
        do {
            try HudsonVoiceRuntimeHost.shared.start()
            DiagnosticLog.shared.info("HudsonVoice: embedded runtime host started at \(HudsonVoiceRuntimeHost.shared.capabilityURL.path)")
        } catch {
            DiagnosticLog.shared.warn("HudsonVoice: embedded runtime host failed to start - \(error.localizedDescription)")
        }
        #else
        DiagnosticLog.shared.info("HudsonVoice: runtime host skipped because HudsonVoice is not compiled into this build")
        #endif
    }

    static func stop() {
        #if canImport(HudsonVoice)
        HudsonVoiceRuntimeHost.shared.stop()
        DiagnosticLog.shared.info("HudsonVoice: embedded runtime host stopped")
        #endif
    }
}
