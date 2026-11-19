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
let small = PaletteGeometry.iconSize(itemSize: 30)
let large = PaletteGeometry.iconSize(itemSize: 44)
check(large.width > small.width * 1.4 && large.height > small.height * 1.4, "largest icons visibly scale up from smallest")
check(abs(small.width / small.height - large.width / large.height) < 0.0001, "icon scaling preserves aspect ratio")
check(small.width < 30 && small.height < 30 && large.width < 44 && large.height < 44, "scaled icons remain within button bounds")
check(PaletteGeometry.iconSize(itemSize: 100) == large && PaletteGeometry.iconSize(itemSize: 1) == small, "out-of-range icon sizes clamp safely")

SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/PaletteGeometry.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
