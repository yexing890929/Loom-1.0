import Foundation
import CoreGraphics

enum PaletteGeometry {
    static func iconSize(itemSize: CGFloat) -> CGSize {
        let width = min(max(itemSize, 30), 44) * 0.75
        return CGSize(width: width, height: width * 23 / 25)
    }
    static func axPoint(_ point: CGPoint, primaryTop: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryTop - point.y)
    }
    static func cocoaFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
}
