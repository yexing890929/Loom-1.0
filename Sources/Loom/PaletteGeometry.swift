import Foundation
import CoreGraphics

enum PaletteGeometry {
    static func isCompetingPopup(frame: CGRect, button: CGRect, layer: Int, ownerPID: Int, ownPID: Int) -> Bool {
        guard ownerPID != ownPID, layer > 0, frame.width >= 70, frame.height >= 40 else { return false }
        // A native popup is a raised surface immediately below (or above, near
        // a screen edge) the traffic light, not the normal layer-zero app window.
        let nearX = frame.minX <= button.midX + 32 && frame.maxX >= button.midX - 32
        let below = abs(frame.maxY - button.minY) <= 40
        let above = abs(frame.minY - button.maxY) <= 40
        return nearX && (below || above)
    }

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
