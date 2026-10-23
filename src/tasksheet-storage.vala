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
     * Persists tasks in a small KeyFile, by default
     * $XDG_DATA_HOME/diodon/tasksheet.ini.
     *
     * Plain GLib only (no Gtk, no Diodon) so it can be unit tested on
     * its own. Everything is synchronous: a few dozen KeyFile rows do not
     * justify async machinery.
     */
    public class Storage : GLib.Object
    {
        private const string GROUP_META = "Tasksheet";
        private const string KEY_COUNT = "count";
        private const string KEY_ID = "id";
        private const string KEY_TEXT = "text";
        private const string KEY_CREATED = "created_unix";

        private string file_path;
        private GLib.List<Item> items;

        /**
         * Emitted after a task has been added and saved. It carries the
         * task id and not the Item itself: Diodon rejects a signal whose
         * parameter is a class defined inside the plugin module.
         */
        public signal void on_item_added(string id);

        /**
         * Emitted after a task has been removed and saved (carries the id).
         */
        public signal void on_item_removed(string id);

        public Storage()
        {
            string dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "diodon");
            this.with_file(GLib.Path.build_filename(dir, "tasksheet.ini"));
        }

        public Storage.with_file(string file_path)
        {
            this.file_path = file_path;
            this.items = new GLib.List<Item>();
            load();
        }

        /**
         * Snapshot of all tasks, oldest first. The list is a private
         * copy, so it is safe to iterate while storage changes.
         */
        public GLib.List<Item> get_all()
        {
            GLib.List<Item> snapshot = new GLib.List<Item>();
            foreach(Item task in items) {
                snapshot.append(task);
            }
            return snapshot;
        }

        public void add(Item task)
        {
            items.append(task);
            save();
            on_item_added(task.id);
        }

        /**
         * Remove a task by id. No-op if it is already gone.
         */
        public void remove(string id)
        {
            Item? found = null;
            foreach(Item task in items) {
                if(task.id == id) {
                    found = task;
                    break;
                }
            }

            if(found == null) {
                return;
            }

            items.remove(found);
            save();
            on_item_removed(found.id);
        }

        private void load()
        {
            GLib.KeyFile key_file = new GLib.KeyFile();

            try {
                key_file.load_from_file(file_path, GLib.KeyFileFlags.NONE);
            } catch(GLib.FileError e) {
                return; // nothing saved yet: an empty tasksheet is the normal start
            } catch(GLib.KeyFileError e) {
                warning("Tasksheet file %s is unreadable, starting empty: %s",
                    file_path, e.message);
                return;
            }

            int count = 0;
            try {
                count = key_file.get_integer(GROUP_META, KEY_COUNT);
            } catch(GLib.KeyFileError e) {
                return;
            }

            for(int i = 0; i < count; i++) {
                string group = "Task%d".printf(i);
                try {
                    string id = key_file.get_string(group, KEY_ID);
                    string text = key_file.get_string(group, KEY_TEXT);
                    int64 created_unix = key_file.get_int64(group, KEY_CREATED);

                    items.append(new Item(id, text, new DateTime.from_unix_utc(created_unix)));
                } catch(GLib.KeyFileError e) {
                    warning("Skipping malformed tasksheet entry %s: %s", group, e.message);
                }
            }
        }

        private void save()
        {
            GLib.KeyFile key_file = new GLib.KeyFile();
            key_file.set_integer(GROUP_META, KEY_COUNT, (int) items.length());

            int i = 0;
            foreach(Item task in items) {
                string group = "Task%d".printf(i);
                key_file.set_string(group, KEY_ID, task.id);
                key_file.set_string(group, KEY_TEXT, task.text);
                key_file.set_int64(group, KEY_CREATED, task.created.to_unix());
                i++;
            }

            try {
                GLib.DirUtils.create_with_parents(GLib.Path.get_dirname(file_path), 0700);
                // set_contents writes a temp file and renames it, so a
                // crash mid-save cannot leave a half-written tasksheet.
                GLib.FileUtils.set_contents(file_path, key_file.to_data());
            } catch(GLib.Error e) {
                warning("Could not save tasksheet to %s: %s", file_path, e.message);
            }
        }
    }
}
