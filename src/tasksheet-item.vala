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
     * One entry on the tasksheet: a word, phrase or note. Independent of
     * Diodon's clipboard items on purpose - it may be typed directly and
     * only ever carries plain text.
     */
    public class Item : GLib.Object
    {
        private string _id;
        private string _text;
        private DateTime _created;

        /**
         * Stable identifier. Not a content checksum: two tasks with the
         * same text must stay distinguishable.
         */
        public string id { get { return _id; } }

        public string text { get { return _text; } }

        public DateTime created { get { return _created; } }

        public Item(string id, string text, DateTime created)
        {
            this._id = id;
            this._text = text;
            this._created = created;
        }

        /**
         * Create a new task from plain text with a freshly generated id.
         */
        public static Item from_text(string text)
        {
            string id = "%s-%08x".printf(GLib.get_real_time().to_string(),
                GLib.Random.next_int());
            return new Item(id, text, new DateTime.now_utc());
        }

        /**
         * First line of the task, shortened to max_length characters.
         * Counts characters (not bytes) so multibyte scripts such as
         * Devanagari are never cut inside a code point.
         */
        public string get_label(int max_length = 60)
        {
            string label = text.strip();

            int newline_index = label.index_of("\n");
            if(newline_index > -1) {
                label = label.substring(0, newline_index);
            }

            if(label.char_count() > max_length) {
                label = label.substring(0, label.index_of_nth_char(max_length)) + "…";
            }

            return label;
        }
    }
}
