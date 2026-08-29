import SwiftUI

/// Continuous rounded rectangle used across Action surfaces.
///
/// The type name is historical (`ActionChamferedShape`); the path is a standard
/// continuous corner radius so call sites stay stable while the visual system
/// drops cut corners.
struct ActionChamferedShape: InsettableShape {
    /// Corner radius. Named `cornerCut` for call-site compatibility.
    var cornerCut: CGFloat = 10
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, min(cornerCut, min(insetRect.width, insetRect.height) / 2))
        return Path(roundedRect: insetRect, cornerRadius: radius, style: .continuous)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
