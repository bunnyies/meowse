#!/bin/zsh
# Build Meowse and MOVE it into /Applications, replacing the previous install.
# Exactly one copy of the app exists afterwards: build/Meowse.app is gone.
#
#   scripts/install.sh              # build, install, relaunch
#   scripts/install.sh --no-build   # install the existing build/Meowse.app
#   scripts/install.sh --no-launch  # don't start it afterwards
#
# The move is a rename on the same volume: instant, no data copied.
#
# The Accessibility grant is tied to the app's signature (bundle ID +
# certificate), not its path, so it carries over to /Applications as long as
# build.sh signed with your Apple Development identity.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=app.meowse.Meowse
SRC=build/Meowse.app
DEST=/Applications/Meowse.app
BUILD=1 LAUNCH=1
for arg in "$@"; do
  case $arg in
    --no-build)  BUILD=0 ;;
    --no-launch) LAUNCH=0 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

(( BUILD )) && scripts/build.sh
[[ -d $SRC ]] || { echo "No $SRC. Run scripts/build.sh first."; exit 1; }
[[ -w /Applications ]] || { echo "/Applications isn't writable by $(whoami)."; exit 1; }

# Quit any running copy (wherever it was launched from) so it saves settings
# and releases its event tap. Only send quit if it's running: AppleScript
# would otherwise launch it.
if pgrep -x Meowse >/dev/null; then
  echo "Quitting running Meowse…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -x Meowse >/dev/null || break; /bin/sleep 0.25; done
  pgrep -x Meowse >/dev/null && { pkill -TERM -x Meowse; /bin/sleep 0.5; }
fi

codesign --verify --strict "$SRC"

# Swap: park the old install, move the new build in, then delete the old one.
# If the move fails, the previous install is put back.
OLD="/Applications/.Meowse.app.previous"
rm -rf "$OLD"
[[ -e $DEST ]] && mv "$DEST" "$OLD"
if ! mv "$SRC" "$DEST"; then
  [[ -e $OLD ]] && mv "$OLD" "$DEST"
  echo "Install failed; previous version restored."
  exit 1
fi
rm -rf "$OLD"

# Make LaunchServices/Spotlight prefer the installed copy.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

echo "Installed $DEST ($(du -sh "$DEST" | cut -f1))"
if (( LAUNCH )); then
  open "$DEST"
  echo "Launched. If Launch at login was turned on from the build/ copy, toggle it off and on once in Settings so it points here."
fi
