#!/bin/bash
# Build Ipil.app: compile, assemble the bundle, borrow the Ipil favicon as the
# menu bar icon, ad-hoc codesign (stable TCC identity for Screen Recording).
set -euo pipefail
cd "$(dirname "$0")"

# Build OUTSIDE iCloud/Dropbox/etc — a synced folder can re-add metadata
# mid-build and break codesign. ~/.cache is a safe local-only default.
APP="$HOME/.cache/ipil-build/Ipil.app"
ICON_SRC="$(dirname "$0")/screenshots/ipil-icon.png"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/Ipil" \
  -framework Cocoa -framework Carbon

cp Info.plist "$APP/Contents/Info.plist"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APP/Contents/Resources/menubar.png"
fi

xattr -cr "$APP"   # iCloud Drive adds metadata that codesign rejects
codesign --force --sign - "$APP"
echo "Built $APP"
