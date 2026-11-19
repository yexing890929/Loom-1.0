import Foundation
import CoreGraphics

struct PaletteLayout: Equatable {
    static let columns = 10
    static let rows = 6
    static let count = columns * rows
    static let actions: [Action] = [.maximize, .left, .right, .top, .bottom, .center, .restore]
    private(set) var cells: [Action?]

    static var standard: Self {
        var cells = [Action?](repeating: nil, count: count)
        for (offset, action) in actions.enumerated() { cells[2 * columns + 1 + offset] = action }
        return Self(cells: cells)
    }
    private init(cells: [Action?]) { self.cells = cells }
    init(data: Data?) {
        guard let data, let raw = try? JSONDecoder().decode([String?].self, from: data), raw.count == Self.count else {
            self = .standard; return
        }
        var seen = Set<Action>()
        cells = raw.map { name in
            guard let name, let action = Action(rawValue: name), Self.actions.contains(action), seen.insert(action).inserted else { return nil }
            return action
        }
        for action in Self.actions where !seen.contains(action) {
            if let empty = cells.firstIndex(where: { $0 == nil }) { cells[empty] = action }
        }
    }
    var data: Data? { try? JSONEncoder().encode(cells.map { $0?.rawValue }) }
    @discardableResult mutating func move(_ action: Action, to destination: Int) -> Bool {
        guard cells.indices.contains(destination), let source = cells.firstIndex(of: action), source != destination else { return false }
        cells.swapAt(source, destination)
        return true
    }
    func size(itemSize: CGFloat) -> CGSize {
        CGSize(width: CGFloat(Self.columns) * itemSize + CGFloat(Self.columns - 1) * 4,
               height: CGFloat(Self.rows) * itemSize + CGFloat(Self.rows - 1) * 4)
    }
}
