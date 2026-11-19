#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
import CoreGraphics
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
check(PaletteGeometry.axPoint(CGPoint(x: -100, y: 1000), primaryTop: 900) == CGPoint(x: -100, y: -100), "AX hit point conversion above primary screen")
check(PaletteGeometry.cocoaFrame(CGRect(x: -100, y: -100, width: 14, height: 14), primaryTop: 900) == CGRect(x: -100, y: 986, width: 14, height: 14), "AX button frame conversion")
let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
check(PaletteGeometry.shiftedFrame(CGRect(x: 30, y: 700, width: 280, height: 60), in: screen, offset: 24) == CGRect(x: 54, y: 700, width: 280, height: 60), "popup moves right without changing height or vertical anchor")
check(PaletteGeometry.shiftedFrame(CGRect(x: 1150, y: 700, width: 280, height: 60), in: screen, offset: 24).maxX == 1436, "right shift remains within screen")
check(PaletteGeometry.shiftedFrame(CGRect(x: -1900, y: 700, width: 280, height: 60), in: CGRect(x: -1920, y: 0, width: 1920, height: 1080), offset: 24).minX == -1876, "right shift on a negative-coordinate display")

SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/PaletteGeometry.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
