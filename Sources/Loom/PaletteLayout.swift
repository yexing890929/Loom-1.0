import Foundation
import CoreGraphics

struct PaletteLayout: Equatable {
    static let columns = 10
    static let rows = 6
    static let count = columns * rows
    static let actions: [Action] = [.maximize, .left, .right, .top, .bottom, .center, .restore] + Action.arrangementActions
    private(set) var cells: [Action?]
    private(set) var hidden = Set<Action>()
    private struct Stored: Codable {
        let cells: [String?]
        let hidden: [String]
    }

    static var standard: Self {
        var cells = [Action?](repeating: nil, count: count)
        let first: [Action] = [.maximize, .left, .right, .top, .bottom]
        let second: [Action] = [.center, .arrangeTwo, .arrangeThree, .arrangeFour, .restore]
        for (offset, action) in first.enumerated() { cells[2 * columns + 2 + offset] = action }
        for (offset, action) in second.enumerated() { cells[3 * columns + 2 + offset] = action }
        return Self(cells: cells)
    }
    private init(cells: [Action?]) { self.cells = cells }
    init(data: Data?) {
        guard let data else { self = .standard; return }
        let stored = try? JSONDecoder().decode(Stored.self, from: data)
        guard let raw = stored?.cells ?? (try? JSONDecoder().decode([String?].self, from: data)), raw.count == Self.count else {
            self = .standard; return
        }
        var seen = Set<Action>()
        cells = raw.map { name in
            guard let name, let action = Action(rawValue: name), Self.actions.contains(action), seen.insert(action).inserted else { return nil }
            return action
        }
        for action in Self.actions where !seen.contains(action) {
            let preferred = Self.standard.cells.firstIndex(of: action)
            if let preferred {
                // A custom layout may occupy the default destination. Keep new
                // presets nearby instead of expanding the popup to the top-left.
                let free = cells.indices.filter { cells[$0] == nil }.min { a, b in
                    func distance(_ index: Int) -> Int {
                        abs(index / Self.columns - preferred / Self.columns) * Self.columns
                        + abs(index % Self.columns - preferred % Self.columns)
                    }
                    return distance(a) == distance(b) ? a > b : distance(a) < distance(b)
                }
                if let free { cells[free] = action }
            }
        }
        hidden = Set((stored?.hidden ?? []).compactMap(Action.init(rawValue:))).intersection(Self.actions)
    }
    var data: Data? { try? JSONEncoder().encode(Stored(cells: cells.map { $0?.rawValue }, hidden: hidden.map(\.rawValue).sorted())) }
    var hasVisibleActions: Bool { cells.compactMap { $0 }.contains { !hidden.contains($0) } }
    func visibleAction(at index: Int) -> Action? {
        guard cells.indices.contains(index), let action = cells[index], !hidden.contains(action) else { return nil }
        return action
    }
    mutating func toggleVisibility(_ action: Action) {
        guard Self.actions.contains(action) else { return }
        if !hidden.insert(action).inserted { hidden.remove(action) }
    }
    @discardableResult mutating func move(_ action: Action, to destination: Int) -> Bool {
        guard cells.indices.contains(destination), let source = cells.firstIndex(of: action), source != destination else { return false }
        cells.swapAt(source, destination)
        return true
    }
    struct VisibleBounds: Equatable {
        let rows: ClosedRange<Int>
        let columns: ClosedRange<Int>
        func size(itemSize: CGFloat) -> CGSize {
            CGSize(width: CGFloat(columns.count) * itemSize + CGFloat(columns.count - 1) * 4,
                   height: CGFloat(rows.count) * itemSize + CGFloat(rows.count - 1) * 4)
        }
    }
    var visibleBounds: VisibleBounds {
        let occupied = cells.indices.filter { visibleAction(at: $0) != nil }
        let rows = occupied.map { $0 / Self.columns }
        let columns = occupied.map { $0 % Self.columns }
        return VisibleBounds(rows: (rows.min() ?? 0)...(rows.max() ?? 0),
                             columns: (columns.min() ?? 0)...(columns.max() ?? 0))
    }
    func size(itemSize: CGFloat) -> CGSize {
        CGSize(width: CGFloat(Self.columns) * itemSize + CGFloat(Self.columns - 1) * 4,
               height: CGFloat(Self.rows) * itemSize + CGFloat(Self.rows - 1) * 4)
    }
}
