// Patched for Fedora: all Garuda-specific calls removed.
//
// loadTemplate call for org.garuda.desktop.defaultPanel was removed because
// that template does not exist on Fedora — calling a missing template
// creates an empty containment (plugin="") → "error when loading applet """.
//
// a2n.blur wallpaper plugin call was removed (not installed on Fedora).
//
// All ConfigFile writes removed:
//   - kcminputrc RepeatDelay already set in skel/.config/kcminputrc via build.sh
//   - krunnerrc FreeFloating set in skel/.config/krunnerrc via build.sh
//   - appletsrc ActionPlugins writes created an invalid KConfig state: writing
//     [ActionPlugins][0][RightButton;NoModifier] (nested subgroup) while the skel
//     already has [ActionPlugins][0] RightButton;NoModifier as a flat key — this
//     same-name key+subgroup collision causes Plasma to generate a ghost containment
//     with empty plugin, producing "error when loading applet """.
//
// Panel layout and ActionPlugins come entirely from the skel appletsrc.
var plasma = getApiVersion(1)
