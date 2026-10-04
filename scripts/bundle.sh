#!/bin/sh
# Assembles build/MacGamingFixes.app from the release build (run through `make build`).
set -eu
cd "$(dirname "$0")/.."
BIN=$(swift build -c release --show-bin-path)
APP=build/MacGamingFixes.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MGF" "$APP/Contents/MacOS/MacGamingFixes"
cp -R "$BIN/MacGamingFixes_MGF.bundle" "$APP/Contents/Resources/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp Sources/MGF/Resources/Brand/MGF.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad hoc by default: enough to run locally. macOS ties the App Management permission to the signature, so an
# ad hoc build loses it on every rebuild; MGF_SIGN_IDENTITY="Apple Development: …" keeps it.
codesign --force --sign "${MGF_SIGN_IDENTITY:--}" "$APP"
echo "built $APP"
