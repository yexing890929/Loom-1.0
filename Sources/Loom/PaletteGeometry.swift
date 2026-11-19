import Foundation
import CoreGraphics

enum PaletteGeometry {
    struct ChromePlacement {
        let frame: CGRect
        let bodyRect: CGRect
        let arrowTip: CGPoint
        let pointsUp: Bool
    }
    static func chromePlacement(anchor: CGRect, contentSize: CGSize, visible: CGRect, horizontalOffset: CGFloat = 24) -> ChromePlacement {
        let radius: CGFloat = 12
        let arrowHeight: CGFloat = 10
        let arrowHalfWidth: CGFloat = 11
        let margin: CGFloat = 6
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - contentSize.width - margin)
        let standardX = min(max(anchor.midX - contentSize.width / 2, minX), maxX)
        var x = min(max(standardX + horizontalOffset, minX), maxX)
        // Keep the arrow out of the rounded corners, without moving its screen tip.
        let arrowInset = radius + arrowHalfWidth
        x = min(x, anchor.midX - arrowInset)
        x = max(x, anchor.midX - contentSize.width + arrowInset)
        x = min(max(x, minX), maxX)
        let belowTipY = anchor.minY - 3
        let belowY = belowTipY - arrowHeight - contentSize.height
        let pointsUp = belowY >= visible.minY + margin
        let y = pointsUp ? belowY : anchor.maxY + 3
        return ChromePlacement(frame: CGRect(x: x, y: y, width: contentSize.width, height: contentSize.height + arrowHeight),
                               bodyRect: CGRect(x: 0, y: pointsUp ? 0 : arrowHeight, width: contentSize.width, height: contentSize.height),
                               arrowTip: CGPoint(x: anchor.midX - x, y: pointsUp ? contentSize.height + arrowHeight : 0),
                               pointsUp: pointsUp)
    }
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
