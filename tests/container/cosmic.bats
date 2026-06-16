#!/usr/bin/env bats
# Container tests — run inside the built image
# Tests: COSMIC skel, themes, fonts, wallpaper, panel, layout, GTK

setup() {
    load '../helpers/common'
    COSMIC_SKEL="/etc/skel/.config/cosmic"
}

# ── Dark mode ────────────────────────────────────────────────────────────────

@test "COSMIC dark mode is active in skel" {
    grep -qx 'true' "$COSMIC_SKEL/com.system76.CosmicTheme.Mode/v1/is_dark"
}

# ── Fonts ────────────────────────────────────────────────────────────────────

@test "COSMIC interface font is JetBrainsMono Nerd Font" {
    grep -q 'JetBrainsMono Nerd Font' "$COSMIC_SKEL/com.system76.CosmicTk/v1/interface_font"
}

@test "COSMIC monospace font is JetBrainsMono Nerd Font Mono" {
    grep -q 'JetBrainsMono Nerd Font Mono' "$COSMIC_SKEL/com.system76.CosmicTk/v1/monospace_font"
}

# ── Theme propagation ───────────────────────────────────────────────────────

@test "COSMIC apply_theme_global is active" {
    grep -qx 'true' "$COSMIC_SKEL/com.system76.CosmicTk/v1/apply_theme_global"
}

# ── Icon theme ───────────────────────────────────────────────────────────────

@test "COSMIC icon theme is installed" {
    ICON_THEME=$(tr -d '"' < "$COSMIC_SKEL/com.system76.CosmicTk/v1/icon_theme" 2>/dev/null)
    [ -n "$ICON_THEME" ]
    [ -d "/usr/share/icons/$ICON_THEME" ]
}

# ── Wallpaper ────────────────────────────────────────────────────────────────

@test "COSMIC wallpaper file exists" {
    COSMIC_WALL=$(sed -n 's/.*Path("\([^"]*\)").*/\1/p' \
        "$COSMIC_SKEL/com.system76.CosmicBackground/v1/all" 2>/dev/null | head -1)
    [ -n "$COSMIC_WALL" ]
    [ -e "$COSMIC_WALL" ]
}

# ── Panel config ─────────────────────────────────────────────────────────────

@test "COSMIC panel is at bottom" {
    grep -qx 'Bottom' "$COSMIC_SKEL/com.system76.CosmicPanel.Panel/v1/anchor"
}

@test "COSMIC panel has no anchor gap" {
    grep -qx 'false' "$COSMIC_SKEL/com.system76.CosmicPanel.Panel/v1/anchor_gap"
}

@test "COSMIC panel border_radius is 0" {
    grep -qx '0' "$COSMIC_SKEL/com.system76.CosmicPanel.Panel/v1/border_radius"
}

@test "COSMIC panel margin is 0" {
    grep -qx '0' "$COSMIC_SKEL/com.system76.CosmicPanel.Panel/v1/margin"
}

# ── Layout setup ─────────────────────────────────────────────────────────────

@test "fedora-cosmic-layout-setup is executable" {
    [ -x /usr/libexec/fedora-cosmic-layout-setup ]
}

@test "layout user service exists in skel" {
    [ -f /etc/skel/.config/systemd/user/fedora-cosmic-layout-setup.service ]
}

@test "layout user timer exists in skel" {
    [ -f /etc/skel/.config/systemd/user/fedora-cosmic-layout-setup.timer ]
}

@test "layout global user service exists" {
    [ -f /usr/lib/systemd/user/fedora-cosmic-layout-setup.service ]
}

@test "layout global user timer exists" {
    [ -f /usr/lib/systemd/user/fedora-cosmic-layout-setup.timer ]
}

@test "layout timer is enabled via symlink" {
    [ -L /etc/systemd/user/timers.target.wants/fedora-cosmic-layout-setup.timer ]
}

# ── COSMIC skel required files ───────────────────────────────────────────────

@test "COSMIC skel accent theme exists" {
    [ -e "$COSMIC_SKEL/com.system76.CosmicTheme.Dark/v1/accent" ]
}

@test "COSMIC skel interface_font exists" {
    [ -e "$COSMIC_SKEL/com.system76.CosmicTk/v1/interface_font" ]
}

@test "COSMIC skel wallpaper config exists" {
    [ -e "$COSMIC_SKEL/com.system76.CosmicBackground/v1/all" ]
}

@test "Mokka wallpaper image exists" {
    [ -e /usr/share/backgrounds/mokka/Mokka-tree.jpg ]
}

@test "cosmic-mokka theme-builder.ron exists" {
    [ -f /usr/share/cosmic-mokka/theme-builder.ron ]
}

# ── Theme derivation (Catppuccin Mocha Mauve) ────────────────────────────────

@test "COSMIC dark theme accent is present" {
    COSMIC_DARK="$COSMIC_SKEL/com.system76.CosmicTheme.Dark/v1"
    [ -s "$COSMIC_DARK/accent" ]
}

@test "COSMIC dark theme background is present" {
    COSMIC_DARK="$COSMIC_SKEL/com.system76.CosmicTheme.Dark/v1"
    [ -s "$COSMIC_DARK/background" ]
}

@test "COSMIC ThemeBuilder accent is present" {
    COSMIC_BUILDER="$COSMIC_SKEL/com.system76.CosmicTheme.Dark.Builder/v1"
    [ -s "$COSMIC_BUILDER/accent" ]
}

@test "COSMIC builder accent matches Catppuccin Mocha mauve" {
    COSMIC_BUILDER="$COSMIC_SKEL/com.system76.CosmicTheme.Dark.Builder/v1"
    grep -q '0.79' "$COSMIC_BUILDER/accent"
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
