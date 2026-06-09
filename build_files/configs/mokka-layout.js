// Patched for Fedora: removed Garuda-specific loadTemplate calls
// (org.garuda.desktop.defaultPanel / defaultDock don't exist on Fedora and
// cause "error when loading applet """ when Plasma executes this script).
// Panel layout is defined by plasma-org.kde.plasma.desktop-appletsrc in skel.
// Also removed a2n.blur wallpaper plugin (not installed on Fedora).
var plasma = getApiVersion(1)

// Center Krunner on screen
const krunner = ConfigFile('krunnerrc')
krunner.group = 'General'
krunner.writeEntry('FreeFloating', true)

// Keyboard repeat delay 250ms (default 600ms is too slow)
const kbd = ConfigFile('kcminputrc')
kbd.group = 'Keyboard'
kbd.writeEntry('RepeatDelay', 250)

// Desktop context menu actions
const desktoprc = ConfigFile('plasma-org.kde.plasma.desktop-appletsrc')
desktoprc.group = "ActionPlugins\x1d0\x1dRightButton;NoModifier"
desktoprc.writeEntry('_run_command', true)
desktoprc.writeEntry('_lock_screen', true)
desktoprc.writeEntry('_logout', true)
desktoprc.writeEntry('_open_terminal', true)
desktoprc.writeEntry('_context', true)
desktoprc.writeEntry('_display_settings', true)
desktoprc.writeEntry('_wallpaper', true)
desktoprc.writeEntry('add widgets', true)
desktoprc.writeEntry('_add panel', true)
desktoprc.writeEntry('configure', true)
desktoprc.writeEntry('configure shortcuts', false)
desktoprc.writeEntry('desktop edit mode', true)
desktoprc.writeEntry('manage activities', true)
desktoprc.writeEntry('remove', true)
desktoprc.writeEntry('_sep1', true)
desktoprc.writeEntry('_sep2', true)
desktoprc.writeEntry('_sep3', true)
desktoprc.writeEntry('_sep4', true)
