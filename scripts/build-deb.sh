#!/usr/bin/env bash
# Build the diodon-tasksheet .deb package for THIS machine's Diodon.
#
#   bash scripts/build-deb.sh              build (sudo once, to install build packages)
#   bash scripts/build-deb.sh --no-deps    do not install build packages
#   bash scripts/build-deb.sh --dry-run    prepare and show what would be built; build nothing
#
# Result: dist/diodon-tasksheet_<version>_<arch>.deb
# Install: sudo apt install ./dist/diodon-tasksheet_*.deb
#
# A Diodon plugin links against libdiodon, so the package is built against
# the Diodon installed on this machine. Build on the distribution release
# you want to install on.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBDIRS="${DIODON_LIBDIRS:-/usr/lib /usr/lib64 /usr/local/lib}"
SCHEMA_DIR="${DIODON_SCHEMA_DIR:-/usr/share/glib-2.0/schemas}"
INSTALL_DEPS=1
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --no-deps) INSTALL_DEPS=0 ;;
        --dry-run) DRY_RUN=1; INSTALL_DEPS=0 ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'note: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run as your normal user, not root; sudo is used only to install build packages"

VERSION="$(sed -n "s/^[[:space:]]*version: '\([^']*\)'.*/\1/p" "$HERE/meson.build" | head -1)"
[[ -n "$VERSION" ]] || die "cannot read the version from meson.build"

# Reads Diodon's real GSettings schema and writes a default-plugins override
# that is the current default plus "tasksheet". Fails (writes nothing) if the
# schema or key is not found, so nothing is ever guessed.
make_override() {  # $1 = output file
    python3 - "$SCHEMA_DIR" "$1" <<'PY'
import ast, glob, os, sys
import xml.etree.ElementTree as ET

schema_dir, out = sys.argv[1], sys.argv[2]
for path in sorted(glob.glob(os.path.join(schema_dir, "*.gschema.xml"))):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        continue
    for schema in root.iter("schema"):
        if schema.get("id") != "net.launchpad.Diodon.plugins":
            continue
        for key in schema.iter("key"):
            if key.get("name") == "active-plugins" and key.get("type") == "as":
                plugins = ast.literal_eval(key.findtext("default"))
                if "tasksheet" not in plugins:
                    plugins.append("tasksheet")
                with open(out, "w") as f:
                    f.write("[net.launchpad.Diodon.plugins]\n")
                    f.write("active-plugins=[" + ", ".join("'%s'" % p for p in plugins) + "]\n")
                sys.exit(0)
sys.exit(1)
PY
}

# Debian and Ubuntu ship Diodon's headers as "diodon-dev"; some other
# releases or derivatives use "libdiodon-dev". Pick whichever one exists.
pick_dev_package() {
    local p
    for p in diodon-dev libdiodon-dev; do
        if apt-cache show "$p" >/dev/null 2>&1; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------- 1. packages
if [[ $INSTALL_DEPS -eq 1 ]]; then
    step "1/5  Build packages (sudo asks for your password once)"
    sudo apt-get update -qq
    DEV_PKG="$(pick_dev_package)" || die "no Diodon development package found (tried diodon-dev and libdiodon-dev). Enable the 'universe' repository (sudo add-apt-repository universe; sudo apt update) and run this again."
    echo "Using development package: $DEV_PKG"
    sudo apt-get install -y --no-install-recommends \
        dpkg-dev debhelper meson ninja-build pkg-config valac \
        libglib2.0-dev libgtk-3-dev libpeas-dev \
        diodon "$DEV_PKG" python3
else
    step "1/5  Build packages: skipped"
fi
command -v dpkg-buildpackage >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]] \
    || die "dpkg-buildpackage not found (sudo apt install dpkg-dev debhelper)"

# ----------------------------------------------- 2. where does Diodon keep plugins?
step "2/5  Looking at the installed Diodon"
PLUGIN_DIR=""
for root in $LIBDIRS; do
    [[ -d "$root" ]] || continue
    found="$(find "$root" -path '*/diodon/plugins/indicator/libindicator.so' 2>/dev/null | head -1)"
    if [[ -n "$found" ]]; then
        PLUGIN_DIR="$(dirname "$(dirname "$found")")/tasksheet"
        break
    fi
done
if [[ -n "$PLUGIN_DIR" ]]; then
    echo "Diodon's plugin directory: $(dirname "$PLUGIN_DIR")"
else
    warn "could not find Diodon's indicator plugin; using the standard location"
fi

# ------------------------------------------------------------- 3. staging copy
step "3/5  Preparing a clean source copy"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/diodon-tasksheet-build.XXXXXX")"
SRC="$STAGE/diodon-tasksheet-$VERSION"
mkdir "$SRC"
tar -C "$HERE" --exclude=./build --exclude=./dist --exclude=./.git -cf - . | tar -C "$SRC" -xf -

NAME="${DEBFULLNAME:-$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)}"
NAME="${NAME:-$USER}"
EMAIL="${DEBEMAIL:-$USER@$(hostname -s 2>/dev/null || echo localhost)}"
sed -e "s/@VERSION@/$VERSION/" \
    -e "s|@MAINTAINER@|$NAME <$EMAIL>|" \
    -e "s/@DATE@/$(date -R)/" \
    "$HERE/debian/changelog.in" > "$SRC/debian/changelog"
rm -f "$SRC/debian/changelog.in"
chmod +x "$SRC/debian/rules"   # some unzip tools drop the executable bit

if make_override "$SRC/debian/diodon-tasksheet.gsettings-override"; then
    echo "Active by default: $(tail -1 "$SRC/debian/diodon-tasksheet.gsettings-override" | cut -d= -f2)"
else
    warn "Diodon's plugin setting was not found; after installing, run: diodon-tasksheet enable"
fi
echo "maintainer: $NAME <$EMAIL>"
echo "version:    $VERSION"

if [[ $DRY_RUN -eq 1 ]]; then
    echo
    echo "--dry-run: nothing built. Would run in $SRC:"
    echo "  TASKSHEET_PLUGIN_DIR=${PLUGIN_DIR:-<meson default>} dpkg-buildpackage -us -uc -b"
    echo "debian/ contains: $(ls "$SRC/debian" | tr '\n' ' ')"
    exit 0
fi

# --------------------------------------------------------------------- 4. build
step "4/5  Building (this also runs the unit tests)"
(
    cd "$SRC"
    if [[ -n "$PLUGIN_DIR" ]]; then export TASKSHEET_PLUGIN_DIR="$PLUGIN_DIR"; fi
    dpkg-buildpackage -us -uc -b
)

# ------------------------------------------------------------------ 5. verify
step "5/5  Checking the package"
mkdir -p "$HERE/dist"
DEB="$(ls "$STAGE"/diodon-tasksheet_*.deb | head -1)"
cp "$DEB" "$HERE/dist/"
DEB="$HERE/dist/$(basename "$DEB")"

contents="$(dpkg-deb --contents "$DEB")"
echo "$contents" | awk '{print $1, $6}'
echo "$contents" | grep -q 'libtasksheet\.so'        || die "the package does not contain the plugin library"
echo "$contents" | grep -q 'tasksheet\.plugin'       || die "the package does not contain the plugin descriptor"
echo "$contents" | grep -q 'usr/bin/diodon-tasksheet' || die "the package does not contain the command"
echo
dpkg-deb --field "$DEB" Package Version Architecture Depends Recommends | sed 's/^/  /'
if command -v lintian >/dev/null 2>&1; then
    echo; echo "lintian:"; lintian "$DEB" || true
fi
rm -rf "$STAGE"

cat <<MSG

Built: $DEB

Install:
    sudo apt install $DEB
Then restart Diodon and open its menu -> Tasksheet...:
    pkill -x diodon; diodon &
Keyboard shortcuts (GNOME):
    diodon-tasksheet hotkeys
Remove:
    sudo apt remove diodon-tasksheet
MSG
