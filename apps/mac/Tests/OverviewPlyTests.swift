import AppKit
import SwiftUI
import XCTest
@testable import Lattices

@MainActor
final class OverviewPlyTests: XCTestCase {
    private let poses: [OverviewPlyPose] = [.idle, .pickUp, .carry, .wait, .setDown, .snapBack]

    /// Every pose renders at the tray and status-line sizes. Set
    /// LATTICES_PLY_RENDER_DIR to keep the PNGs for a look.
    func testEveryPoseRendersAtTraySizes() throws {
        let out = ProcessInfo.processInfo.environment["LATTICES_PLY_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        for height: CGFloat in [18, 24, 96] {
            for pose in poses {
                let renderer = ImageRenderer(content: OverviewPly(pose: pose, height: height)
                    .padding(4).background(Palette.bg))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage, "\(pose) at \(height)")
                XCTAssertEqual(CGFloat(image.height), (height + 8) * 2)
                if let out {
                    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                    try png?.write(to: out.appendingPathComponent("ply-\(Int(height))-\(pose).png"))
                }
            }
        }
    }
}
