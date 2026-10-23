#!/usr/bin/env bash
# Safe test build for Ubuntu: builds an UNMODIFIED Diodon into a private
# folder, installs this plugin into it, enables it and starts Diodon.
#
# - Only build packages are installed system-wide (via apt).
# - Everything else lives in ~/diodon-tasksheet-test; delete it to undo.
# - Diodon's own source is never patched.
#
# Run from this folder:   bash test-install.sh
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HOME/diodon-tasksheet-test"
PREFIX="$WORK/prefix"
LOG="$WORK/build.log"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user (not with sudo); it asks for sudo itself." >&2
    exit 1
fi
[[ -f "$HERE/scripts/install.sh" ]] || { echo "Run this from the plugin folder (scripts/install.sh missing)." >&2; exit 1; }

mkdir -p "$WORK"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

on_error() {
    echo
    echo "FAILED. Full log: $LOG"
    echo "Please send me the first line containing 'error:' and the line above it."
}
trap on_error ERR

step "1/6  Build dependencies (sudo asks for your password once)"
sudo -v
PKGS=(git valac meson ninja-build pkg-config gettext xvfb zeitgeist-core
      libgtk-3-dev libglib2.0-dev libpeas-dev libxtst-dev libx11-dev libcairo2-dev)
pick() {  # package names differ between Ubuntu releases: first one that exists wins
    local p
    for p in "$@"; do
        if apt-cache show "$p" >/dev/null 2>&1; then PKGS+=("$p"); return 0; fi
    done
    echo "None of these packages exist on this system: $*" >&2
    return 1
}
pick libzeitgeist-2.0-dev libzeitgeist2.0-dev
pick libayatana-appindicator3-dev libappindicator3-dev
pick libgdk-pixbuf-2.0-dev libgdk-pixbuf2.0-dev
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends "${PKGS[@]}"

step "2/6  Unmodified Diodon source"
pkill -x diodon || true
if [[ -d "$WORK/src/.git" ]]; then
    # Undo any earlier patching of the Diodon tree (older versions of this
    # project patched Diodon's own files; this one never does).
    git -C "$WORK/src" checkout -q -- .
    git -C "$WORK/src" clean -fdq
else
    rm -rf "$WORK/src"
    git clone --depth 1 https://github.com/diodon-dev/diodon.git "$WORK/src"
fi
rm -rf "$PREFIX" "$WORK/src/build"

step "3/6  Building Diodon into $PREFIX"
cd "$WORK/src"
meson setup build --prefix="$PREFIX" --libdir=lib
meson compile -C build
meson install -C build
glib-compile-schemas "$PREFIX/share/glib-2.0/schemas"

step "4/6  Launcher"
cat > "$WORK/run-diodon.sh" <<LAUNCH
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export GSETTINGS_SCHEMA_DIR="$PREFIX/share/glib-2.0/schemas"
export XDG_DATA_DIRS="$PREFIX/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec "$PREFIX/bin/diodon" "\$@"
LAUNCH
chmod +x "$WORK/run-diodon.sh"

step "5/6  Building, testing and installing the Tasksheet plugin"
bash "$HERE/scripts/install.sh" --diodon-prefix "$PREFIX"

step "6/6  Starting Diodon"
trap - ERR
cat <<MSG

Build OK.  Now test:
  1. Copy two or three texts anywhere.
  2. Click the Diodon tray icon -> 'Tasksheet...'
  3. Ctrl+C here stops Diodon. Start it again any time:
         $WORK/run-diodon.sh
  4. Keyboard shortcuts (Win+V / Win+Y):
         bash $HERE/scripts/setup-hotkeys.sh

Debug log: $WORK/diodon.log

MSG
G_MESSAGES_DEBUG=all "$WORK/run-diodon.sh" 2>&1 | tee "$WORK/diodon.log" || true

echo
echo "Stopped. To undo: bash $HERE/scripts/uninstall.sh --diodon-prefix $PREFIX ; then rm -rf $WORK"
