#!/bin/zsh
# Build Meowse.app (release, universal) into ./build.
#
#   scripts/build.sh                      # signs with your Apple Development identity if present
#   scripts/build.sh --dev                # "Meowse dev.app", beside an installed Meowse
#   SIGN_IDENTITY="-" scripts/build.sh    # force ad-hoc
#   TIMESTAMP=1 scripts/build.sh          # add Apple's secure timestamp (needs network; releases)
#
# A stable identity keeps the Accessibility grant across rebuilds. With
# ad-hoc signing, macOS ties the grant to the exact binary, so every rebuild
# needs it granted again.
#
# Without a secure timestamp a signature is only valid while its certificate
# is, so the in-app updater would refuse a release once the certificate that
# signed it expires.
#
# A dev build has its own bundle ID, settings and Accessibility entry and never
# updates itself. Pause scrolling in one copy while both run.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV=0
for arg in "$@"; do
  case $arg in
    --dev) DEV=1 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done
NAME=Meowse BUNDLE_ID=app.meowse.Meowse
(( DEV )) && NAME="Meowse dev" BUNDLE_ID=app.meowse.Meowse.dev

APP="build/$NAME.app"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ { print $2; exit }')
fi
IDENTITY="${SIGN_IDENTITY:--}"
echo "Signing with: ${IDENTITY/#-/ad-hoc}"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Meowse" "$APP/Contents/MacOS/$NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
strip -x "$APP/Contents/MacOS/$NAME"
if (( DEV )); then
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $BUNDLE_ID" \
    -c "Set :CFBundleExecutable '$NAME'" \
    -c "Set :CFBundleName '$NAME'" \
    -c "Set :CFBundleDisplayName '$NAME'" \
    -c "Delete :MeowseUpdateRepository" \
    "$APP/Contents/Info.plist"
fi

# The Settings window is an app of its own inside this one, so everything it
# loads goes back to the system when it closes. Its Info.plist is Meowse's,
# renamed, so the versions always match.
HELPER="$APP/Contents/Helpers/Meowse Settings.app"
mkdir -p "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"
cp "$BIN/MeowseSettings" "$HELPER/Contents/MacOS/Meowse Settings"
cp Resources/Info.plist "$HELPER/Contents/Info.plist"
# It never shows a Dock icon, only list-sized ones (Activity Monitor,
# Finder), so it gets the app icon's 16 and 32 pt images: 10 KB, not 440.
ICONS=$(mktemp -d)
iconutil -c iconset Resources/AppIcon.icns -o "$ICONS/all.iconset"
mkdir "$ICONS/small.iconset"
cp "$ICONS"/all.iconset/icon_{16x16,32x32}{,@2x}.png "$ICONS/small.iconset/"
iconutil -c icns "$ICONS/small.iconset" -o "$HELPER/Contents/Resources/AppIcon.icns"
rm -rf "$ICONS"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier $BUNDLE_ID.Settings" \
  -c "Set :CFBundleExecutable 'Meowse Settings'" \
  -c "Set :CFBundleName 'Meowse Settings'" \
  -c "Set :CFBundleDisplayName 'Meowse Settings'" \
  -c "Delete :MeowseUpdateRepository" \
  "$HELPER/Contents/Info.plist"
strip -x "$HELPER/Contents/MacOS/Meowse Settings"

# Inside out: the helper's signature is sealed into Meowse's.
TS=--timestamp=none
[[ ${TIMESTAMP:-0} == 1 ]] && TS=--timestamp
codesign --force --options runtime $TS --sign "$IDENTITY" "$HELPER"
codesign --force --options runtime $TS --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1))"
