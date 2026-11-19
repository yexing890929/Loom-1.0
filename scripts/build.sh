#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SDK="${LOOM_SDK:-$(xcrun --show-sdk-path)}"
APP="$PWD/dist/Loom.app"
mkdir -p "$APP/Contents/MacOS" .build/module-cache
xcrun swiftc -O -sdk "$SDK" -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx14.0" Sources/Loom/*.swift -o "$APP/Contents/MacOS/Loom"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier dev.loom.windowmanager "$APP"
echo "Built $APP"
