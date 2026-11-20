import Foundation
import CoreGraphics

enum SelectionGridGeometry {
    static let dimensions = Array(stride(from: 4, through: 60, by: 4))
    static func dimension(_ stored: Int?, default fallback: Int) -> Int {
        guard let stored, dimensions.contains(stored) else { return fallback }
        return stored
    }
    // Coordinates are local to a flipped overlay view. Edges snap outward to
    // the cells touched by a drag, regardless of drag direction.
    static func selection(from start: CGPoint, to end: CGPoint, in bounds: CGRect, columns: Int, rows: Int) -> CGRect? {
        guard bounds.width > 0, bounds.height > 0, columns > 0, rows > 0 else { return nil }
        let width = bounds.width / CGFloat(columns)
        let height = bounds.height / CGFloat(rows)
        func cell(_ value: CGFloat, origin: CGFloat, size: CGFloat, count: Int) -> Int {
            min(count - 1, max(0, Int(floor((value - origin) / size))))
        }
        let a = cell(start.x, origin: bounds.minX, size: width, count: columns)
        let b = cell(end.x, origin: bounds.minX, size: width, count: columns)
        let c = cell(start.y, origin: bounds.minY, size: height, count: rows)
        let d = cell(end.y, origin: bounds.minY, size: height, count: rows)
        return CGRect(x: bounds.minX + CGFloat(min(a, b)) * width,
                      y: bounds.minY + CGFloat(min(c, d)) * height,
                      width: CGFloat(abs(a - b) + 1) * width,
                      height: CGFloat(abs(c - d) + 1) * height)
    }
}
