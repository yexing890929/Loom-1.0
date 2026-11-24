#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
for (action, title) in [(Action.arrangeTwo, "左侧与右侧"), (.arrangeTwoVertical, "顶部与底部"), (.arrangeThree, "左侧与四等分"), (.arrangeFour, "四等分")] {
    check(NativeArrangementCommand.matches(title, names: NativeArrangementCommand.titles(for: action)), "observed Finder menu command: \(title)")
}
check(!NativeArrangementCommand.matches("左侧", names: NativeArrangementCommand.titles(for: .arrangeTwo)), "single-window half never substitutes for two-window arrangement")
check(!NativeArrangementCommand.matches("屏幕左侧", names: NativeArrangementCommand.titles(for: .arrangeTwo)), "Split View never substitutes for desktop arrangement")
check(!NativeArrangementCommand.matches("左上", names: NativeArrangementCommand.titles(for: .arrangeFour)), "single corner never substitutes for four-window arrangement")
check(NativeArrangementCommand.titles(for: .left).isEmpty, "non-native action has no native command")
check(NativeArrangementCommand.matches("Left & Quarters", names: NativeArrangementCommand.titles(for: .arrangeThree)), "English three-window command is recognized")
check(NativeArrangementCommand.matches("左側與右側", names: NativeArrangementCommand.titles(for: .arrangeTwo)), "traditional Chinese two-window command is recognized")
check(!NativeArrangementCommand.matches("Left & Right…", names: NativeArrangementCommand.titles(for: .arrangeTwo)), "unknown commands fail closed instead of fuzzy matching")
check(Action.allCases.prefix(12).map(\.rawValue) == ["left", "right", "top", "bottom", "maximize", "center", "restore", "nextDisplay", "fullScreen", "arrangeTwo", "arrangeThree", "arrangeFour"], "all existing Carbon action IDs remain stable")
check(Action.arrangeTwo.title == "双窗口左右排布" && Action.arrangeTwoVertical.title == "双窗口上下排布", "horizontal and vertical actions have distinct labels")
check(!NativeArrangementCommand.matches("顶部", names: NativeArrangementCommand.titles(for: .arrangeTwoVertical)) && !NativeArrangementCommand.matches("Left & Right", names: NativeArrangementCommand.titles(for: .arrangeTwoVertical)), "vertical arrangement cannot invoke a single-window or horizontal command")
check(NativeArrangementCommand.matches("Top & Bottom", names: NativeArrangementCommand.titles(for: .arrangeTwoVertical)) && NativeArrangementCommand.matches("頂部與底部", names: NativeArrangementCommand.titles(for: .arrangeTwoVertical)), "vertical native command supports English and traditional Chinese")
let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
let left = CGRect(x: 0, y: 25, width: 720, height: 875)
let right = CGRect(x: 720, y: 25, width: 720, height: 875)
check(NativeArrangementGeometry.needsCompletion(.arrangeTwo, primary: left, companion: CGRect(x: 1100, y: 25, width: 720, height: 875), visible: visible), "partial companion origin needs one completion pass")
check(!NativeArrangementGeometry.needsCompletion(.arrangeTwo, primary: left, companion: right, visible: visible), "completed pair is not repeated")
check(!NativeArrangementGeometry.needsCompletion(.arrangeTwo, primary: left.insetBy(dx: 8, dy: 8), companion: right.insetBy(dx: 8, dy: 8), visible: visible), "system tiling margins are preserved")
check(!NativeArrangementGeometry.needsCompletion(.arrangeTwo, primary: CGRect(x: 100, y: 100, width: 500, height: 500), companion: right, visible: visible), "no retry when target has not taken native primary slot")
check(!NativeArrangementGeometry.needsCompletion(.arrangeTwo, primary: left, companion: CGRect(x: -1000, y: 25, width: 500, height: 500), visible: visible), "unrelated display does not trigger completion")
check(!NativeArrangementGeometry.needsCompletion(.arrangeFour, primary: left, companion: right, visible: visible), "multiwindow combinations are never blindly replayed")
let top = Layout.frame(.top, window: .zero, visible: visible)
check(NativeArrangementGeometry.needsCompletion(.arrangeTwoVertical, primary: top, companion: CGRect(x: 0, y: 700, width: 1440, height: 437.5), visible: visible), "vertical partial pair is detected")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/Layout.swift Sources/Loom/NativeArrangementCommand.swift Sources/Loom/NativeArrangementGeometry.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
