import Foundation

// Exact, scoped menu names: never substitute a single-window tile or Split View.
enum NativeArrangementCommand {
    static let windowMenu = ["Window", "窗口", "視窗"]
    static let moveAndResize = ["Move & Resize", "移动与调整大小", "移動與調整大小"]
    static func titles(for action: Action) -> [String] {
        switch action {
        case .arrangeTwo: return ["Left & Right", "左侧与右侧", "左側與右側"]
        case .arrangeThree: return ["Left & Quarters", "左侧与四等分", "左側與四等分"]
        case .arrangeFour: return ["Quarters", "四等分"]
        default: return []
        }
    }
    static func matches(_ title: String, names: [String]) -> Bool {
        names.contains(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
