## Diodon Tasksheet 1.0.1

A Tasksheet tab for the Diodon clipboard manager: a personal list of words and
notes that sits next to your clipboard history. Move items over with a button
or by drag and drop, type tasks in directly, click one to copy it back.

**What is new in 1.0.1**
* The list updates instantly when you add, delete or move a task.
* The build no longer fails on Debian and Ubuntu over the `diodon-dev` package name.
* Installing or removing the .deb restarts a running Diodon for you.

**Install**
* Debian or Ubuntu with Diodon 1.13: download the .deb below, then
  `sudo apt install ./diodon-tasksheet_1.0.1_amd64.deb`
* Anything else: download the source and run `bash scripts/install.sh`

The .deb is built against Diodon 1.13 on Ubuntu, so on another release it is
safer to build it yourself with `bash scripts/build-deb.sh`.

Keyboard shortcuts are optional: `diodon-tasksheet hotkeys` (GNOME, Win+V and Win+Y).

Full list of changes in `CHANGELOG.md`.
