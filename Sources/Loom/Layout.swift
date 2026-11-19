import Foundation
import CoreGraphics

enum Action: String, CaseIterable, Codable {
    case left, right, top, bottom, maximize, center, restore, nextDisplay, fullScreen
    static let fullScreenActions: [Action] = [.fullScreen]
    var isNativeFullScreen: Bool { Self.fullScreenActions.contains(self) }
    var title: String {
        switch self {
        case .left: return "左半屏"
        case .right: return "右半屏"
        case .top: return "上半屏"
        case .bottom: return "下半屏"
        case .maximize: return "最大化"
        case .center: return "居中"
        case .restore: return "还原"
        case .nextDisplay: return "移至下一显示器"
        case .fullScreen: return "整个屏幕"
        }
    }
}

// All geometry uses Accessibility coordinates: origin at the primary display's top left.
enum Layout {
    static func screenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        screens.indices.max { area(window.intersection(screens[$0])) < area(window.intersection(screens[$1])) }
    }
    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
    static func frame(_ action: Action, window: CGRect, visible: CGRect) -> CGRect {
        var result = visible
        switch action {
        case .left, .right: result.size.width /= 2
        case .top, .bottom: result.size.height /= 2
        case .center:
            return CGRect(x: visible.midX - window.width / 2, y: visible.midY - window.height / 2, width: window.width, height: window.height)
        default: break
        }
        if action == .right { result.origin.x = visible.maxX - result.width }
        if action == .bottom { result.origin.y = visible.maxY - result.height }
        return result
    }
    static func transfer(_ window: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return to }
        return CGRect(x: to.minX + (window.minX - from.minX) / from.width * to.width,
                      y: to.minY + (window.minY - from.minY) / from.height * to.height,
                      width: window.width / from.width * to.width, height: window.height / from.height * to.height)
    }
    static func fit(_ frame: CGRect, in visible: CGRect) -> CGRect {
        CGRect(x: min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width)),
               y: min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height)),
               width: frame.width, height: frame.height)
    }
}
