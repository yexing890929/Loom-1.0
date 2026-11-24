#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
func check(_ value: Bool, _ label: String) { precondition(value, label); print("PASS: \(label)") }
let suite = "dev.loom.permission-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var state = PalettePermissionState(trusted: false, defaults: defaults)
check(!state.enabled, "first unauthorized launch switch is off")
state.cancelAuthorization()
check(!state.enabled, "postpone leaves switch off")
state.updatePermission(true)
check(state.enabled, "first grant from any entry enables palette")
_ = state.request(false)
check(!state.enabled, "explicit disable takes effect")
state.updatePermission(false)
state.updatePermission(true)
check(!state.enabled, "regrant does not overwrite explicit disable")
state = PalettePermissionState(trusted: true, defaults: defaults)
check(!state.enabled, "explicit disable survives relaunch")
state.updatePermission(false)
check(state.request(true), "enabling without permission requests guide")
check(!state.enabled, "switch remains off while authorization is pending")
state.cancelAuthorization()
state.updatePermission(true)
check(!state.enabled, "cancelled switch request preserves previous disable")
state.updatePermission(false)
_ = state.request(true)
state.updatePermission(true)
check(state.enabled, "successful explicit enable overrides previous disable")
state.updatePermission(false)
check(!state.enabled, "permission revocation makes effective switch off")
state.updatePermission(true)
check(state.enabled, "permission recovery preserves enabled choice")
defaults.removePersistentDomain(forName: suite)
defaults.set(false, forKey: "paletteEnabled")
state = PalettePermissionState(trusted: true, defaults: defaults)
check(!state.enabled, "migration preserves legacy disabled preference")
defaults.removePersistentDomain(forName: suite)
state = PalettePermissionState(trusted: false, defaults: defaults)
_ = state.request(true)
state.cancelAuthorization()
state.updatePermission(true)
check(state.enabled, "postponing first authorization never becomes explicit opt-out")
SWIFT
mkdir -p .build/module-cache
xcrun swiftc -sdk "${LOOM_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/.build/module-cache" Sources/Loom/PalettePermissionState.swift "$WORK/main.swift" -o "$WORK/tests"
"$WORK/tests"
