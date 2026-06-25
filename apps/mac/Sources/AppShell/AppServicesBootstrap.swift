enum AppServicesBootstrap {
    static func start() {
        let diagnosticLog = DiagnosticLog.shared
        let timedBoot = diagnosticLog.startTimed("Daemon services boot")
        OcrStore.shared.open()
        DesktopModel.shared.start()
        OcrModel.shared.start()
        TmuxModel.shared.start()
        ProcessModel.shared.start()
        LatticesVoiceRuntime.start()
        LatticesApi.setup()
        DaemonServer.shared.start()
        if Preferences.shared.companionBridgeEnabled {
            LatticesCompanionBridgeServer.shared.start()
        } else {
            diagnosticLog.info("CompanionBridge: disabled by preference")
        }
        diagnosticLog.finish(timedBoot)
    }

    static func stop() {
        LatticesVoiceRuntime.stop()
        WorkspaceAssistantSession.shared.shutdown()
        LatticesCompanionBridgeServer.shared.stop()
        DaemonServer.shared.stop()
    }
}
