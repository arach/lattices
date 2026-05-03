import CoreGraphics
import Darwin

enum WindowCapture {
    // Transitional wrapper for the old CoreGraphics window snapshot API.
    // macOS 26 rejects direct references because ScreenCaptureKit is the supported path;
    // this can return nil if Apple removes the symbol, so preview/OCR callers must degrade.
    private typealias CGWindowListCreateImageFn = @convention(c) (
        CGRect,
        CGWindowListOption,
        CGWindowID,
        CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    private static let createImage: CGWindowListCreateImageFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY) else {
            return nil
        }
        guard let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CGWindowListCreateImageFn.self)
    }()

    static func image(
        bounds: CGRect = .null,
        listOption: CGWindowListOption,
        windowID: CGWindowID,
        imageOption: CGWindowImageOption
    ) -> CGImage? {
        createImage?(bounds, listOption, windowID, imageOption)?.takeRetainedValue()
    }
}
