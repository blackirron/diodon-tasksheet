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
     * The Diodon plugin: adds a "Tasksheet…" entry to Diodon's menu and
     * starts the keyboard-shortcut service. It uses only Diodon's public
     * plugin API:
     *
     *   - Peas.Activatable for the lifecycle,
     *   - Controller.add_static_recent_menu_item() for the menu entry.
     *     Diodon re-adds static items to every rebuilt menu by itself, so
     *     the entry works with any indicator and also in the menu that
     *     opens when you run `diodon`.
     *
     * No Diodon source file is modified or replaced.
     */
    public class Plugin : Peas.ExtensionBase, Peas.Activatable
    {
        private Storage storage;
        private Popup popup;
        private Service service;
        private Gtk.MenuItem menu_item;

        public GLib.Object object { owned get; construct; }

        public Plugin()
        {
            GLib.Object();
        }

        public void activate()
        {
            Diodon.Controller controller = object as Diodon.Controller;

            if(popup != null) {
                return;
            }

            storage = new Storage();
            popup = new Popup(controller, storage);

            service = new Service(popup);
            service.start();

            menu_item = new Gtk.MenuItem.with_label(_("Tasksheet…"));
            menu_item.activate.connect(() => { popup.show_popup(Tab.TASKSHEET, true); });
            menu_item.show();
            controller.add_static_recent_menu_item.begin(menu_item);
        }

        public void deactivate()
        {
            Diodon.Controller controller = object as Diodon.Controller;

            if(menu_item != null) {
                controller.remove_static_recent_menu_item.begin(menu_item);
                menu_item = null;
            }

            if(service != null) {
                service.stop();
                service = null;
            }

            if(popup != null) {
                popup.destroy();
                popup = null;
            }

            storage = null;
        }

        public void update_state()
        {
        }
    }
}

[ModuleInit]
public void peas_register_types(GLib.TypeModule module)
{
    Peas.ObjectModule objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Peas.Activatable),
        typeof(Tasksheet.Plugin));
}
