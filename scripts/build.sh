#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SDK="${LOOM_SDK:-$(xcrun --show-sdk-path)}"
APP="$PWD/dist/Loom.app"
mkdir -p "$APP/Contents/MacOS" .build/module-cache
RESOURCES="$APP/Contents/Resources"
mkdir -p "$RESOURCES"
# Compile the layered document directly; actool also supplies legacy macOS icons.
if ! xcrun --find actool >/dev/null 2>&1; then
    print -u2 "Install and select full Xcode to compile icon/Loom.icon."
    exit 1
fi
ICON_OUTPUT=$(mktemp -d "$PWD/.build/native-icon.XXXXXX")
trap 'rm -rf "$ICON_OUTPUT"' EXIT
ICON_INFO="$ICON_OUTPUT/icon-info.plist"
xcrun actool "$PWD/icon/Loom.icon" --compile "$ICON_OUTPUT" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon Loom \
    --output-partial-info-plist "$ICON_INFO" --output-format human-readable-text
[[ -s "$ICON_OUTPUT/Assets.car" && -s "$ICON_OUTPUT/Loom.icns" ]]
cp "$ICON_OUTPUT/Assets.car" "$ICON_OUTPUT/Loom.icns" "$RESOURCES/"
xcrun swiftc -sdk "$SDK" -module-cache-path "$PWD/.build/module-cache" scripts/build-menu-icon.swift -o .build/build-menu-icon
.build/build-menu-icon "$PWD/icon/顶部菜单栏图标.svg" "$RESOURCES/MenuBarTemplate.pdf"
mkdir -p "$RESOURCES/Onboarding"
xcrun swiftc -sdk "$SDK" -module-cache-path "$PWD/.build/module-cache" scripts/build-onboarding-assets.swift -o .build/build-onboarding-assets
.build/build-onboarding-assets "$PWD/Sources/Loom/Resources/Onboarding/AppIcon.svg" "$RESOURCES/Onboarding/AppIcon.png" 376 376
.build/build-onboarding-assets "$PWD/Sources/Loom/Resources/Onboarding/Success.svg" "$RESOURCES/Onboarding/Success.png" 90.667 90.667
xcrun swiftc -O -sdk "$SDK" -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx14.0" Sources/Loom/*.swift -o "$APP/Contents/MacOS/Loom"
cp Info.plist "$APP/Contents/Info.plist"
for KEY in CFBundleIconFile CFBundleIconName; do
    VALUE=$(/usr/bin/plutil -extract "$KEY" raw -o - "$ICON_INFO")
    /usr/bin/plutil -replace "$KEY" -string "$VALUE" "$APP/Contents/Info.plist"
done
codesign --force --sign - --identifier dev.loom.windowmanager "$APP"
touch "$APP"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -x "$LSREGISTER" ]]; then
    if ! "$LSREGISTER" -f "$APP"; then
        print -u2 "Built successfully; Finder icon registration could not be refreshed."
    fi
fi
echo "Built $APP"
