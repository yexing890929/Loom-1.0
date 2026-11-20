#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SDK="${LOOM_SDK:-$(xcrun --show-sdk-path)}"
APP="$PWD/dist/Loom.app"
mkdir -p "$APP/Contents/MacOS" .build/module-cache
RESOURCES="$APP/Contents/Resources"
ICONSET="$PWD/.build/Loom.iconset"
mkdir -p "$RESOURCES" "$ICONSET"
ICTOOL="${LOOM_ICTOOL:-/Applications/Icon Composer.app/Contents/Executables/ictool}"
if [[ ! -x "$ICTOOL" ]]; then
    print -u2 "Install Apple Icon Composer or set LOOM_ICTOOL to its ictool executable."
    exit 1
fi
ICON_RENDER="$PWD/.build/Loom-rendered.png"
"$ICTOOL" "$PWD/icon/Loom.icon" --export-image --output-file "$ICON_RENDER" --platform macOS --rendition Default --width 1024 --height 1024 --scale 1 >/dev/null
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ICON_RENDER" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$ICON_RENDER" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/Loom.icns"
xcrun swiftc -sdk "$SDK" -module-cache-path "$PWD/.build/module-cache" scripts/build-menu-icon.swift -o .build/build-menu-icon
.build/build-menu-icon "$PWD/icon/顶部菜单栏图标.svg" "$RESOURCES/MenuBarTemplate.pdf"
xcrun swiftc -O -sdk "$SDK" -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx14.0" Sources/Loom/*.swift -o "$APP/Contents/MacOS/Loom"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier dev.loom.windowmanager "$APP"
touch "$APP"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -x "$LSREGISTER" ]]; then
    if ! "$LSREGISTER" -f "$APP"; then
        print -u2 "Built successfully; Finder icon registration could not be refreshed."
    fi
fi
echo "Built $APP"
