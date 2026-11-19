#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
import CoreGraphics
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
let anchor = CGRect(x: 30, y: 850, width: 14, height: 14)
// Placement is handled by NSPopover. Exercise pointer travel against a sample
// system popover frame rather than maintaining a second placement algorithm.
let panel = CGRect(x: 30, y: 794, width: 278, height: 50)
check(PaletteGeometry.axPoint(CGPoint(x: -100, y: 1000), primaryTop: 900) == CGPoint(x: -100, y: -100), "AX hit point conversion above primary screen")
check(PaletteGeometry.cocoaFrame(CGRect(x: -100, y: -100, width: 14, height: 14), primaryTop: 900) == CGRect(x: -100, y: 986, width: 14, height: 14), "AX button frame conversion")
check(PaletteGeometry.containsPointer(CGPoint(x: 35, y: 847), anchor: anchor, panel: panel), "crossing the gap keeps panel open")
check(PaletteGeometry.containsPointer(CGPoint(x: 280, y: 815), anchor: anchor, panel: panel), "pointer can reach final layout button")
check(!PaletteGeometry.containsPointer(CGPoint(x: 500, y: 800), anchor: anchor, panel: panel), "outside pointer dismisses panel")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/PaletteGeometry.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
