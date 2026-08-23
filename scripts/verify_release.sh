#!/bin/bash
set -euo pipefail

APP=${1:?Usage: verify_release.sh /path/to/TravelTime.app}
test -d "$APP"
test -x "$APP/Contents/MacOS/TravelTime"
test -f "$APP/Contents/Resources/AppIcon.icns"
test -f "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
test "$BUNDLE_ID" = "com.atom.tzbar"
test -n "$VERSION"
test -n "$BUILD"
codesign --verify --deep --strict "$APP"
echo "Verified TravelTime $VERSION ($BUILD): icon, metadata, executable, signature"
