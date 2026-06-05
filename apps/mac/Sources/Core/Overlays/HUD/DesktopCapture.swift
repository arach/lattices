import AppKit
import CoreImage
import Foundation
import ScreenCaptureKit

// Grabs a snapshot of the screen region under the HUD panels (before they become visible)
// and runs a CIFilter pipeline to produce a blurred, desaturated "desktop impression".

final class DesktopCapture {
    static let shared = DesktopCapture()

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // ScreenCaptureKit replaces the macOS-26-removed CGWindowListCreateImage.
    // Capture is async; the only caller (HUDController.captureDesktop) already
    // runs it off the main thread and assigns the result asynchronously.
    func captureScreen(_ screen: NSScreen) async -> NSImage? {
        // Panels are at alpha=0 when this fires, so the capture naturally excludes them.
        let cgImage: CGImage? = await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(in: screen.frame) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let cgImage else { return nil }
        return filtered(cgImage)
    }

    private func filtered(_ source: CGImage) -> NSImage? {
        var img = CIImage(cgImage: source)

        // 1. Heavy blur — destroys readable content, keeps colour and shape
        if let f = CIFilter(name: "CIGaussianBlur",
                            parameters: [kCIInputImageKey: img, kCIInputRadiusKey: 32.0]) {
            img = f.outputImage ?? img
        }

        // 2. Pull saturation way down, slight brightness reduction
        if let f = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: img,
            kCIInputSaturationKey: 0.22,
            kCIInputBrightnessKey: -0.06
        ]) {
            img = f.outputImage ?? img
        }

        // Clamp to source dimensions to avoid infinite extent from blur
        let rect = CGRect(origin: .zero, size: CGSize(width: source.width, height: source.height))
        guard let out = ciContext.createCGImage(img.clamped(to: rect), from: rect) else { return nil }

        // Return at half resolution — it's blurred anyway, no need for full res
        return NSImage(cgImage: out, size: CGSize(
            width: CGFloat(source.width) / 2,
            height: CGFloat(source.height) / 2
        ))
    }
}
