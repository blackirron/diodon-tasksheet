# Diodon Tasksheet - a tasksheet plugin for the Diodon clipboard manager.
#
# Builds OUTSIDE the Diodon source tree against an installed Diodon
# (Ubuntu/Debian: package diodon-dev; from source: its install prefix).
#
#   meson setup build -Dplugin_dir=$HOME/.local/share/diodon/plugins/tasksheet
#   meson compile -C build
#   meson test -C build
#   meson install -C build
#
# scripts/install.sh does all of this for you.

project('diodon-tasksheet', ['c', 'vala'],
    version: '1.0.1',
    license: 'GPL-2.0-or-later',
    meson_version: '>= 0.56.0')

glib_dep    = dependency('glib-2.0', version: '>= 2.40')
gobject_dep = dependency('gobject-2.0')
gio_dep     = dependency('gio-2.0')
gtk_dep     = dependency('gtk+-3.0', version: '>= 3.10')  # Gtk.ListBox needs 3.10
libpeas_dep = dependency('libpeas-1.0')
diodon_dep  = dependency('diodon')

# valac must find diodon.vapi, which Diodon installs to <prefix>/share/vala/vapi.
vapidir = get_option('diodon_vapidir')
if vapidir == ''
    diodon_prefix = diodon_dep.get_variable(pkgconfig: 'prefix', default_value: '/usr')
    vapidir = join_paths(diodon_prefix, 'share', 'vala', 'vapi')
endif
add_project_arguments('--vapidir', vapidir, language: 'vala')

# Diodon installs diodon.h into <includedir>/diodon/, but its .pc file only
# adds <includedir>, so the generated C code could not find it.
diodon_includedir = get_option('diodon_includedir')
if diodon_includedir == ''
    diodon_includedir = join_paths(
        diodon_dep.get_variable(pkgconfig: 'includedir', default_value: '/usr/include'),
        'diodon')
endif
add_project_arguments('-I' + diodon_includedir, language: 'c')

# Needed by _() (glib/gi18n-lib.h).
add_project_arguments('-DGETTEXT_PACKAGE="diodon-tasksheet"', language: 'c')

plugin_dir = get_option('plugin_dir')
if plugin_dir == ''
    plugin_dir = join_paths(get_option('prefix'), get_option('libdir'),
        'diodon', 'plugins', 'tasksheet')
endif

bin_dir = get_option('bin_dir')
if bin_dir == ''
    bin_dir = join_paths(get_option('prefix'), get_option('bindir'))
endif

# Architecture-independent helper scripts (Debian: /usr/lib/diodon-tasksheet).
libexec_dir = get_option('libexec_dir')
if libexec_dir == ''
    libexec_dir = join_paths(get_option('prefix'), 'lib', 'diodon-tasksheet')
endif

shared_library('tasksheet',
    [
        'src/tasksheet-item.vala',
        'src/tasksheet-storage.vala',
        'src/tasksheet-popup.vala',
        'src/tasksheet-service.vala',
        'src/tasksheet-plugin.vala',
    ],
    dependencies: [
        glib_dep,
        gobject_dep,
        gio_dep,
        gtk_dep,
        libpeas_dep,
        diodon_dep,
    ],
    install: true,
    install_dir: plugin_dir,
)

install_data('data/tasksheet.plugin', install_dir: plugin_dir)
# The command-line helper learns where its sibling scripts were installed.
helper_conf = configuration_data()
helper_conf.set('LIBEXECDIR', libexec_dir)
helper = configure_file(
    input: 'bin/diodon-tasksheet.in',
    output: 'diodon-tasksheet',
    configuration: helper_conf)
install_data(helper,
    install_dir: bin_dir,
    install_mode: 'rwxr-xr-x')
install_data('scripts/setup-hotkeys.sh',
    install_dir: libexec_dir,
    install_mode: 'rwxr-xr-x')
install_man('data/diodon-tasksheet.1')

# Unit tests: pure GLib, no display and no Diodon needed.
test_storage = executable('test-storage',
    [
        'tests/test-storage.vala',
        'src/tasksheet-item.vala',
        'src/tasksheet-storage.vala',
    ],
    dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('storage', test_storage)
