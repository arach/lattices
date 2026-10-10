import AppKit
import SwiftUI
import XCTest
@testable import Lattices

@MainActor
final class LongRenderTests: XCTestCase {
    func testDragThresholdAndReturnToOrigin() {
        var gesture = LongDragGesture()
        XCTAssertFalse(gesture.update(dx: 1, dy: 1))
        XCTAssertTrue(gesture.update(dx: 3, dy: 0))
        XCTAssertTrue(gesture.update(dx: 0, dy: 0))
        XCTAssertTrue(gesture.moved)
    }

    func testFlashIsReplacedByNewEvent() async throws {
        let model = DesktopLongModel()
        model.flash(.done, for: 0.01)
        model.flash(.oops, for: 0.1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.mood, .oops)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(model.mood, .rest)
    }

    func testOfflineMoods() throws {
        guard let dir = ProcessInfo.processInfo.environment["LONG_RENDER_DIR"] else { throw XCTSkip("Opt-in offline render") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let moods: [(String, Long.Mood)] = [("rest", .rest), ("listen", .listen), ("work", .work), ("oops", .oops), ("away", .away), ("talk", .talk)]
        let view = VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { light in
                HStack(alignment: .bottom, spacing: 20) {
                    ForEach(moods, id: \.0) { label, mood in
                        VStack(spacing: 12) {
                            Long(mood: mood, size: 100, speechLevel: mood == .talk ? 0.8 : 0)
                            Long(mood: mood, size: 44, speechLevel: mood == .talk ? 0.8 : 0)
                            Text(label).font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
                .padding(24)
                .foregroundStyle(light ? Long.ink : Long.lit)
                .background(light ? Color(white: 0.92) : Color(white: 0.08))
            }
        }
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("long-moods.png"))

        let comparison = VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { light in
                HStack(spacing: 36) {
                    ForEach(Long.Depth.allCases, id: \.rawValue) { depth in
                        VStack(spacing: 16) {
                            Long(size: 140, depth: depth)
                            Long(size: 44, depth: depth)
                            Text(depth.rawValue + (depth == .soft ? " · selected" : ""))
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
                .padding(28)
                .foregroundStyle(light ? Long.ink : Long.lit)
                .background(light ? Color(white: 0.92) : Color(white: 0.08))
            }
        }
        let depthRenderer = ImageRenderer(content: comparison)
        depthRenderer.scale = 2
        let depthImage = try XCTUnwrap(depthRenderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: depthImage).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("long-depth-comparison.png"))

        let card = LongCardModel()
        card.visit = .init(armed: false, visiting: "Mini", hosts: [
            .init(name: "Mini", address: "example.invalid:1", side: .right,
                  bridgePublicKey: "", bridgeFingerprint: "", capabilities: [], pairedAt: .distantPast),
            .init(name: "Studio", address: "example.invalid:2", side: .left,
                  bridgePublicKey: "", bridgeFingerprint: "", capabilities: [], pairedAt: .distantPast),
        ], ready: true)
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
