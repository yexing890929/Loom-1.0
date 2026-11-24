#!/bin/zsh
# Local test package: ad-hoc signed, not Developer ID signed or notarized.
set -euo pipefail
cd "${0:A:h:h}"

./scripts/build.sh
APP="$PWD/dist/Loom.app"
VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "Invalid application version: $VERSION"
    exit 1
fi
/usr/bin/codesign --verify --strict "$APP"

# Keep staging isolated so unrelated dist files cannot enter the image.
WORK=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
MOUNTED=false
cleanup() {
    if $MOUNTED; then
        /usr/bin/hdiutil detach "$WORK/mount" || return
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir "$WORK/payload"
/usr/bin/ditto "$APP" "$WORK/payload/Loom.app"
ln -s /Applications "$WORK/payload/Applications"
mkdir "$WORK/payload/.background" "$WORK/mount"
SDK="${LOOM_SDK:-$(xcrun --show-sdk-path)}"
xcrun swiftc -sdk "$SDK" -module-cache-path "$PWD/.build/module-cache" \
    scripts/build-dmg-background.swift -o .build/build-dmg-background
.build/build-dmg-background "$WORK/payload/.background/background.png" "$PWD/scripts/dmg-assets/arrow.svg"

# Finder writes .DS_Store on the mounted image so the background alias refers
# to its final volume. Only the staging image is opened/configured.
/usr/bin/hdiutil create -volname "Loom $VERSION" -srcfolder "$WORK/payload" \
    -fs HFS+ -format UDRW "$WORK/editable.dmg"
/usr/bin/hdiutil attach -nobrowse -mountpoint "$WORK/mount" "$WORK/editable.dmg"
MOUNTED=true
/usr/bin/osascript scripts/configure-dmg.applescript "$WORK/mount"
[[ -s "$WORK/mount/.DS_Store" ]]
/bin/sync
/usr/bin/hdiutil detach "$WORK/mount"
MOUNTED=false

OUTPUT="$PWD/dist/Loom-$VERSION.dmg"
# Create and verify before replacing any previous successful package.
/usr/bin/hdiutil convert "$WORK/editable.dmg" -format UDZO -o "$WORK/Loom.dmg"
/usr/bin/hdiutil verify "$WORK/Loom.dmg"
mv -f "$WORK/Loom.dmg" "$OUTPUT"
/usr/bin/shasum -a 256 "$OUTPUT" > "$OUTPUT.sha256"
print "Packaged: $OUTPUT"
print "Architecture: $(uname -m). Local testing only; not notarized."
print "Open the DMG and drag Loom.app to Applications before launching."
