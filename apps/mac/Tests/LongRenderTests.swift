import AppKit
import SwiftUI
import XCTest
@testable import Lattices

@MainActor
final class LongRenderTests: XCTestCase {
    func testOfflineMoods() throws {
        guard let dir = ProcessInfo.processInfo.environment["LONG_RENDER_DIR"] else { throw XCTSkip("Opt-in offline render") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let moods: [(String, Long.Mood)] = [("rest", .rest), ("listen", .listen), ("work", .work), ("oops", .oops), ("away", .away), ("talk", .talk)]
        let view = HStack(spacing: 16) {
            ForEach(moods, id: \.0) { Long(mood: $0.1, size: 120) }
            DesktopLongView(model: DesktopLongModel())
        }
        .padding(20)
        .background(Color(white: 0.12))
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("long-moods.png"))

        let card = LongCardModel()
        card.layers = ["Lattices", "Scout", "Talkie", "Fab", "Web", "Notes", "Music", "Mail"]
        card.activeLayer = 1
        card.screens = [
            .init(index: 0, id: "1", name: "DELL S3422DWG", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440), visible: .zero, isMain: true),
            .init(index: 1, id: "2", name: "U32J59x", frame: CGRect(x: -3840, y: -396, width: 3840, height: 2160), visible: .zero, isMain: false),
        ]
        let cardImage = try XCTUnwrap(ImageRenderer(content: LongCardView(model: card).padding(20).background(Color(white: 0.2))).cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: cardImage).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("long-card.png"))
    }
}
