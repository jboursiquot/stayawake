#!/bin/bash
# Builds StayAwake.app next to this script. Needs only Command Line Tools (no Xcode).
set -euo pipefail
cd "$(dirname "$0")"

APP=StayAwake
ARCH="$(uname -m)"
OUT="$APP.app/Contents/MacOS"
RES="$APP.app/Contents/Resources"

# App icon: regenerate when missing or when the generator changed.
if [ ! -f AppIcon.icns ] || [ scripts/make-icon.swift -nt AppIcon.icns ]; then
  rm -rf AppIcon.iconset
  swift scripts/make-icon.swift AppIcon.iconset
  iconutil -c icns AppIcon.iconset -o AppIcon.icns
  rm -rf AppIcon.iconset
fi

rm -rf "$APP.app"
mkdir -p "$OUT" "$RES"

swiftc -O -parse-as-library \
  -target "$ARCH-apple-macos13.0" \
  -framework SwiftUI -framework AppKit -framework IOKit -framework ServiceManagement \
  Sources/*.swift -o "$OUT/$APP"

cp Info.plist "$APP.app/Contents/Info.plist"
cp AppIcon.icns "$RES/AppIcon.icns"
codesign --force --sign - "$APP.app"

# Nudge LaunchServices so Finder/Spotlight pick up the new icon instead of a cached one.
touch "$APP.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP.app" >/dev/null 2>&1 || true

echo "built $APP.app — run with: open $APP.app   (or cp -R $APP.app /Applications/)"
