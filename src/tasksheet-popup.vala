/*
 * Diodon Tasksheet - a tasksheet plugin for the Diodon clipboard manager.
 * Copyright (C) 2026 Samir Pravin Nimgade
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
 * License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

namespace Tasksheet
{
    /**
     * The two tabs of the popup. Values are the notebook page numbers.
     */
    public enum Tab
    {
        CLIPBOARD = 0,
        TASKSHEET = 1
    }

    /**
     * A list row that remembers which clipboard checksum / task id it
     * represents, so row activation can find the backing object.
     */
    internal class PopupRow : Gtk.ListBoxRow
    {
        public string key;

        public PopupRow(string key)
        {
            this.key = key;
        }
    }

    /**
     * Tabbed popup (Clipboard / Tasksheet).
     *
     * Clipboard tab: Diodon's text history. Click a row to paste it.
     * Tasksheet tab: a personal list of words/notes. Type one and press
     * Enter (or the + button) to add it; the trash button deletes it;
     * clicking a task copies its text to the clipboard (the task stays).
     *
     * Items move from the clipboard to the tasksheet: drag a row onto the
     * Tasksheet tab (or hover the tab, then drop in the list), or press the
     * arrow button on the row.
     *
     * It is a real window, not part of the tray menu, because the tray
     * menu is exported to the desktop shell over D-Bus (dbusmenu) and can
     * only contain plain menu items.
     */
    public class Popup : Gtk.Window
    {
        private const Gtk.TargetEntry[] CLIPBOARD_TARGETS = {
            { "diodon-clipboard-item", Gtk.TargetFlags.SAME_APP, 0 }
        };

        private Diodon.Controller controller;
        private Storage storage;

        private Gtk.Notebook notebook;
        private Gtk.ListBox clipboard_list;
        private Gtk.ListBox tasksheet_list;
        private Gtk.Label clipboard_placeholder;
        private Gtk.Entry task_entry;

        private GLib.HashTable<string, Diodon.IClipboardItem> clipboard_items;
        private GLib.HashTable<string, Item> tasks;

        // History is fetched asynchronously; a newer refresh makes older
        // results stale and they are dropped.
        private uint clipboard_generation = 0;

        // While a drag is running the window must not auto-hide.
        private bool dragging = false;

        public Popup(Diodon.Controller controller, Storage storage)
        {
            this.controller = controller;
            this.storage = storage;
            this.clipboard_items =
                new GLib.HashTable<string, Diodon.IClipboardItem>(GLib.str_hash, GLib.str_equal);
            this.tasks =
                new GLib.HashTable<string, Item>(GLib.str_hash, GLib.str_equal);

            build_ui();

            controller.on_recent_menu_changed.connect((menu) => { refresh_clipboard_tab.begin(); });
            storage.on_item_added.connect((task) => { refresh_tasksheet_tab(); });
            storage.on_item_removed.connect((task) => { refresh_tasksheet_tab(); });

            refresh_clipboard_tab.begin();
            refresh_tasksheet_tab();
        }

        /**
         * Show the popup on the given tab.
         *
         * @param tab which tab to open
         * @param at_pointer open at the mouse pointer (menu click) instead
         *        of the screen center (keyboard shortcut). Wayland ignores
         *        positions requested by applications.
         */
        public void show_popup(Tab tab = Tab.CLIPBOARD, bool at_pointer = true)
        {
            dragging = false;
            refresh_clipboard_tab.begin();
            refresh_tasksheet_tab();

            set_position(at_pointer ? Gtk.WindowPosition.MOUSE : Gtk.WindowPosition.CENTER);
            show_all();
            notebook.page = (int) tab;
            present();

            if(tab == Tab.TASKSHEET) {
                task_entry.grab_focus();
            }
        }

        /**
         * Keyboard-shortcut behaviour: pressing the shortcut for the tab
         * that is already showing closes the popup.
         */
        public void toggle_popup(Tab tab, bool at_pointer = false)
        {
            if(visible && notebook.page == (int) tab) {
                hide();
            } else {
                show_popup(tab, at_pointer);
            }
        }

        private void build_ui()
        {
            // A normal (focusable) undecorated utility window rather than a
            // POPUP_MENU hint: popup-hinted windows bypass the window
            // manager and often never receive keyboard focus, which would
            // break Escape and click-away dismissal.
            set_type_hint(Gdk.WindowTypeHint.UTILITY);
            set_decorated(false);
            set_skip_taskbar_hint(true);
            set_skip_pager_hint(true);
            set_keep_above(true);
            set_resizable(false);
            set_size_request(340, 440);

            Gtk.Frame frame = new Gtk.Frame(null);
            frame.shadow_type = Gtk.ShadowType.OUT;
            add(frame);

            notebook = new Gtk.Notebook();
            frame.add(notebook);

            Gtk.Button close_button = new Gtk.Button.from_icon_name(
                "window-close-symbolic", Gtk.IconSize.MENU);
            close_button.relief = Gtk.ReliefStyle.NONE;
            close_button.tooltip_text = _("Close");
            close_button.clicked.connect(() => { hide(); });
            close_button.show();
            notebook.set_action_widget(close_button, Gtk.PackType.END);

            // --- Clipboard tab ---
            clipboard_placeholder = create_placeholder(default_clipboard_placeholder());
            clipboard_list = create_list(clipboard_placeholder);
            Gtk.ScrolledWindow clipboard_scroll = create_scroller(clipboard_list);
            notebook.append_page(clipboard_scroll, create_tab_label(_("Clipboard")));

            // --- Tasksheet tab: entry + add button on top, list below ---
            tasksheet_list = create_list(create_placeholder(
                _("No tasks yet.\nType one above, or move items here from the Clipboard tab.")));
            Gtk.ScrolledWindow tasksheet_scroll = create_scroller(tasksheet_list);

            task_entry = new Gtk.Entry();
            task_entry.placeholder_text = _("Add a word or task");
            task_entry.hexpand = true;
            task_entry.activate.connect(add_task_from_entry);

            Gtk.Button add_button = new Gtk.Button.from_icon_name(
                "list-add-symbolic", Gtk.IconSize.BUTTON);
            add_button.tooltip_text = _("Add to tasksheet");
            add_button.clicked.connect(add_task_from_entry);

            Gtk.Box entry_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            entry_row.margin = 6;
            entry_row.pack_start(task_entry, true, true, 0);
            entry_row.pack_start(add_button, false, false, 0);

            Gtk.Box tasksheet_page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            tasksheet_page.pack_start(entry_row, false, false, 0);
            tasksheet_page.pack_start(tasksheet_scroll, true, true, 0);

            Gtk.EventBox tasksheet_tab = create_tab_label(_("Tasksheet"));
            notebook.append_page(tasksheet_page, tasksheet_tab);

            // Drop targets: the tab header (drop straight onto it) and the
            // visible list area (after hovering the tab switched to it).
            enable_drop(tasksheet_tab);
            enable_drop(tasksheet_scroll);

            clipboard_list.row_activated.connect(on_clipboard_row_activated);
            tasksheet_list.row_activated.connect(on_tasksheet_row_activated);

            key_press_event.connect(on_key_press);
            focus_out_event.connect(on_focus_out);

            // Closing from the window manager only hides: the plugin keeps
            // a single instance and shows it again later.
            delete_event.connect(() => { hide(); return true; });
        }

        private string default_clipboard_placeholder()
        {
            return _("No text items in the clipboard history yet.\nCopy some text and it appears here.");
        }

        private Gtk.Label create_placeholder(string text)
        {
            Gtk.Label placeholder = new Gtk.Label(text);
            placeholder.margin = 24;
            placeholder.wrap = true;
            placeholder.justify = Gtk.Justification.CENTER;
            placeholder.sensitive = false;
            placeholder.show();
            return placeholder;
        }

        private Gtk.ListBox create_list(Gtk.Label placeholder)
        {
            Gtk.ListBox list = new Gtk.ListBox();
            list.selection_mode = Gtk.SelectionMode.NONE;
            list.activate_on_single_click = true;
            list.set_placeholder(placeholder);
            return list;
        }

        private Gtk.ScrolledWindow create_scroller(Gtk.Widget child)
        {
            Gtk.ScrolledWindow scroller = new Gtk.ScrolledWindow(null, null);
            scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scroller.add(child);
            return scroller;
        }

        private Gtk.EventBox create_tab_label(string text)
        {
            // Labels have no window and cannot receive drops, so the label
            // is wrapped in an invisible EventBox.
            Gtk.EventBox box = new Gtk.EventBox();
            box.visible_window = false;
            box.add(new Gtk.Label(text));
            box.show_all();
            return box;
        }

        private void enable_drop(Gtk.Widget widget)
        {
            // DestDefaults.ALL makes GTK request the data and call
            // drag_finish itself, so the handler must not call it again.
            Gtk.drag_dest_set(widget, Gtk.DestDefaults.ALL, CLIPBOARD_TARGETS, Gdk.DragAction.MOVE);

            widget.drag_data_received.connect((context, x, y, data, info, time) => {
                dragging = false;

                if(data.get_length() <= 0) {
                    return;
                }

                move_clipboard_item_to_tasksheet((string) data.get_data());
            });
        }

        private bool on_key_press(Gdk.EventKey event)
        {
            if(event.keyval == Gdk.Key.Escape) {
                hide();
                return true;
            }
            return false;
        }

        private bool on_focus_out(Gdk.EventFocus event)
        {
            if(!dragging) {
                hide();
            }
            return false;
        }

        private void add_task_from_entry()
        {
            string text = task_entry.text.strip();
            if(text == "") {
                return;
            }

            storage.add(Item.from_text(text));
            task_entry.text = "";
            task_entry.grab_focus();
        }

        private Gtk.Label create_row_label(string label_text, string tooltip)
        {
            Gtk.Label label = new Gtk.Label(label_text);
            label.xalign = 0;
            label.margin = 6;
            label.hexpand = true;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.tooltip_text = tooltip;
            return label;
        }

        private Gtk.Button create_row_button(string icon_name, string tooltip)
        {
            Gtk.Button button = new Gtk.Button.from_icon_name(icon_name, Gtk.IconSize.MENU);
            button.relief = Gtk.ReliefStyle.NONE;
            button.tooltip_text = tooltip;
            return button;
        }

        /**
         * Wrap row content in an EventBox that acts as the drag source;
         * list rows have no window of their own to start a drag from.
         */
        private Gtk.EventBox create_drag_handle(Gtk.Widget content, string key)
        {
            Gtk.EventBox handle = new Gtk.EventBox();
            handle.visible_window = false;
            handle.add(content);

            Gtk.drag_source_set(handle, Gdk.ModifierType.BUTTON1_MASK,
                CLIPBOARD_TARGETS, Gdk.DragAction.MOVE);
            Gtk.drag_source_set_icon_name(handle, "text-x-generic");

            handle.drag_begin.connect((context) => { dragging = true; });
            handle.drag_end.connect((context) => { dragging = false; });
            handle.drag_data_get.connect((context, data, info, time) => {
                data.set(data.get_target(), 8, key.data);
            });

            return handle;
        }

        private Gtk.ListBoxRow build_clipboard_row(Diodon.IClipboardItem item)
        {
            string checksum = item.get_checksum();

            Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            box.pack_start(create_row_label(item.get_label(), shorten(item.get_text())),
                true, true, 0);

            Gtk.Button move_button = create_row_button("go-next-symbolic", _("Move to tasksheet"));
            move_button.clicked.connect(() => { move_clipboard_item_to_tasksheet(checksum); });
            box.pack_start(move_button, false, false, 0);

            PopupRow row = new PopupRow(checksum);
            row.add(create_drag_handle(box, checksum));
            return row;
        }

        private Gtk.ListBoxRow build_task_row(Item task)
        {
            string task_id = task.id;

            Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            box.pack_start(create_row_label(task.get_label(), shorten(task.text)),
                true, true, 0);

            Gtk.Button delete_button = create_row_button("edit-delete-symbolic", _("Delete"));
            delete_button.clicked.connect(() => { storage.remove(task_id); });
            box.pack_start(delete_button, false, false, 0);

            PopupRow row = new PopupRow(task_id);
            row.add(box);
            return row;
        }

        private async void refresh_clipboard_tab()
        {
            uint generation = ++clipboard_generation;

            GLib.List<Diodon.IClipboardItem> items;
            try {
                Diodon.ClipboardCategory[] categories = { Diodon.ClipboardCategory.TEXT };
                items = yield controller.get_recent_items(categories, Diodon.ClipboardTimerange.ALL);
            } catch(GLib.Error e) {
                warning("Tasksheet popup could not load clipboard history: %s", e.message);
                if(generation == clipboard_generation) {
                    // Say why the list is empty instead of pretending it is.
                    clipboard_placeholder.label = _("Clipboard history is unavailable:\n%s\n\nDiodon keeps its history in the Zeitgeist service. Is it installed and running?").printf(e.message);
                }
                return;
            }

            if(generation != clipboard_generation) {
                return; // a newer refresh is already in flight
            }

            clipboard_placeholder.label = default_clipboard_placeholder();

            // Clear and repopulate in one uninterrupted step, so two
            // overlapping refreshes can never interleave and duplicate rows.
            foreach(Gtk.Widget child in clipboard_list.get_children()) {
                clipboard_list.remove(child);
            }
            clipboard_items.remove_all();

            foreach(Diodon.IClipboardItem item in items) {
                clipboard_items.set(item.get_checksum(), item);
                clipboard_list.insert(build_clipboard_row(item), -1);
            }

            clipboard_list.show_all();
        }

        private void refresh_tasksheet_tab()
        {
            foreach(Gtk.Widget child in tasksheet_list.get_children()) {
                tasksheet_list.remove(child);
            }
            tasks.remove_all();

            foreach(Item task in storage.get_all()) {
                tasks.set(task.id, task);
                tasksheet_list.insert(build_task_row(task), -1);
            }

            tasksheet_list.show_all();
        }

        /**
         * Click on a clipboard row: select the item exactly like the
         * regular Diodon menu does (copy to clipboard, paste if enabled).
         */
        private void on_clipboard_row_activated(Gtk.ListBoxRow row)
        {
            PopupRow? popup_row = row as PopupRow;
            if(popup_row == null) {
                return;
            }

            hide();
            controller.select_item_by_checksum.begin(popup_row.key);
        }

        /**
         * Click on a task row: copy its text to the system clipboard and
         * keep the task. Non-destructive on purpose: a stray click must
         * never delete a task.
         */
        private void on_tasksheet_row_activated(Gtk.ListBoxRow row)
        {
            PopupRow? popup_row = row as PopupRow;
            if(popup_row == null) {
                return;
            }

            Item? task = tasks.get(popup_row.key);
            if(task == null) {
                return;
            }

            Gtk.Clipboard.get_default(Gdk.Display.get_default()).set_text(task.text, -1);
            hide();
        }

        /**
         * Move a clipboard item to the tasksheet: add it as a task, then
         * remove it from clipboard history. Used by the row button and the
         * drop handler so both paths behave identically.
         */
        private void move_clipboard_item_to_tasksheet(string checksum)
        {
            Diodon.IClipboardItem? item = clipboard_items.get(checksum);
            if(item == null) {
                return;
            }

            storage.add(Item.from_text(item.get_text()));
            controller.remove_item.begin(item);
        }

        private string shorten(string text)
        {
            // Tooltip text only; counts characters so multibyte text is safe.
            const int MAX = 400;
            if(text.char_count() <= MAX) {
                return text;
            }
            return text.substring(0, text.index_of_nth_char(MAX)) + "…";
        }
    }
}
