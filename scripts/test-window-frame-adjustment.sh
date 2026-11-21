#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: \(name)") }
let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
var frame = CGRect(x: 400, y: 200, width: 600, height: 400)
var sizes = 0
func apply(_ desired: CGRect, resize: Bool = true, minimum: CGSize = .zero) {
    WindowFrameAdjustment.apply(desired, in: screen, resize: resize, read: { frame }, setSize: { size in
        sizes += 1
        frame.size = CGSize(width: max(minimum.width, min(size.width, screen.maxX - frame.minX)),
                            height: max(minimum.height, min(size.height, screen.maxY - frame.minY)))
    }, setPosition: { frame.origin = $0 })
}
// A grid-positioned window whose app refuses to grow past the display edge.
apply(screen)
check(frame == screen, "maximize after grid selection fills available screen")
check(sizes == 2, "retry resize after moving from interior grid cell")
sizes = 0
apply(screen)
check(sizes == 1, "accepted resize needs no retry")
let restored = CGRect(x: 250, y: 160, width: 700, height: 500)
apply(restored)
check(frame == restored, "restore preserves requested frame")
sizes = 0
apply(Layout.frame(.center, window: frame, visible: screen), resize: false)
check(frame.size == restored.size && sizes == 0, "center never resizes")
apply(CGRect(x: 1300, y: 700, width: 100, height: 100), minimum: CGSize(width: 400, height: 300))
check(frame == CGRect(x: 1040, y: 600, width: 400, height: 300), "minimum size remains on screen")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/Layout.swift Sources/Loom/WindowFrameAdjustment.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
