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
     * The D-Bus interface. Kept as a separate tiny class so that only
     * these two calls are exported on the bus - every public method of a
     * [DBus] class would be.
     */
    [DBus (name = "org.diodon.Tasksheet")]
    internal class DBusApi : GLib.Object
    {
        private Popup popup;

        public DBusApi(Popup popup)
        {
            this.popup = popup;
        }

        public void show_clipboard() throws GLib.Error
        {
            popup.toggle_popup(Tab.CLIPBOARD, false);
        }

        public void show_tasksheet() throws GLib.Error
        {
            popup.toggle_popup(Tab.TASKSHEET, false);
        }
    }

    /**
     * Lets desktop keyboard shortcuts open the popup. Diodon removed its
     * own global hotkeys in 1.4.0 (and applications cannot grab global
     * keys on Wayland at all), so the desktop owns the shortcut and runs
     * a command - see bin/diodon-tasksheet:
     *
     *   diodon-tasksheet clipboard    open/close the Clipboard tab
     *   diodon-tasksheet tasksheet    open/close the Tasksheet tab
     */
    public class Service : GLib.Object
    {
        private const string BUS_NAME = "org.diodon.Tasksheet";
        private const string OBJECT_PATH = "/org/diodon/Tasksheet";

        private DBusApi api;
        private GLib.DBusConnection? connection = null;
        private uint owner_id = 0;
        private uint registration_id = 0;

        public Service(Popup popup)
        {
            this.api = new DBusApi(popup);
        }

        public void start()
        {
            if(owner_id != 0) {
                return;
            }

            owner_id = GLib.Bus.own_name(GLib.BusType.SESSION, BUS_NAME,
                GLib.BusNameOwnerFlags.NONE, on_bus_acquired, null, on_name_lost);
        }

        public void stop()
        {
            if(connection != null && registration_id != 0) {
                connection.unregister_object(registration_id);
                registration_id = 0;
            }
            if(owner_id != 0) {
                GLib.Bus.unown_name(owner_id);
                owner_id = 0;
            }
            connection = null;
        }

        private void on_bus_acquired(GLib.DBusConnection conn, string name)
        {
            try {
                registration_id = conn.register_object(OBJECT_PATH, api);
                connection = conn;
            } catch(GLib.Error e) {
                warning("Tasksheet: could not register %s on the session bus: %s",
                    OBJECT_PATH, e.message);
            }
        }

        private void on_name_lost(GLib.DBusConnection? conn, string name)
        {
            warning("Tasksheet: could not own D-Bus name %s (is another instance running?). "
                + "Keyboard shortcuts will not work.", name);
        }
    }
}
