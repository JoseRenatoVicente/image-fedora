#!/usr/bin/env bats
# Container tests — run inside the built image
# Tests: KDE Plasma skel, Mokka theme, fonts, wallpaper, GTK

setup() {
    load '../helpers/common'
    KDE_SKEL="/etc/skel/.config"
}

# ── Look and feel (Mokka) ────────────────────────────────────────────────────

@test "KDE look-and-feel is Mokka in ksplashrc" {
    grep -q 'Theme=Mokka' "$KDE_SKEL/ksplashrc"
}

@test "KDE look-and-feel is Mokka in kdeglobals" {
    grep -q 'LookAndFeelPackage=Mokka' "$KDE_SKEL/kdeglobals"
}

@test "KDE color scheme is Mokka" {
    grep -q 'ColorScheme=Mokka' "$KDE_SKEL/kdeglobals"
}

@test "KDE widget style is kvantum-dark" {
    grep -q 'widgetStyle=kvantum-dark' "$KDE_SKEL/kdeglobals"
}

@test "KDE icon theme is Tela-circle-dracula-dark" {
    grep -q 'Theme=Tela-circle-dracula-dark' "$KDE_SKEL/kdeglobals"
}

@test "Mokka look-and-feel package is installed" {
    [ -d /usr/share/plasma/look-and-feel/Mokka ]
}

# ── Window decoration (Aurorae) ──────────────────────────────────────────────

@test "Catppuccin Aurorae CatppuccinMocha-Classic is installed" {
    [ -d /usr/share/aurorae/themes/CatppuccinMocha-Classic ]
}

# ── Cursor ───────────────────────────────────────────────────────────────────

@test "Catppuccin cursor theme is installed" {
    [ -d /usr/share/icons/catppuccin-mocha-mauve-cursors ]
}

# ── Icons ────────────────────────────────────────────────────────────────────

@test "Tela circle Dracula icon theme is installed" {
    [ -d /usr/share/icons/Tela-circle-dracula-dark ]
}

# ── Fonts ────────────────────────────────────────────────────────────────────

@test "JetBrainsMono Nerd Font is installed" {
    [ -d /usr/share/fonts/JetBrainsMonoNerdFont ]
    find /usr/share/fonts/JetBrainsMonoNerdFont -name '*NerdFont*.ttf' | grep -q .
}

# ── Wallpaper ────────────────────────────────────────────────────────────────

@test "Mokka-tree wallpaper is installed" {
    [ -d /usr/share/wallpapers/Mokka-tree ]
}

# ── KDE skel files ───────────────────────────────────────────────────────────

@test "plasma desktop appletsrc exists in skel" {
    [ -f /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc ]
}

@test "krunnerrc free-floating is set in skel" {
    grep -q 'FreeFloating=true' "$KDE_SKEL/krunnerrc"
}

# ── kwin VM compat ───────────────────────────────────────────────────────────

@test "kwin-vm-compat.sh is installed and executable" {
    [ -x /usr/libexec/kwin-vm-compat.sh ]
}

@test "kwin-vm-compat autostart exists" {
    [ -f /etc/xdg/autostart/kwin-vm-compat.desktop ]
}

# ── SDDM / plasmalogin ───────────────────────────────────────────────────────

@test "plasmalogin SDDM theme config exists" {
    [ -f /etc/plasmalogin.conf.d/10-theme.conf ]
}

@test "Catppuccin SDDM theme is installed" {
    [ -d /usr/share/sddm/themes/catppuccin-mocha-mauve ]
}

# ── GTK theme ────────────────────────────────────────────────────────────────

@test "GTK theme referenced in skel is installed" {
    GTK3_CONF="/etc/skel/.config/gtk-3.0/settings.ini"
    if [ ! -f "$GTK3_CONF" ]; then
        skip "GTK3 settings.ini not present"
    fi
    GTK_THEME=$(sed -n 's/^gtk-theme-name=//p' "$GTK3_CONF" | head -1)
    if [ -z "$GTK_THEME" ]; then
        skip "no gtk-theme-name set"
    fi
    [ -d "/usr/share/themes/$GTK_THEME" ]
}
