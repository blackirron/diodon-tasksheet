#!/usr/bin/env bash
# Build and install the Diodon Tasksheet plugin for the current user.
# Nothing is installed system-wide and no root access is needed.
#
#   scripts/install.sh                       Diodon installed from your distro
#   scripts/install.sh --diodon-prefix DIR   Diodon built into a private prefix
#   scripts/install.sh --plugin-dir DIR      install the plugin somewhere else
#
# Requirements: meson, ninja, valac, and Diodon's development files
# (Ubuntu/Debian: sudo apt install diodon-dev libgtk-3-dev libpeas-dev valac meson).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN_DIR="$HOME/.local/bin"
LIBEXEC_DIR="$HOME/.local/lib/diodon-tasksheet"
PLUGIN_DIR="$DATA_HOME/diodon/plugins/tasksheet"
DIODON_PREFIX=""
BUILD="$HERE/build"

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --diodon-prefix) DIODON_PREFIX="${2:?--diodon-prefix needs a directory}"; shift 2 ;;
        --plugin-dir)    PLUGIN_DIR="${2:?--plugin-dir needs a directory}"; shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$*"; }
die()  { echo "error: $*" >&2; exit 1; }

for tool in meson ninja valac pkg-config; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' not found. Ubuntu/Debian: sudo apt install meson ninja-build valac pkg-config"
done

MESON_ARGS=()
if [[ -n "$DIODON_PREFIX" ]]; then
    # A Diodon built into a private prefix keeps its plugins under that
    # prefix, which Diodon always searches, so install there.
    export PKG_CONFIG_PATH="$DIODON_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export GSETTINGS_SCHEMA_DIR="$DIODON_PREFIX/share/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"
    MESON_ARGS+=("-Ddiodon_vapidir=$DIODON_PREFIX/share/vala/vapi"
                 "-Ddiodon_includedir=$DIODON_PREFIX/include/diodon")
    if [[ "$PLUGIN_DIR" == "$DATA_HOME/diodon/plugins/tasksheet" ]]; then
        PLUGIN_DIR="$DIODON_PREFIX/lib/diodon/plugins/tasksheet"
    fi
fi

pkg-config --exists diodon || die "Diodon's development files were not found.
  Distro Diodon:       sudo apt install diodon diodon-dev
  Diodon built by you: rerun with --diodon-prefix /path/to/its/install/prefix"

step "Configuring (Diodon $(pkg-config --modversion diodon))"
rm -rf "$BUILD"
meson setup "$BUILD" "$HERE" \
    -Dplugin_dir="$PLUGIN_DIR" -Dbin_dir="$BIN_DIR" -Dlibexec_dir="$LIBEXEC_DIR" \
    -Dmandir="$DATA_HOME/man" "${MESON_ARGS[@]}"

step "Compiling"
meson compile -C "$BUILD"

step "Running unit tests"
meson test -C "$BUILD" --print-errorlogs

step "Installing"
meson install -C "$BUILD"
echo "plugin:  $PLUGIN_DIR"
echo "command: $BIN_DIR/diodon-tasksheet"

step "Enabling the plugin in Diodon"
enable_plugin() {
    local schema="net.launchpad.Diodon.plugins" key="active-plugins" current updated
    current="$(gsettings get "$schema" "$key" 2>/dev/null)" || return 1
    updated="$(python3 - "$current" tasksheet <<'PY'
import ast, sys
text = sys.argv[1].strip()
if text.startswith("@as"):
    text = text[3:].strip()
plugins = ast.literal_eval(text)
if sys.argv[2] not in plugins:
    plugins.append(sys.argv[2])
print("[" + ", ".join("'" + p + "'" for p in plugins) + "]")
PY
)"
    gsettings set "$schema" "$key" "$updated"
}
if enable_plugin; then
    echo "Tasksheet added to Diodon's active plugins."
else
    echo "Could not update Diodon's settings automatically."
    echo "Enable it by hand: Diodon > Preferences > Plugins > Tasksheet."
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Note: $BIN_DIR is not on your PATH; use the full path when binding shortcuts." ;;
esac

cat <<MSG

Installed. Restart Diodon to load the plugin:
    pkill -x diodon; diodon &
Then click Diodon's menu -> "Tasksheet...".

Keyboard shortcuts (Win+V / Win+Y on GNOME):
    bash $HERE/scripts/setup-hotkeys.sh
MSG
