#!/usr/bin/env bash
# Builds a release binary and wraps it in build/pgpmana.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/pgpmana.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/pgpmana" "$APP/Contents/MacOS/pgpmana"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp -R Sources/pgpmana/Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R Sources/pgpmana/Resources/Images "$APP/Contents/Resources/Images"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP"
