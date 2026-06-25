import Foundation

#if canImport(HudsonVoice)
import HudsonVoice
#endif

enum LatticesVoiceRuntime {
    static func start() {
        #if canImport(HudsonVoice)
        DiagnosticLog.shared.info("HudsonVoice: live session client compiled in")
        #else
        DiagnosticLog.shared.info("HudsonVoice: runtime host skipped because HudsonVoice is not compiled into this build")
        #endif
    }

    static func stop() {
        #if canImport(HudsonVoice)
        DiagnosticLog.shared.info("HudsonVoice: live session client stopped")
        #endif
    }
}
