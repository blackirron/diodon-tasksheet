# Diodon Tasksheet

A plugin for the [Diodon](https://github.com/diodon-dev/diodon) clipboard
manager that adds a **Tasksheet** next to your clipboard history: a personal
list of words and notes you can keep, copy back, and fill by moving items over
from the clipboard.

* **Clipboard tab** – Diodon's text history. Click a row to paste it.
* **Tasksheet tab** – your own list.
  * type a word and press Enter (or **+**) to add it
  * **trash** button deletes it
  * click a task to copy its text to the clipboard (the task stays)
* **Move from Clipboard to Tasksheet** – press the arrow on a row, or drag the
  row onto the *Tasksheet* tab.
* **Shortcuts** – `Win+V` opens the Clipboard tab, `Win+Y` the Tasksheet tab
  (press again to close).

Tasks are stored in `~/.local/share/diodon/tasksheet.ini`.

## It is a plugin, not a fork

Nothing in Diodon is patched or replaced. The plugin uses only Diodon's public
plugin API and is built *against* an installed Diodon:

| Need | Used |
|------|------|
| lifecycle, appears in *Preferences → Plugins* | `Peas.Activatable` |
| menu entry that survives every menu rebuild | `Controller.add_static_recent_menu_item()` |
| read / paste / remove history | `Controller.get_recent_items()`, `select_item_by_checksum()`, `remove_item()` |
| keyboard shortcuts | a small D-Bus service `org.diodon.Tasksheet` |

Why D-Bus for shortcuts: Diodon dropped its built-in global hotkeys in 1.4.0,
and applications cannot grab global keys on Wayland at all. The desktop owns
the shortcut and runs `diodon-tasksheet clipboard|tasksheet`, which works on
Wayland and X11 alike. Why a separate window instead of tabs in the tray
menu: the tray menu is exported to the shell over D-Bus (dbusmenu) and can
only hold plain menu items.

## Install as a Debian package (recommended)

```bash
bash scripts/build-deb.sh                       # builds dist/diodon-tasksheet_1.0.1_amd64.deb
sudo apt install ./dist/diodon-tasksheet_*.deb   # also restarts a running Diodon for you
diodon-tasksheet hotkeys                         # optional, GNOME: Win+V and Win+Y
```

`build-deb.sh` installs the build packages (one `sudo`), looks at the Diodon
that is installed on the machine — where it keeps its plugins and what its
default plugin list is — builds against it, runs the unit tests, and checks the
resulting package. The package depends on `diodon`, recommends `zeitgeist-core`,
and enables the plugin by default through a GSettings override generated from
Diodon's own schema (so users who never customised their plugin list get it
automatically; others run `diodon-tasksheet enable` or tick it in
*Preferences → Plugins*). Installing or removing the package restarts a Diodon that is already
running, so the Tasksheet tab appears or disappears at once. Shortcuts are
not set automatically, because Win+V is a GNOME default; run
`diodon-tasksheet hotkeys` if you want them. Remove it with
`sudo apt remove diodon-tasksheet`.

A plugin links against `libdiodon`, so build on the same distribution release
you install on. `build-deb.sh --dry-run` shows what would be built.

### Troubleshooting

**`Unable to locate package diodon-dev`**: the package lives in the `universe`
repository on Ubuntu. Run `sudo add-apt-repository universe && sudo apt update`
and build again. `build-deb.sh` also tries the older name `libdiodon-dev`
automatically.

**`Unsupported file ... .deb given on commandline`**: the build did not finish,
so there is no package to install. Scroll up to the first error from
`build-deb.sh`, fix that, and run `ls dist/` before installing.

**Clipboard history fills with half-selected fragments** (`p`, `pt`, `pt ins`
and so on): this is Diodon's own *primary selection* option, not the plugin.
The plugin never changes Diodon's clipboard settings. Put them back to the
defaults with:

```bash
gsettings reset-recursively net.launchpad.Diodon.clipboard
pkill -x diodon; diodon &
```

Or untick *Use primary selection* and *Synchronize clipboards* in Diodon's
Preferences. Then use Clear in Diodon's menu to remove the entries already saved.

`diodon-tasksheet` only accepts `tasksheet`, `clipboard`, `enable`, `disable`
and `hotkeys`.

## Install for one user only (no root, no package)

```bash
sudo apt install diodon diodon-dev libgtk-3-dev libpeas-dev valac meson ninja-build zeitgeist-core
bash scripts/install.sh
pkill -x diodon; diodon &
```

`install.sh` builds the plugin, runs the unit tests, installs it for **your
user only** (`~/.local/share/diodon/plugins/tasksheet`, no root), and enables it
in Diodon's settings. Then click Diodon's menu → **Tasksheet…**
(or *Diodon → Preferences → Plugins* to toggle it).

Diodon built from source into its own prefix:
`bash scripts/install.sh --diodon-prefix /path/to/prefix`.

### Try it without touching your system Diodon

```bash
bash test-install.sh
```

Builds an unmodified Diodon into `~/diodon-tasksheet-test`, installs the plugin
into it and starts it. Delete that folder to undo.

### Keyboard shortcuts

```bash
diodon-tasksheet hotkeys               # GNOME: Win+V and Win+Y
diodon-tasksheet hotkeys --undo
```

GNOME uses `Win+V` for the notification list; the script releases it (and any
other binding of these keys), registers the shortcuts, verifies them, and
remembers what it changed for `--undo`. On other desktops (XFCE, KDE, …)
create two custom shortcuts running `diodon-tasksheet clipboard` and
`diodon-tasksheet tasksheet`. Diodon must be running.

### The `diodon-tasksheet` command

| command | does |
|---------|------|
| `tasksheet` (default) / `clipboard` | open or close that tab |
| `enable` / `disable` | add / remove the plugin in your Diodon settings |
| `hotkeys [--undo]` | set up / remove the GNOME shortcuts |

See `man diodon-tasksheet`.

### Uninstall

```bash
bash scripts/uninstall.sh            # keeps your tasks
bash scripts/uninstall.sh --purge    # also deletes them
```

## Requirements and limits

* Same platform as Diodon: GTK 3, libpeas, Zeitgeist (Diodon stores its
  history there – without the `zeitgeist-core` service the Clipboard tab says
  so instead of showing an empty list).
* **Wayland:** Diodon is an X11 program and cannot reliably see text copied in
  Wayland-native applications, so on Wayland the Clipboard tab may stay empty.
  That is a Diodon limitation, not this plugin's. The Tasksheet tab, shortcuts
  and the menu entry work regardless; use an Xorg session for clipboard
  history. Wayland also ignores window positions requested by applications, so
  the popup opens where the compositor puts it.
* Only text items are listed in the Clipboard tab.

## Development

```bash
meson setup build -Dplugin_dir=$PWD/build/plugin -Dbin_dir=$PWD/build/bin
meson compile -C build
meson test -C build --print-errorlogs     # storage + label unit tests, no display needed
```

Layout: `src/` plugin sources (`tasksheet-storage.vala` is plain GLib and unit
tested; `tasksheet-popup.vala` is the GTK window; `tasksheet-plugin.vala` is the
Peas entry point that registers the menu entry and the shortcut service) · `tests/` · `scripts/` ·
`bin/diodon-tasksheet.in` · `data/` (plugin descriptor, man page) · `debian/`.

## License

GPL-2.0-or-later, the same as Diodon.
