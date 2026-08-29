import AppKit
import Foundation
import Vision

public struct ActionOCRFrame: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public struct ActionOCRTextBlock: Codable, Sendable {
    public let text: String
    public let confidence: Double
    public let frame: ActionOCRFrame
}

public struct ActionOCRResult: Codable, Sendable {
    public let imagePath: String
    public let imageWidth: Double
    public let imageHeight: Double
    public let blockCount: Int
    public let fullText: String
    public let blocks: [ActionOCRTextBlock]
}

public enum ActionVisionOCRError: LocalizedError {
    case imageNotFound(String)
    case unableToLoadImage(String)
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .imageNotFound(let path):
            return "Image not found: \(path)"
        case .unableToLoadImage(let path):
            return "Unable to load image: \(path)"
        case .recognitionFailed(let detail):
            return "OCR failed: \(detail)"
        }
    }
}

public func actionRecognizeText(in imagePath: String) throws -> ActionOCRResult {
    let path = (imagePath as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ActionVisionOCRError.imageNotFound(path)
    }

    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw ActionVisionOCRError.unableToLoadImage(path)
    }

    let imageWidth = Double(cgImage.width)
    let imageHeight = Double(cgImage.height)

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        throw ActionVisionOCRError.recognitionFailed(error.localizedDescription)
    }

    let observations = request.results ?? []
    var blocks: [ActionOCRTextBlock] = []

    for observation in observations {
        guard let candidate = observation.topCandidates(1).first else {
            continue
        }

        let box = observation.boundingBox
        blocks.append(
            ActionOCRTextBlock(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                frame: ActionOCRFrame(
                    x: box.minX * imageWidth,
                    y: (1.0 - box.maxY) * imageHeight,
                    width: box.width * imageWidth,
                    height: box.height * imageHeight
                )
            )
        )
    }

    blocks.sort {
        if abs($0.frame.y - $1.frame.y) > 4 {
            return $0.frame.y < $1.frame.y
        }
        return $0.frame.x < $1.frame.x
    }

    let fullText = blocks.map(\.text).joined(separator: "\n")

    return ActionOCRResult(
        imagePath: path,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        blockCount: blocks.count,
        fullText: fullText,
        blocks: blocks
    )
}