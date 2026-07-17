#!/usr/bin/env bats
# Container tests — run inside the built image
# Tests: COSMIC theme (Catppuccin Mocha Mauve), fonts, wallpaper, GTK

setup() {
    load '../helpers/common'
    COSMIC_THEME_DARK="/usr/share/cosmic/com.system76.CosmicTheme.Dark/v1"
    COSMIC_THEME_BUILDER="/usr/share/cosmic/com.system76.CosmicTheme.Dark.Builder/v1"
}

# ── Look and feel (Catppuccin Mocha Mauve) ──────────────────────────────────

@test "COSMIC theme palette is Catppuccin-Mocha-Mauve" {
    grep -q 'Catppuccin-Mocha-Mauve' "$COSMIC_THEME_DARK/palette"
}

@test "COSMIC theme builder palette is Catppuccin-Mocha-Mauve" {
    grep -q 'Catppuccin-Mocha-Mauve' "$COSMIC_THEME_BUILDER/palette"
}

@test "COSMIC theme name is Catppuccin-Mocha-Mauve" {
    grep -q 'Catppuccin-Mocha-Mauve' "$COSMIC_THEME_DARK/name"
}

@test "COSMIC theme accent and accent_button files exist" {
    [ -f "$COSMIC_THEME_DARK/accent" ]
    [ -f "$COSMIC_THEME_DARK/accent_button" ]
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

@test "COSMIC default wallpaper is configured" {
    [ -f /usr/share/cosmic/com.system76.CosmicBackground/v1/all ]
    grep -q 'source: Path(' /usr/share/cosmic/com.system76.CosmicBackground/v1/all
}

# ── cosmic-term theme ────────────────────────────────────────────────────────

@test "cosmic-term Catppuccin Mocha theme is available for import" {
    [ -f /usr/share/cosmic-term-themes/catppuccin-mocha.ron ]
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

# ── Regressão: resquícios do Mokka (KDE) não devem existir ──────────────────

@test "Mokka look-and-feel package is not installed" {
    [ ! -d /usr/share/plasma/look-and-feel/Mokka ]
}

@test "Catppuccin Aurorae theme is not installed" {
    [ ! -d /usr/share/aurorae/themes ]
}

@test "Catppuccin SDDM theme is not installed" {
    [ ! -d /usr/share/sddm/themes ]
}
