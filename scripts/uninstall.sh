#!/usr/bin/env bash
# Remove the Diodon Tasksheet plugin. Your saved tasks are kept unless you
# pass --purge.
#
#   scripts/uninstall.sh [--diodon-prefix DIR] [--plugin-dir DIR] [--purge]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN_DIR="$HOME/.local/bin"
LIBEXEC_DIR="$HOME/.local/lib/diodon-tasksheet"
PLUGIN_DIR="$DATA_HOME/diodon/plugins/tasksheet"
DIODON_PREFIX=""
PURGE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --diodon-prefix) DIODON_PREFIX="${2:?--diodon-prefix needs a directory}"; shift 2 ;;
        --plugin-dir)    PLUGIN_DIR="${2:?--plugin-dir needs a directory}"; shift 2 ;;
        --purge)         PURGE=1; shift ;;
        -h|--help)       sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ -n "$DIODON_PREFIX" ]]; then
    export GSETTINGS_SCHEMA_DIR="$DIODON_PREFIX/share/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"
    if [[ "$PLUGIN_DIR" == "$DATA_HOME/diodon/plugins/tasksheet" ]]; then
        PLUGIN_DIR="$DIODON_PREFIX/lib/diodon/plugins/tasksheet"
    fi
fi

disable_plugin() {
    local schema="net.launchpad.Diodon.plugins" key="active-plugins" current updated
    current="$(gsettings get "$schema" "$key" 2>/dev/null)" || return 1
    updated="$(python3 - "$current" tasksheet <<'PY'
import ast, sys
text = sys.argv[1].strip()
if text.startswith("@as"):
    text = text[3:].strip()
plugins = [p for p in ast.literal_eval(text) if p != sys.argv[2]]
print("[" + ", ".join("'" + p + "'" for p in plugins) + "]" if plugins else "@as []")
PY
)"
    gsettings set "$schema" "$key" "$updated"
}

disable_plugin && echo "Removed tasksheet from Diodon's active plugins." \
    || echo "Could not edit Diodon's settings (disable it in Preferences > Plugins)."

rm -rf "$PLUGIN_DIR"        && echo "Removed $PLUGIN_DIR"
rm -f  "$BIN_DIR/diodon-tasksheet" && echo "Removed $BIN_DIR/diodon-tasksheet"

if [[ -f "$LIBEXEC_DIR/setup-hotkeys.sh" ]]; then
    bash "$LIBEXEC_DIR/setup-hotkeys.sh" --undo || true
elif [[ -f "$HERE/scripts/setup-hotkeys.sh" ]]; then
    bash "$HERE/scripts/setup-hotkeys.sh" --undo || true
fi
rm -rf "$LIBEXEC_DIR" && echo "Removed $LIBEXEC_DIR"
rm -f "$DATA_HOME/man/man1/diodon-tasksheet.1"

TASKS="$DATA_HOME/diodon/tasksheet.ini"
if [[ $PURGE -eq 1 ]]; then
    rm -f "$TASKS" && echo "Deleted your saved tasks ($TASKS)"
else
    echo "Your saved tasks were kept: $TASKS   (delete with --purge)"
fi
echo "Restart Diodon:  pkill -x diodon; diodon &"
