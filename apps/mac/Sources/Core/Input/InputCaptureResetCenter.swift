import Foundation

enum InputCaptureResetCenter {
    static func reset(reason: String) {
        if Thread.isMainThread {
            performReset(reason: reason)
        } else {
            DispatchQueue.main.async {
                performReset(reason: reason)
            }
        }
    }

    private static func performReset(reason: String) {
        DiagnosticLog.shared.warn("InputCapture: reset for \(reason)")
        ScreenOverlayCanvasController.shared.resetInputCapture(reason: reason)
        MouseGestureController.shared.resetForSystemInputBoundary(reason: reason)
        KeyboardRemapController.shared.resetForSystemInputBoundary(reason: reason)
    }
}
