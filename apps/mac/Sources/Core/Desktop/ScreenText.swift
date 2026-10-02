import AppKit
import Combine
import Vision

// MARK: - Data Types

enum TextSource: String {
    case accessibility
    case ocr
}

struct OcrTextBlock {
    let text: String
    let confidence: Float         // 0.0–1.0
    let boundingBox: CGRect       // normalized coordinates within window
}

struct OcrWindowResult {
    let wid: UInt32
    let app: String
    let title: String
    let frame: WindowFrame
    let texts: [OcrTextBlock]
    let fullText: String
    let timestamp: Date
    let source: TextSource
}

struct OcrSearchResult {
    let id: Int64
    let wid: UInt32
    let app: String
    let title: String
    let frame: WindowFrame
    let fullText: String
    let snippet: String
    let timestamp: Date
    let source: TextSource
}

// MARK: - Screen Text Index

/// The background screen-text index (periodic OCR of on-screen windows plus
/// its history). The bundle installs one; the free build has none, and every
/// read through `ScreenText` comes back empty.
protocol ScreenTextIndex: AnyObject {
    var changes: ObservableObjectPublisher { get }
    var results: [UInt32: OcrWindowResult] { get }
    var isScanning: Bool { get }
    var enabled: Bool { get }
    var lastReviewedAt: Date? { get }

    func setEnabled(_ on: Bool)
    func scan()
    func scanSingle(wid: UInt32)
}

/// Core's view of screen text. Views observe `ScreenText.shared`; one-shot
/// recognition of a single image (capture analysis) is core and needs no index.
final class ScreenText: ObservableObject {
    static let shared = ScreenText()

    private(set) var index: ScreenTextIndex?
    private var forward: AnyCancellable?

    func install(_ index: ScreenTextIndex) {
        self.index = index
        forward = index.changes.sink { [weak self] in self?.objectWillChange.send() }
        objectWillChange.send()
    }

    var isAvailable: Bool { index != nil }
    var results: [UInt32: OcrWindowResult] { index?.results ?? [:] }
    var isScanning: Bool { index?.isScanning ?? false }
    var enabled: Bool { index?.enabled ?? false }
    var lastReviewedAt: Date? { index?.lastReviewedAt }

    func setEnabled(_ on: Bool) { index?.setEnabled(on) }
    func scan() { index?.scan() }
    func scanSingle(wid: UInt32) { index?.scanSingle(wid: wid) }

    // MARK: - Vision OCR

    static func recognize(in image: CGImage) -> [OcrTextBlock] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = Preferences.shared.ocrAccuracy == "fast" ? .fast : .accurate
        request.usesLanguageCorrection = true

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        return observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return OcrTextBlock(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: obs.boundingBox
            )
        }
    }
}
