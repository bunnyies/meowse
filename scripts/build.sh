#!/bin/zsh
# Build Meowse.app (release, universal) into ./build.
#
#   scripts/build.sh                      # signs with your Apple Development identity if present
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
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Meowse.app
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ { print $2; exit }')
fi
IDENTITY="${SIGN_IDENTITY:--}"
echo "Signing with: ${IDENTITY/#-/ad-hoc}"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Meowse"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Meowse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
strip -x "$APP/Contents/MacOS/Meowse"

TS=--timestamp=none
[[ ${TIMESTAMP:-0} == 1 ]] && TS=--timestamp
codesign --force --options runtime $TS --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1))"
