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

let button = CGRect(x: 100, y: 850, width: 14, height: 14)
let native = CGRect(x: 60, y: 500, width: 250, height: 340)
check(PaletteGeometry.isCompetingPopup(frame: native, button: button, layer: 101, ownerPID: 2, ownPID: 1), "native popup below green button is detected")
check(!PaletteGeometry.isCompetingPopup(frame: native, button: button, layer: 101, ownerPID: 1, ownPID: 1), "Loom's own popup is excluded")
check(!PaletteGeometry.isCompetingPopup(frame: native, button: button, layer: 0, ownerPID: 2, ownPID: 1), "ordinary app window is excluded")
check(!PaletteGeometry.isCompetingPopup(frame: CGRect(x: 500, y: 500, width: 250, height: 340), button: button, layer: 101, ownerPID: 2, ownPID: 1), "unrelated distant popup is excluded")
check(!PaletteGeometry.isCompetingPopup(frame: CGRect(x: 90, y: 830, width: 90, height: 20), button: button, layer: 101, ownerPID: 2, ownPID: 1), "small tooltips are excluded")
check(PaletteGeometry.isCompetingPopup(frame: CGRect(x: 60, y: 880, width: 250, height: 100), button: button, layer: 101, ownerPID: 2, ownPID: 1), "popup flipped above the button is detected")
check(!PaletteGeometry.isCompetingPopup(frame: CGRect(x: 60, y: 300, width: 250, height: 100), button: button, layer: 101, ownerPID: 2, ownPID: 1), "vertically distant surface is excluded")

let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
let green = CGRect(x: 500, y: 850, width: 14, height: 14)
let bodySize = CGSize(width: 278, height: 50)
let centered = PaletteGeometry.chromePlacement(anchor: green, contentSize: bodySize, visible: screen, horizontalOffset: 0)
let shifted = PaletteGeometry.chromePlacement(anchor: green, contentSize: bodySize, visible: screen)
check(shifted.frame.minX - centered.frame.minX == 24, "body moves 24 points independently")
check(shifted.frame.minX + shifted.arrowTip.x == green.midX && centered.frame.minX + centered.arrowTip.x == green.midX, "arrow remains on the green button after shift")
check(shifted.pointsUp && shifted.frame.minY + shifted.arrowTip.y == green.minY - 3, "arrow points upward to green button")
check(shifted.bodyRect.size == bodySize && shifted.frame.height == bodySize.height + 10, "chrome preserves cropped content size")
let nearRight = PaletteGeometry.chromePlacement(anchor: CGRect(x: 1400, y: 850, width: 14, height: 14), contentSize: bodySize, visible: screen)
check(nearRight.frame.maxX <= screen.maxX - 6 && nearRight.frame.minX + nearRight.arrowTip.x == 1407, "right screen edge clamps body while preserving arrow")
let nearLeft = PaletteGeometry.chromePlacement(anchor: CGRect(x: 5, y: 850, width: 14, height: 14), contentSize: bodySize, visible: screen)
check(nearLeft.frame.minX >= 6 && nearLeft.frame.minX + nearLeft.arrowTip.x == 12, "extreme left edge preserves visible body and arrow target")
let above = PaletteGeometry.chromePlacement(anchor: CGRect(x: 500, y: 20, width: 14, height: 14), contentSize: bodySize, visible: screen)
check(!above.pointsUp && above.frame.minY + above.arrowTip.y == 37 && above.bodyRect.minY == 10, "bottom edge flips the arrow and body above the button")
let otherScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
let negative = PaletteGeometry.chromePlacement(anchor: CGRect(x: -1850, y: 850, width: 14, height: 14), contentSize: bodySize, visible: otherScreen)
check(otherScreen.contains(negative.frame) && negative.frame.minX + negative.arrowTip.x == -1843, "negative-coordinate display preserves arrow target")

SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/PaletteGeometry.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
