import Foundation
import CoreGraphics

enum PaletteGeometry {
    static func axPoint(_ point: CGPoint, primaryTop: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryTop - point.y)
    }
    static func cocoaFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
    static func containsPointer(_ point: CGPoint, anchor: CGRect, panel: CGRect) -> Bool {
        if anchor.insetBy(dx: -4, dy: -4).contains(point) || panel.insetBy(dx: -4, dy: -4).contains(point) { return true }
        // A narrow travel corridor between the green button and the panel.
        let gap = CGRect(x: anchor.minX - 4, y: min(anchor.minY, panel.maxY), width: anchor.width + 8,
                         height: abs(anchor.minY - panel.maxY))
        return gap.contains(point)
    }
}
