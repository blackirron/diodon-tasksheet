#!/usr/bin/env bash
# Registers two GNOME keyboard shortcuts for the Diodon Tasksheet:
#   Super+V  -> Clipboard tab   (Super = the Windows key)
#   Super+Y  -> Tasksheet tab
# Pressing a shortcut again while its tab is showing closes the popup.
#
# If another GNOME shortcut already owns one of these keys (GNOME uses
# Super+V for the notification list), it is released first. Everything
# changed is saved so it can be put back exactly:
#
#   bash setup-hotkeys.sh          install, then verify
#   bash setup-hotkeys.sh --undo   remove our shortcuts, restore the old ones
set -euo pipefail

GS="${GSETTINGS:-gsettings}"
LIST_SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
ITEM_SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
BASE="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/diodon-tasksheet"
RELEASED="$STATE_DIR/released-bindings.tsv"
OLD_STATE="$STATE_DIR/toggle-message-tray.orig"   # written by an earlier version

IDS=(diodon-clipboard diodon-tasksheet)
NAMES=("Diodon: Clipboard tab" "Diodon: Tasksheet tab")
KEYS=("<Super>v" "<Super>y")
CALL="gdbus call --session --dest org.diodon.Tasksheet --object-path /org/diodon/Tasksheet --method org.diodon.Tasksheet."
CMDS=("${CALL}ShowClipboard" "${CALL}ShowTasksheet")

if ! command -v "$GS" >/dev/null 2>&1 || ! $GS list-schemas 2>/dev/null | grep -qx "$LIST_SCHEMA"; then
    echo "This is not a GNOME session, so shortcuts must be set in your desktop's settings."
    echo "Create two custom keyboard shortcuts running these commands:"
    echo "  ${CMDS[0]}"
    echo "  ${CMDS[1]}"
    echo "(XFCE: Settings > Keyboard > Application Shortcuts.  KDE: System Settings > Shortcuts > Custom.)"
    exit 1
fi

# ---- GVariant string-array helpers (python parses them safely) ----
get_list() {
    $GS get "$LIST_SCHEMA" custom-keybindings | python3 -c '
import ast,sys
t=sys.stdin.read().strip()
if t.startswith("@as"): t=t[3:].strip()
for p in ast.literal_eval(t): print(p)'
}
set_list() {  # paths on stdin, one per line
    local value
    value="$(python3 -c '
import sys
print("[" + ", ".join("\x27"+l.strip()+"\x27" for l in sys.stdin if l.strip()) + "]")')"
    $GS set "$LIST_SCHEMA" custom-keybindings "$value"
}

# Prints "schema<TAB>key<TAB>original<TAB>replacement" for every OTHER
# GNOME setting that is a list of accelerators containing one of ours.
find_conflicts() {
    $GS list-recursively | python3 -c '
import ast,sys
accels={a.lower() for a in sys.argv[1:]}
for line in sys.stdin:
    parts=line.rstrip("\n").split(" ",2)
    if len(parts)<3: continue
    schema,key,raw=parts
    t=raw.strip()
    if t.startswith("@as"): t=t[3:].strip()
    if not t.startswith("["): continue
    try: lst=ast.literal_eval(t)
    except Exception: continue
    if not isinstance(lst,list) or not all(isinstance(x,str) for x in lst): continue
    if not any(x.lower() in accels for x in lst): continue
    new=[x for x in lst if x.lower() not in accels]
    print("\t".join([schema,key,raw.strip(),"["+", ".join("\x27"+x+"\x27" for x in new)+"]"]))
' "${KEYS[@]}"
}

# ------------------------------------------------------------ undo
if [[ "${1:-}" == "--undo" ]]; then
    keep=""
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        drop=0
        for id in "${IDS[@]}"; do [[ "$p" == "$BASE/$id/" ]] && drop=1; done
        [[ $drop -eq 0 ]] && keep+="$p"$'\n'
    done <<< "$(get_list || true)"
    printf '%s' "$keep" | set_list
    for id in "${IDS[@]}"; do
        $GS reset-recursively "$ITEM_SCHEMA:$BASE/$id/" 2>/dev/null || true
    done

    if [[ -f "$OLD_STATE" ]]; then
        # shellcheck disable=SC2046
        $GS set org.gnome.shell.keybindings toggle-message-tray \
            "[$(python3 -c 'import sys; print(", ".join("\x27"+a+"\x27" for a in sys.argv[1:]))' $(cat "$OLD_STATE"))]"
        rm -f "$OLD_STATE"
    fi
    if [[ -f "$RELEASED" ]]; then
        while IFS=$'\t' read -r schema key original _; do
            [[ -z "$schema" ]] && continue
            $GS set "$schema" "$key" "$original" && echo "restored $schema $key"
        done < "$RELEASED"
        rm -f "$RELEASED"
    fi
    echo "Diodon shortcuts removed; previous shortcuts restored."
    exit 0
fi

# ------------------------------------------------------------ install
mkdir -p "$STATE_DIR"; touch "$RELEASED"

echo "1/3  Releasing other shortcuts that use ${KEYS[*]} ..."
released_any=0
while IFS=$'\t' read -r schema key original replacement; do
    [[ -z "$schema" ]] && continue
    grep -qF "$schema"$'\t'"$key"$'\t' "$RELEASED" || printf '%s\t%s\t%s\n' "$schema" "$key" "$original" >> "$RELEASED"
    $GS set "$schema" "$key" "$replacement"
    echo "     released: $schema $key   (was $original)"
    released_any=1
done < <(find_conflicts)
[[ $released_any -eq 0 ]] && echo "     none found (or already released)"

echo "2/3  Registering the Diodon shortcuts ..."
# An earlier manual attempt (or older version of this script) may have left a
# custom shortcut that runs the same Diodon command on the same key. Two
# bindings on one key can cancel each other out, so such leftovers are
# replaced; shortcuts running anything else are never touched, only reported.
updated=""
while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    mine=0; for id in "${IDS[@]}"; do [[ "$p" == "$BASE/$id/" ]] && mine=1; done
    if [[ $mine -eq 0 ]]; then
        b="$($GS get "$ITEM_SCHEMA:$p" binding 2>/dev/null || true)"
        c="$($GS get "$ITEM_SCHEMA:$p" command 2>/dev/null || true)"
        for k in "${KEYS[@]}"; do
            if [[ "${b,,}" == "'${k,,}'" && ( "$c" == *org.diodon.Tasksheet* || "$c" == *diodon-tasksheet* ) ]]; then
                n="$($GS get "$ITEM_SCHEMA:$p" name 2>/dev/null || true)"
                echo "     replacing your earlier Diodon shortcut $n ($k)"
                $GS reset-recursively "$ITEM_SCHEMA:$p" 2>/dev/null || true
                continue 2
            fi
        done
    fi
    updated+="$p"$'\n'
done <<< "$(get_list || true)"

for i in "${!IDS[@]}"; do
    path="$BASE/${IDS[$i]}/"
    grep -qxF "$path" <<< "$updated" || updated+="$path"$'\n'
    $GS set "$ITEM_SCHEMA:$path" name "${NAMES[$i]}"
    $GS set "$ITEM_SCHEMA:$path" command "${CMDS[$i]}"
    $GS set "$ITEM_SCHEMA:$path" binding "${KEYS[$i]}"
done
printf '%s' "$updated" | set_list

echo "3/3  Verifying ..."
problems=0
for i in "${!IDS[@]}"; do
    got="$($GS get "$ITEM_SCHEMA:$BASE/${IDS[$i]}/" binding)"
    if [[ "$got" == "'${KEYS[$i]}'" ]]; then
        echo "     OK   ${KEYS[$i]} -> ${NAMES[$i]}"
    else
        echo "     FAIL ${KEYS[$i]} reads back as $got"; problems=1
    fi
done
# another *custom* shortcut using the same key would still collide
while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    mine=0; for id in "${IDS[@]}"; do [[ "$p" == "$BASE/$id/" ]] && mine=1; done
    [[ $mine -eq 1 ]] && continue
    b="$($GS get "$ITEM_SCHEMA:$p" binding 2>/dev/null || true)"
    for k in "${KEYS[@]}"; do
        if [[ "${b,,}" == "'${k,,}'" ]]; then
            n="$($GS get "$ITEM_SCHEMA:$p" name 2>/dev/null || true)"
            echo "     CONFLICT: your custom shortcut $n also uses $k - remove it in Settings > Keyboard"
            problems=1
        fi
    done
done <<< "$(get_list || true)"
remaining="$(find_conflicts || true)"
if [[ -n "$remaining" ]]; then
    echo "     CONFLICT: still bound elsewhere:"; echo "$remaining" | cut -f1,2 | sed 's/^/       /'
    problems=1
fi
if command -v gdbus >/dev/null 2>&1; then
    if gdbus introspect --session --dest org.diodon.Tasksheet --object-path /org/diodon/Tasksheet >/dev/null 2>&1; then
        echo "     OK   Diodon Tasksheet service is running"
    else
        echo "     NOTE Diodon is not running (or the Tasksheet plugin is not loaded): start it, then try the keys"
    fi
fi
echo "     session type: ${XDG_SESSION_TYPE:-unknown}"

echo
if [[ $problems -eq 0 ]]; then
    echo "Done: Super+V -> Clipboard tab, Super+Y -> Tasksheet tab.  Undo: bash $0 --undo"
else
    echo "Installed, but see the lines above marked FAIL/CONFLICT."
fi
