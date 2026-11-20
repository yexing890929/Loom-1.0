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
let standard = PaletteLayout.standard
check(standard.visibleBounds.rows == 2...3 && standard.visibleBounds.columns == 2...7, "default palette crops surrounding empty rows and columns")
check(Array(standard.cells[22...27]) == [.maximize, .left, .right, .top, .bottom, .center] && Array(standard.cells[32...37]) == [.gridSelection, .arrangeTwo, .arrangeTwoVertical, .arrangeThree, .arrangeFour, .restore], "vertical preset is next to horizontal preset in the default layout")
check(standard.visibleBounds.size(itemSize: 34) == CGSize(width: 224, height: 72), "default popup includes manual grid action")
var sparse = PaletteLayout.standard
sparse.move(.restore, to: 49)
check(sparse.visibleBounds.rows == 2...4 && sparse.visibleBounds.columns == 2...9, "sparse layout retains internal empty row and columns")
check(sparse.visibleBounds.size(itemSize: 34) == CGSize(width: 300, height: 110), "popup size uses occupied bounding box with internal gaps")
var shifted = PaletteLayout.standard
for action in PaletteLayout.actions.reversed() { shifted.move(action, to: standard.cells.firstIndex(of: action)! + 22) }
check(shifted.visibleBounds.rows == 4...5 && shifted.visibleBounds.columns == 4...9 && shifted.visibleBounds.size(itemSize: 34) == standard.visibleBounds.size(itemSize: 34), "translated icons retain same popup size")
var extremes = PaletteLayout.standard
extremes.move(.maximize, to: 0); extremes.move(.restore, to: 59)
check(extremes.visibleBounds.size(itemSize: 34) == extremes.size(itemSize: 34), "opposite-corner icons require full grid bounds")
check(PaletteLayout(data: sparse.data).visibleBounds == sparse.visibleBounds, "cropping is preserved after reload")
var hidden = PaletteLayout.standard
hidden.toggleVisibility(.left)
check(hidden.cells.contains(.left) && hidden.visibleAction(at: 23) == nil && hidden.visibleBounds == standard.visibleBounds, "hidden interior action retains its editor position and popup hole")
hidden.toggleVisibility(.maximize)
hidden.toggleVisibility(.center)
hidden.toggleVisibility(.gridSelection)
check(hidden.visibleBounds.columns == 3...7, "empty edge columns crop after hiding")
check(PaletteLayout(data: hidden.data) == hidden, "hidden actions and positions persist together")
hidden.move(.left, to: 59)
check(hidden.hidden.contains(.left) && hidden.visibleBounds.rows == 2...3, "dragging a hidden icon preserves visibility without expanding popup")
hidden.toggleVisibility(.left)
check(hidden.visibleAction(at: 59) == .left && hidden.visibleBounds.columns.upperBound == 9, "showing an icon restores it at its current location")
for action in PaletteLayout.actions where !hidden.hidden.contains(action) { hidden.toggleVisibility(action) }
check(!hidden.hasVisibleActions && PaletteLayout(data: hidden.data) == hidden, "all hidden configuration persists and disables popup")
let legacy = try! JSONEncoder().encode(standard.cells.map { $0?.rawValue })
check(PaletteLayout(data: legacy) == standard, "legacy array storage migrates without moving icons")
hidden.toggleVisibility(.fullScreen)
check(!hidden.hidden.contains(.fullScreen), "unsupported actions cannot be hidden")
var oldCells = [String?](repeating: nil, count: 60)
for (offset, action) in PaletteLayout.actions.prefix(7).enumerated() { oldCells[21 + offset] = action.rawValue }
oldCells.swapAt(21, 49)
let migrated = PaletteLayout(data: try! JSONEncoder().encode(oldCells))
check(migrated.cells[49] == .maximize && migrated.cells[22] == .left && migrated.cells[33] == .arrangeTwo && migrated.cells[34] == .arrangeTwoVertical && migrated.cells[35] == .arrangeThree && migrated.cells[36] == .arrangeFour, "seven-action storage gains native presets without moving existing icons")
let object: [String: Any] = ["cells": oldCells.map { $0 as Any? ?? NSNull() }, "hidden": ["left"]]
let storedMigration = PaletteLayout(data: try! JSONSerialization.data(withJSONObject: object))
check(storedMigration.hidden.contains(.left) && storedMigration.cells.contains(.arrangeFour), "migration preserves hidden actions")
var custom = [String?](repeating: nil, count: 60)
for (index, action) in zip([23, 24, 25, 26, 33, 34, 35], PaletteLayout.actions.prefix(7)) { custom[index] = action.rawValue }
let crowded = PaletteLayout(data: try! JSONEncoder().encode(custom))
check(crowded.cells[38] == .arrangeFour && crowded.visibleBounds.rows == 2...3 && crowded.cells[33] == .bottom, "occupied preset destinations choose nearby free cells without moving custom icons")
var previous = standard.cells.map { $0?.rawValue }
previous[27] = nil
previous[32] = Action.center.rawValue
previous[34] = Action.arrangeThree.rawValue
previous[35] = Action.arrangeFour.rawValue
previous[36] = Action.restore.rawValue
previous[37] = nil
let previousObject: [String: Any] = ["cells": previous.map { $0 as Any? ?? NSNull() }, "hidden": ["arrangeTwo"]]
let upgraded = PaletteLayout(data: try! JSONSerialization.data(withJSONObject: previousObject))
check(upgraded.cells[33] == .arrangeTwo && upgraded.cells[34] == .arrangeThree && upgraded.cells[35] == .arrangeFour && upgraded.cells[36] == .restore && upgraded.cells[37] == .arrangeTwoVertical, "ten-action layout keeps positions when adding vertical preset")
check(upgraded.hidden.contains(.arrangeTwo) && !upgraded.hidden.contains(.arrangeTwoVertical) && PaletteLayout(data: upgraded.data) == upgraded, "horizontal hidden state survives and new vertical preset persists")
var verticalHidden = upgraded
verticalHidden.toggleVisibility(.arrangeTwoVertical)
check(verticalHidden.visibleAction(at: 37) == nil && verticalHidden.visibleBounds.columns == 1...6, "hiding vertical preset crops the now-empty edge column")

check(standard.cells[32] == .gridSelection, "manual grid has a default palette position")
var oldManual = standard.cells.map { $0 == .gridSelection ? nil : $0?.rawValue }
let manualUpgrade = PaletteLayout(data: try! JSONEncoder().encode(oldManual))
check(manualUpgrade.cells[32] == .gridSelection && manualUpgrade.cells[33] == .arrangeTwo, "manual action migrates without moving existing icons")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/Layout.swift Sources/Loom/PaletteLayout.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
