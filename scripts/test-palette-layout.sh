#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
import CoreGraphics
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
var layout = PaletteLayout.standard
check(layout.cells.count == 60 && PaletteLayout.columns == 10 && PaletteLayout.rows == 6, "10 by 6 grid")
let origin = layout.cells.firstIndex(of: .maximize)!
check(layout.move(.maximize, to: 0) && layout.cells[0] == .maximize && layout.cells[origin] == nil, "move to empty cell clears source")
let right = layout.cells.firstIndex(of: .right)!
check(layout.move(.maximize, to: right) && layout.cells[right] == .maximize && layout.cells[0] == .right, "occupied drop swaps actions")
check(Set(layout.cells.compactMap { $0 }) == Set(PaletteLayout.actions) && layout.cells.compactMap { $0 }.count == PaletteLayout.actions.count, "all actions retained exactly once")
check(!layout.move(.maximize, to: right), "same-cell move is no-op")
let before = layout
check(!layout.move(.left, to: -1) && !layout.move(.left, to: 60) && layout == before, "out-of-range drops rejected")
check(!layout.move(.fullScreen, to: 0) && layout == before, "unsupported action cannot be introduced")
check(PaletteLayout(data: layout.data) == layout, "layout persists and round trips")
check(PaletteLayout(data: Data("bad json".utf8)) == .standard, "corrupt storage defaults safely")
check(PaletteLayout(data: try! JSONEncoder().encode([String?](repeating: nil, count: 59))) == .standard, "wrong grid size rejected")
var raw = [String?](repeating: nil, count: 60)
raw[1] = "left"; raw[2] = "left"; raw[3] = "removedAction"
let repaired = PaletteLayout(data: try! JSONEncoder().encode(raw))
check(repaired.cells[1] == .left && repaired.cells.compactMap { $0 }.count == PaletteLayout.actions.count && Set(repaired.cells.compactMap { $0 }) == Set(PaletteLayout.actions), "duplicates and missing actions repaired")
check(PaletteLayout.standard.size(itemSize: 34) == CGSize(width: 376, height: 224), "grid size matches ten columns and six rows")
check(layout.move(.left, to: 59) && layout.cells[59] == .left, "last grid cell is reachable")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/Layout.swift Sources/Loom/PaletteLayout.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
