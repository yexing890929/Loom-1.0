#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import AppKit
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) }; print("PASS: \(name)") }
check(PermissionOnboardingPolicy.shouldPresent(hasLaunched: false, dismissed: false, trusted: false), "first launch without permission shows guide")
check(PermissionOnboardingPolicy.shouldPresent(hasLaunched: false, dismissed: false, trusted: true), "first launch with permission shows ready state")
check(!PermissionOnboardingPolicy.shouldPresent(hasLaunched: true, dismissed: true, trusted: false), "later setting choice is respected on subsequent launches")
check(!PermissionOnboardingPolicy.shouldPresent(hasLaunched: true, dismissed: false, trusted: true), "existing authorized installation does not get an unnecessary guide")
check(PermissionOnboardingPolicy.shouldPresent(hasLaunched: true, dismissed: false, trusted: false), "existing unauthorized installation gets new guide once")
var granted = false
var reads = 0
var opened = 0
var observed = false
let model = PermissionOnboardingModel(permission: { reads += 1; return granted }, openSettings: { opened += 1 }, onTrustChanged: { observed = $0 })
model.start()
check(!model.trusted, "guide starts in authorization state")
let idleReads = reads
RunLoop.main.run(until: Date().addingTimeInterval(0.6))
check(reads == idleReads, "opening guide alone does not start polling")
model.authorize()
check(opened == 1, "authorize button opens settings")
granted = true
RunLoop.main.run(until: Date().addingTimeInterval(0.6))
check(model.trusted && observed, "permission grant updates guide and settings model")
let readyReads = reads
RunLoop.main.run(until: Date().addingTimeInterval(0.6))
check(reads == readyReads, "permission grant stops checks immediately")
model.authorize()
check(opened == 1, "authorized state does not open settings again")
granted = false
NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
check(!model.trusted && !observed, "returning to Loom refreshes revoked permissions")
model.authorize()
model.stop()
let stoppedReads = reads
RunLoop.main.run(until: Date().addingTimeInterval(0.6))
check(reads == stoppedReads, "closing or postponing stops pending checks")
granted = true
NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
check(!model.trusted, "closed guide removes activation observer")
model.start()
check(model.trusted, "reopening guide refreshes permission state")
model.stop()
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/Layout.swift Sources/Loom/WindowManager.swift Sources/Loom/PermissionOnboarding.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
