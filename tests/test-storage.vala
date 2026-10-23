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

// A fresh scratch file for every test, so tests cannot affect each other
// or the real ~/.local/share/diodon/tasksheet.ini.
string scratch_file()
{
    try {
        string dir = GLib.DirUtils.make_tmp("tasksheet-test-XXXXXX");
        return GLib.Path.build_filename(dir, "tasksheet.ini");
    } catch(GLib.FileError e) {
        error("cannot create scratch directory: %s", e.message);
    }
}

void test_roundtrip()
{
    string file = scratch_file();

    Tasksheet.Storage first = new Tasksheet.Storage.with_file(file);
    assert(first.get_all().length() == 0);

    first.add(Tasksheet.Item.from_text("alpha"));
    first.add(Tasksheet.Item.from_text("हिन्दी वाक्य and émoji 🙂"));
    first.add(Tasksheet.Item.from_text("line one\nline two = [odd]; chars"));

    // A second instance reading the same file must see identical tasks.
    Tasksheet.Storage second = new Tasksheet.Storage.with_file(file);
    GLib.List<Tasksheet.Item> loaded = second.get_all();
    assert(loaded.length() == 3);
    assert(loaded.nth_data(0).text == "alpha");
    assert(loaded.nth_data(1).text == "हिन्दी वाक्य and émoji 🙂");
    assert(loaded.nth_data(2).text == "line one\nline two = [odd]; chars");
}

void test_remove_and_signals()
{
    Tasksheet.Storage storage = new Tasksheet.Storage.with_file(scratch_file());

    int added = 0;
    int removed = 0;
    storage.on_item_added.connect((task) => { added++; });
    storage.on_item_removed.connect((task) => { removed++; });

    Tasksheet.Item keep = Tasksheet.Item.from_text("keep me");
    Tasksheet.Item drop = Tasksheet.Item.from_text("drop me");
    storage.add(keep);
    storage.add(drop);
    assert(added == 2);

    storage.remove(drop.id);
    assert(removed == 1);
    assert(storage.get_all().length() == 1);
    assert(storage.get_all().nth_data(0).id == keep.id);

    // Removing an unknown id must be a harmless no-op.
    storage.remove("does-not-exist");
    assert(removed == 1);
    assert(storage.get_all().length() == 1);
}

void test_same_text_stays_distinct()
{
    Tasksheet.Storage storage = new Tasksheet.Storage.with_file(scratch_file());

    Tasksheet.Item a = Tasksheet.Item.from_text("Follow up");
    Tasksheet.Item b = Tasksheet.Item.from_text("Follow up");
    assert(a.id != b.id);

    storage.add(a);
    storage.add(b);
    storage.remove(a.id);

    assert(storage.get_all().length() == 1);
    assert(storage.get_all().nth_data(0).id == b.id);
}

void test_corrupt_file_starts_empty()
{
    string file = scratch_file();
    try {
        GLib.FileUtils.set_contents(file, "this is [not a valid\nkey file at all");
    } catch(GLib.FileError e) {
        error("cannot write scratch file: %s", e.message);
    }

    // Must not crash; a broken file simply yields an empty tasksheet.
    // (The warning it logs is expected, so do not treat it as fatal.)
    GLib.Test.expect_message(null, GLib.LogLevelFlags.LEVEL_WARNING, "*unreadable*");
    Tasksheet.Storage storage = new Tasksheet.Storage.with_file(file);
    GLib.Test.assert_expected_messages();
    assert(storage.get_all().length() == 0);
}

void test_label_is_character_safe()
{
    // 100 Devanagari characters (3 bytes each) must be cut on a character
    // boundary, never in the middle of a code point.
    string long_text = string.joinv("", new string[] { "अ", "ब", "क", "द", "ग" });
    string text = "";
    for(int i = 0; i < 20; i++) {
        text += long_text;
    }

    Tasksheet.Item task = Tasksheet.Item.from_text(text);
    string label = task.get_label(10);

    assert(label.validate());
    assert(label.has_suffix("…"));
    assert(label.char_count() == 11); // 10 characters + the ellipsis

    // Short text and multi-line text.
    assert(Tasksheet.Item.from_text("short").get_label() == "short");
    assert(Tasksheet.Item.from_text("first line\nsecond line").get_label() == "first line");
}

int main(string[] args)
{
    GLib.Test.init(ref args);

    GLib.Test.add_func("/tasksheet/storage/roundtrip", test_roundtrip);
    GLib.Test.add_func("/tasksheet/storage/remove-and-signals", test_remove_and_signals);
    GLib.Test.add_func("/tasksheet/storage/same-text-stays-distinct", test_same_text_stays_distinct);
    GLib.Test.add_func("/tasksheet/storage/corrupt-file", test_corrupt_file_starts_empty);
    GLib.Test.add_func("/tasksheet/task/label-character-safe", test_label_is_character_safe);

    return GLib.Test.run();
}
