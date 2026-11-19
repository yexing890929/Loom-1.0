#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
check(Layout.frame(.top, window: .zero, visible: screen) == CGRect(x: 0, y: 25, width: 1440, height: 437.5), "top half")
check(Layout.frame(.bottom, window: .zero, visible: screen) == CGRect(x: 0, y: 462.5, width: 1440, height: 437.5), "bottom half")
check(Layout.frame(.left, window: .zero, visible: screen) == CGRect(x: 0, y: 25, width: 720, height: 875), "half screen respects reserved area")
check(Layout.frame(.right, window: .zero, visible: screen) == CGRect(x: 720, y: 25, width: 720, height: 875), "right half")
check(Layout.frame(.center, window: CGRect(x: 0, y: 0, width: 400, height: 300), visible: screen) == CGRect(x: 520, y: 312.5, width: 400, height: 300), "center preserves size")
check(Layout.screenIndex(for: CGRect(x: -100, y: 100, width: 600, height: 500), screens: [CGRect(x: -1920, y: -200, width: 1920, height: 1080), screen]) == 1, "largest overlap")
check(Layout.screenIndex(for: screen, screens: []) == nil, "no displays")
check(Layout.transfer(CGRect(x: 640, y: 0, width: 640, height: 350), from: CGRect(x: 0, y: 0, width: 1280, height: 700), to: CGRect(x: -2560, y: -300, width: 2560, height: 1400)) == CGRect(x: -1280, y: -300, width: 1280, height: 700), "proportional display transfer")
check(Layout.fit(CGRect(x: -2000, y: -100, width: 600, height: 400), in: screen).origin == screen.origin, "disconnected display recovery")
check(Layout.fit(CGRect(x: 800, y: 700, width: 2000, height: 1200), in: screen) == CGRect(x: 0, y: 25, width: 2000, height: 1200), "oversized minimum window remains reachable")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/Layout.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
