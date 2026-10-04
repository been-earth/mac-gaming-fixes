#!/bin/sh
# Wraps build/MacGamingFixes.app into build/MacGamingFixes-<version>.dmg (run through `make dmg`).
# The window is one drag: the app on the left, Applications on the right, assets/dmg/background*.png behind them.
# Finder itself lays the window out, so this needs a logged-in desktop session; the window flashes on screen once.
set -eu
cd "$(dirname "$0")/.."
APP=build/MacGamingFixes.app
NAME=MacGamingFixes
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG=build/$NAME-$VERSION.dmg
STAGE=build/dmg
RW=build/dmg-rw.dmg

rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# one TIFF holding both resolutions: Finder takes the 2x picture on a Retina display
tiffutil -cathidpicheck assets/dmg/background.png assets/dmg/background@2x.png -out "$STAGE/.background/background.tiff" >/dev/null

hdiutil create -quiet -srcfolder "$STAGE" -volname "$NAME" -fs HFS+ -format UDRW -size 32m "$RW"
MOUNT=$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}')
trap 'hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true; rm -rf "$STAGE" "$RW"' EXIT
# the mount point is the disk's name as Finder knows it: it gets a suffix when a volume of that name is already mounted
DISK=$(basename "$MOUNT")

# 660x400 of content under the title bar (28 pt, 32 on macOS 26 and later); positions are icon centres, the same
# numbers as in the background. The background carries a plate under each label: Finder writes labels black in
# light mode and white in dark mode.
osascript <<SCRIPT
tell application "Finder"
    tell disk "$DISK"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {200, 120, 860, 548}
        set options to icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 112
        set text size of options to 12
        set background picture of options to file ".background:background.tiff"
        set position of item "$NAME.app" of container window to {180, 190}
        set position of item "Applications" of container window to {480, 190}
        -- Finder saves a window when it closes, and not at once: without the pauses the reopened window gets the default size
        close
        delay 1
        open
        delay 1
        close
    end tell
end tell
SCRIPT
rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach "$MOUNT" -quiet
trap 'rm -rf "$STAGE" "$RW"' EXIT
hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG"
echo "built $DMG"
