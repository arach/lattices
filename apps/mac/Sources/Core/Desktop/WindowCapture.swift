import CoreGraphics
import ScreenCaptureKit

enum WindowCapture {
    // ScreenCaptureKit replacement for the macOS-26-removed
    // CGWindowListCreateImage window snapshot path. Callers still pass the
    // same CoreGraphics-style options, but unsupported combinations degrade
    // to nil instead of falling back to private/dlsym'd CoreGraphics symbols.
    static func image(
        bounds: CGRect = .null,
        listOption: CGWindowListOption,
        windowID: CGWindowID,
        imageOption: CGWindowImageOption
    ) async -> CGImage? {
        _ = listOption

        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let contentInfo = SCShareableContent.info(for: filter)
            let configuration = SCStreamConfiguration()

            if let sourceRect = sourceRect(from: bounds) {
                configuration.sourceRect = sourceRect
            }

            let pointSize = captureSize(
                bounds: bounds,
                contentRect: contentInfo.contentRect,
                windowFrame: window.frame
            )
            let scale = outputScale(for: imageOption, contentInfo: contentInfo)
            configuration.width = max(1, Int((pointSize.width * scale).rounded(.up)))
            configuration.height = max(1, Int((pointSize.height * scale).rounded(.up)))
            configuration.captureResolution = captureResolution(for: imageOption)
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = imageOption.contains(.boundsIgnoreFraming)
            configuration.ignoreGlobalClipSingleWindow = true
            configuration.capturesShadowsOnly = imageOption.contains(.onlyShadows)
            configuration.shouldBeOpaque = imageOption.contains(.shouldBeOpaque)

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            return nil
        }
    }

    private static func sourceRect(from bounds: CGRect) -> CGRect? {
        guard !bounds.isNull, !bounds.isInfinite, !bounds.isEmpty else {
            return nil
        }
        return bounds
    }

    private static func captureSize(
        bounds: CGRect,
        contentRect: CGRect,
        windowFrame: CGRect
    ) -> CGSize {
        if let sourceRect = sourceRect(from: bounds) {
            return sourceRect.size
        }
        if !contentRect.isNull, !contentRect.isEmpty {
            return contentRect.size
        }
        return windowFrame.size
    }

    private static func captureResolution(
        for imageOption: CGWindowImageOption
    ) -> SCCaptureResolutionType {
        if imageOption.contains(.bestResolution) {
            return .best
        }
        if imageOption.contains(.nominalResolution) {
            return .nominal
        }
        return .automatic
    }

    private static func outputScale(
        for imageOption: CGWindowImageOption,
        contentInfo: SCShareableContentInfo
    ) -> CGFloat {
        if imageOption.contains(.nominalResolution) {
            return 1
        }
        return max(CGFloat(contentInfo.pointPixelScale), 1)
    }
}
