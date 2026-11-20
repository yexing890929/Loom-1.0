#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
check(SelectionGridGeometry.dimensions == Array(stride(from: 4, through: 60, by: 4)), "menu dimensions increase by four through sixty")
check(SelectionGridGeometry.dimension(nil, default: 12) == 12 && SelectionGridGeometry.dimension(nil, default: 8) == 8, "new grids default to twelve columns and eight rows")
check(SelectionGridGeometry.dimension(9, default: 12) == 12 && SelectionGridGeometry.dimension(6, default: 8) == 8, "legacy unsupported dimensions migrate to new defaults")
check(SelectionGridGeometry.dimension(60, default: 12) == 60 && SelectionGridGeometry.dimension(28, default: 8) == 28, "valid saved choices above old maximum survive")
let bounds = CGRect(x: 20, y: 30, width: 1000, height: 600)
func select(_ a: CGPoint, _ b: CGPoint) -> CGRect? { SelectionGridGeometry.selection(from: a, to: b, in: bounds, columns: 10, rows: 6) }
check(select(CGPoint(x: 21, y: 31), CGPoint(x: 219, y: 229)) == CGRect(x: 20, y: 30, width: 200, height: 200), "drag snaps to touched cells")
check(select(CGPoint(x: 219, y: 229), CGPoint(x: 21, y: 31)) == select(CGPoint(x: 21, y: 31), CGPoint(x: 219, y: 229)), "reverse drag has same region")
check(select(CGPoint(x: 30, y: 40), CGPoint(x: 2000, y: 2000)) == bounds, "out-of-bounds drag clamps to available desktop")
check(select(CGPoint(x: 1020, y: 630), CGPoint(x: 1020, y: 630)) == CGRect(x: 920, y: 530, width: 100, height: 100), "far edge remains in last cell")
check(select(CGPoint(x: 250, y: 250), CGPoint(x: 251, y: 251)) == CGRect(x: 220, y: 230, width: 100, height: 100), "small drag selects one cell")
check(SelectionGridGeometry.selection(from: .zero, to: .zero, in: .zero, columns: 10, rows: 6) == nil, "empty screen safely rejected")
check(SelectionGridGeometry.selection(from: .zero, to: .zero, in: bounds, columns: 0, rows: 6) == nil, "invalid grid safely rejected")
let fractional = SelectionGridGeometry.selection(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 1000, y: 700), in: CGRect(x: 0, y: 0, width: 1001, height: 701), columns: 7, rows: 3)!
check(abs(fractional.width - 1001) < 0.001 && abs(fractional.height - 701) < 0.001, "fractional cells cover desktop precisely")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/SelectionGridGeometry.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
