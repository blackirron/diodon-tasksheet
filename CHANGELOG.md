# Changelog

## 1.0.1 (2026-10-23)

Fixed
* The Tasksheet tab now updates the moment you add, delete or move a task.
  Before, the list only refreshed after you closed and reopened the popup,
  because Diodon rejected the plugin's change signals when it loaded the
  plugin. The signals now carry the task id instead of the task object.
* Building the package on Debian and Ubuntu no longer fails with
  "Unable to locate package libdiodon-dev". The development package is called
  `diodon-dev` there, and the build script picks whichever name exists.

Added
* Installing the .deb restarts a Diodon that is already running, so the
  Tasksheet tab shows up without a logout. Removing the package does the same
  so the tab goes away at once.
* A troubleshooting section in the README, a screenshot, and notes for
  distributions other than Debian and Ubuntu.
* `COPYING` with the GPL text.

## 1.0.0

First version: Clipboard and Tasksheet tabs, drag and drop from the clipboard
to the tasksheet, keyboard shortcuts through D-Bus, a Debian package and a
per-user install script.
