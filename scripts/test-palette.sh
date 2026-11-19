#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
import CoreGraphics
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
let display = CGRect(x: 0, y: 0, width: 1440, height: 875)
let size = CGSize(width: 278, height: 50)
let anchor = CGRect(x: 30, y: 850, width: 14, height: 14)
let panel = PaletteGeometry.panelFrame(anchor: anchor, size: size, visible: display)
check(panel == CGRect(x: 30, y: 794, width: 278, height: 50), "normal panel appears below green button")
let edge = PaletteGeometry.panelFrame(anchor: CGRect(x: 1400, y: 850, width: 14, height: 14), size: size, visible: display)
check(edge.maxX == display.maxX - 6, "right edge stays on screen")
let bottom = PaletteGeometry.panelFrame(anchor: CGRect(x: 30, y: 20, width: 14, height: 14), size: size, visible: display)
check(bottom.minY == 40, "bottom edge opens above")
let second = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
let negative = PaletteGeometry.panelFrame(anchor: CGRect(x: -1918, y: 700, width: 14, height: 14), size: size, visible: second)
check(negative.minX == second.minX + 6 && second.contains(negative), "negative-coordinate display")
check(PaletteGeometry.axPoint(CGPoint(x: -100, y: 1000), primaryTop: 900) == CGPoint(x: -100, y: -100), "AX hit point conversion above primary screen")
check(PaletteGeometry.cocoaFrame(CGRect(x: -100, y: -100, width: 14, height: 14), primaryTop: 900) == CGRect(x: -100, y: 986, width: 14, height: 14), "AX button frame conversion")
check(PaletteGeometry.containsPointer(CGPoint(x: 35, y: 847), anchor: anchor, panel: panel), "crossing the gap keeps panel open")
check(PaletteGeometry.containsPointer(CGPoint(x: 280, y: 815), anchor: anchor, panel: panel), "pointer can reach final layout button")
check(!PaletteGeometry.containsPointer(CGPoint(x: 500, y: 800), anchor: anchor, panel: panel), "outside pointer dismisses panel")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/PaletteGeometry.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
