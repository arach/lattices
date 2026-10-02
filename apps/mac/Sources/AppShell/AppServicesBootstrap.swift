enum AppServicesBootstrap {
    static func start() {
        let diagnosticLog = DiagnosticLog.shared
        let timedBoot = diagnosticLog.startTimed("Daemon services boot")
        DesktopModel.shared.start()
        BundleModules.startServices()
        TmuxModel.shared.start()
        ProcessModel.shared.start()
        LatticesVoiceRuntime.start()
        LatticesApi.setup()
        DaemonServer.shared.start()
        diagnosticLog.finish(timedBoot)
    }

    static func stop() {
        LatticesVoiceRuntime.stop()
        WorkspaceAssistantSession.shared.shutdown()
        DaemonServer.shared.stop()
    }
}
