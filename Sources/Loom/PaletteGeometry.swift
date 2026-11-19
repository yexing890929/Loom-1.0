import Foundation
import CoreGraphics

enum PaletteGeometry {
    static func shiftedFrame(_ frame: CGRect, in visible: CGRect, offset: CGFloat) -> CGRect {
        let minX = visible.minX + 4
        let maxX = max(minX, visible.maxX - frame.width - 4)
        var result = frame
        result.origin.x = min(max(frame.minX + offset, minX), maxX)
        return result
    }
    static func axPoint(_ point: CGPoint, primaryTop: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryTop - point.y)
    }
    static func cocoaFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
}
