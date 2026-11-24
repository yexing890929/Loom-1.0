import Foundation

// Only detect a partially completed two-window arrangement. System tiling
// margins are allowed; no custom frames are applied to native participants.
enum NativeArrangementGeometry {
    static func matches(_ actual: CGRect, _ expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) <= 20 && abs(actual.minY - expected.minY) <= 20 &&
        abs(actual.maxX - expected.maxX) <= 20 && abs(actual.maxY - expected.maxY) <= 20
    }
    static func needsCompletion(_ action: Action, primary: CGRect, companion: CGRect, visible: CGRect) -> Bool {
        guard action == .arrangeTwo || action == .arrangeTwoVertical else { return false }
        let horizontal = action == .arrangeTwo
        let first = Layout.frame(horizontal ? .left : .top, window: primary, visible: visible)
        let second = Layout.frame(horizontal ? .right : .bottom, window: companion, visible: visible)
        // Do not retry an unsupported layout, an unrelated window, or a pair
        // already at the native positions (with or without tiling margins).
        guard matches(primary, first), !matches(companion, second),
              companion.intersects(second), companion.width >= 100, companion.height >= 100 else { return false }
        return true
    }
}
