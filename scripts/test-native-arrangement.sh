#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
for (action, title) in [(Action.arrangeTwo, "左侧与右侧"), (.arrangeThree, "左侧与四等分"), (.arrangeFour, "四等分")] {
    check(NativeArrangementCommand.matches(title, names: NativeArrangementCommand.titles(for: action)), "observed Finder menu command: \(title)")
}
check(!NativeArrangementCommand.matches("左侧", names: NativeArrangementCommand.titles(for: .arrangeTwo)), "single-window half never substitutes for two-window arrangement")
check(!NativeArrangementCommand.matches("屏幕左侧", names: NativeArrangementCommand.titles(for: .arrangeTwo)), "Split View never substitutes for desktop arrangement")
check(!NativeArrangementCommand.matches("左上", names: NativeArrangementCommand.titles(for: .arrangeFour)), "single corner never substitutes for four-window arrangement")
check(NativeArrangementCommand.titles(for: .left).isEmpty, "non-native action has no native command")
check(NativeArrangementCommand.matches("Left & Quarters", names: NativeArrangementCommand.titles(for: .arrangeThree)), "English three-window command is recognized")
check(NativeArrangementCommand.matches("左側與右側", names: NativeArrangementCommand.titles(for: .arrangeTwo)), "traditional Chinese two-window command is recognized")
check(!NativeArrangementCommand.matches("Left & Right…", names: NativeArrangementCommand.titles(for: .arrangeTwo)), "unknown commands fail closed instead of fuzzy matching")
check(Action.allCases.prefix(9).map(\.rawValue) == ["left", "right", "top", "bottom", "maximize", "center", "restore", "nextDisplay", "fullScreen"], "existing Carbon action IDs remain stable")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/Layout.swift Sources/Loom/NativeArrangementCommand.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
