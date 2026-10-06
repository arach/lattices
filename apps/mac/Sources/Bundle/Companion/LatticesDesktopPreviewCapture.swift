import AppKit
import DeckKit
import Foundation
import ScreenCaptureKit

enum LatticesDesktopPreviewCaptureError: LocalizedError {
    case permissionRequired
    case noDisplays
    case displayUnavailable
    case frontmostWindowUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Screen Recording is off on this Mac. Enable Lattices in System Settings → Privacy & Security → Screen & System Audio Recording."
        case .noDisplays:
            return "No Mac display is available to preview."
        case .displayUnavailable:
            return "That Mac display is no longer available. Choose another display."
        case .frontmostWindowUnavailable:
            return "No frontmost Mac window is available to preview."
        case .encodingFailed:
            return "The Mac captured the display but could not prepare the preview image."
        }
    }
}

/// Captures a deliberately bounded still frame for the paired iPad.
///
/// This is not a video stream. The iPad pulls a new encrypted JPEG after it
/// finishes decoding the previous one, which naturally applies backpressure
/// and keeps capture work bounded when the network or client slows down.
@MainActor
enum LatticesDesktopPreviewCapture {
    static func capture(_ request: DeckDesktopPreviewRequest) async throws -> DeckDesktopPreviewFrame {
        guard CGPreflightScreenCaptureAccess() else {
            throw LatticesDesktopPreviewCaptureError.permissionRequired
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw LatticesDesktopPreviewCaptureError.noDisplays
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let selectedIndex: Int
        let filter: SCContentFilter
        let sourceWidth: Int
        let sourceHeight: Int

        switch request.scope {
        case .display:
            selectedIndex = resolvedDisplayIndex(request.displayIndex, screens: screens)
            guard screens.indices.contains(selectedIndex),
                  let selectedDisplayID = displayID(for: screens[selectedIndex]),
                  let selectedDisplay = content.displays.first(where: { $0.displayID == selectedDisplayID }) else {
                throw LatticesDesktopPreviewCaptureError.displayUnavailable
            }
            filter = SCContentFilter(display: selectedDisplay, excludingWindows: [])
            sourceWidth = max(selectedDisplay.width, 1)
            sourceHeight = max(selectedDisplay.height, 1)

        case .frontmostWindow:
            guard let selectedWindow = frontmostWindow(in: content) else {
                throw LatticesDesktopPreviewCaptureError.frontmostWindowUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: selectedWindow)
            sourceWidth = max(Int(selectedWindow.frame.width.rounded()), 1)
            sourceHeight = max(Int(selectedWindow.frame.height.rounded()), 1)
            selectedIndex = displayIndex(containing: selectedWindow.frame.center, screens: screens)
                ?? resolvedDisplayIndex(request.displayIndex, screens: screens)
        }

        let configuration = SCStreamConfiguration()
        let requestedWidth = min(max(request.maxPixelWidth, 720), 1_920)
        let outputWidth = min(sourceWidth, requestedWidth)
        let outputHeight = max(1, Int((Double(sourceHeight) * Double(outputWidth) / Double(sourceWidth)).rounded()))

        configuration.width = outputWidth
        configuration.height = outputHeight
        configuration.captureResolution = .nominal
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = true
        configuration.shouldBeOpaque = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let jpeg = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.64]
        ) else {
            throw LatticesDesktopPreviewCaptureError.encodingFailed
        }

        let displays = screens.enumerated().map { index, screen in
            let screenID = displayID(for: screen)
            let scDisplay = screenID.flatMap { id in
                content.displays.first(where: { $0.displayID == id })
            }
            return DeckDesktopPreviewDisplay(
                displayIndex: index,
                name: screen.localizedName,
                pixelWidth: scDisplay?.width ?? Int(screen.frame.width * screen.backingScaleFactor),
                pixelHeight: scDisplay?.height ?? Int(screen.frame.height * screen.backingScaleFactor)
            )
        }

        return DeckDesktopPreviewFrame(
            capturedAt: .now,
            displayIndex: selectedIndex,
            displays: displays,
            pixelWidth: image.width,
            pixelHeight: image.height,
            jpegBase64: jpeg.base64EncodedString()
        )
    }

    private static func resolvedDisplayIndex(_ requested: Int?, screens: [NSScreen]) -> Int {
        if let requested, screens.indices.contains(requested) {
            return requested
        }
        let pointer = NSEvent.mouseLocation
        return screens.firstIndex(where: { $0.frame.contains(pointer) })
            ?? screens.firstIndex(where: { $0 === NSScreen.main })
            ?? 0
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    private static func displayIndex(containing point: CGPoint, screens: [NSScreen]) -> Int? {
        screens.firstIndex { screen in
            guard let id = displayID(for: screen) else { return false }
            return CGDisplayBounds(id).contains(point)
        }
    }

    private static func frontmostWindow(in content: SCShareableContent) -> SCWindow? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = application.processIdentifier

        if let windowID = frontmostWindowID(for: pid),
           let exact = content.windows.first(where: { $0.windowID == windowID }) {
            return exact
        }

        return content.windows.first { window in
            window.owningApplication?.processID == pid
                && window.isOnScreen
                && window.frame.width >= 120
                && window.frame.height >= 80
        }
    }

    /// CGWindowList is ordered front-to-back. Matching the frontmost app's
    /// first normal-layer window gives ScreenCaptureKit the exact window rather
    /// than whichever same-process utility panel happens to enumerate first.
    private static func frontmostWindowID(for pid: pid_t) -> CGWindowID? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 120,
                  bounds.height >= 80 else {
                continue
            }
            return CGWindowID(number.uint32Value)
        }
        return nil
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
