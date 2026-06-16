#!/bin/bash
# assets-manifest.sh — Centralized asset definitions.
# Sourced by install-assets.sh. All versions, URLs, and checksums in one place.
#
# Para atualizar um asset: altere a versão/URL/checksum aqui.
# Para adicionar um asset: adicione uma entrada ao array ASSETS.

# ── Versões pinadas ──────────────────────────────────────────────────────────
STARSHIP_VERSION="v1.25.1"
GARUDA_MOKKA_VERSION="1.4.7"
CATPPUCCIN_COSMIC_REF="95e81098042dd2102f0b258f6990f886c5759692"

# ── Asset definitions ────────────────────────────────────────────────────────
# Format: name|url|sha256|arch_filter|post_install
# arch_filter: empty = all arches, "x86_64" = only that arch
# post_install: shell commands ($ARCHIVE = downloaded file, $TMPDIR_ASSETS = temp dir)

ASSETS=(
  "starship|https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu.tar.gz|4488c11ca632327d1f1f16fb2f102c0646094c35479cd5435991385da43c61ac|x86_64|tar -xzf \"\$ARCHIVE\" -C /usr/bin starship && chmod 0755 /usr/bin/starship && /usr/bin/starship --version"

  "JetBrainsMono|https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip|76f05ff3ace48a464a6ca57977998784ff7bdbb65a6d915d7e401cd3927c493c||mkdir -p /usr/share/fonts/JetBrainsMonoNerdFont && unzip -qo \"\$ARCHIVE\" -d /usr/share/fonts/JetBrainsMonoNerdFont && find /usr/share/fonts/JetBrainsMonoNerdFont -name '*.ttf' ! -name '*NerdFont*' -delete 2>/dev/null || true; fc-cache -f /usr/share/fonts/JetBrainsMonoNerdFont"

  "catppuccin-cursors|https://github.com/catppuccin/cursors/releases/download/v2.0.0/catppuccin-mocha-mauve-cursors.zip|971e113a49de65529b3b706ce8529c1c80f22b2828b9c2f4732b3363fb69fcbb||unzip -qo \"\$ARCHIVE\" -d /usr/share/icons/"

  "tela-circle|https://github.com/vinceliuice/Tela-circle-icon-theme/archive/refs/tags/2025-02-10.tar.gz|61dece3ab25711af9516565dd300d23b1c532fe69eac5cad42d2e9c57fa7c331||tar -xzf \"\$ARCHIVE\" -C \"\$TMPDIR_ASSETS\" && bash \"\$TMPDIR_ASSETS/Tela-circle-icon-theme-2025-02-10/install.sh\" -d /usr/share/icons -c dracula"

  "garuda-mokka|https://gitlab.com/garuda-linux/themes-and-settings/settings/garuda-mokka/-/archive/${GARUDA_MOKKA_VERSION}/garuda-mokka-${GARUDA_MOKKA_VERSION}.tar.gz|e7ae5e7f61bdf959b3065c84006edea86cc201891d61d32f4bdfff2060038700||tar -xzf \"\$ARCHIVE\" -C \"\$TMPDIR_ASSETS\" \"garuda-mokka-${GARUDA_MOKKA_VERSION}/wallpapers/Mokka-tree.jpg\" && install -Dm644 \"\$TMPDIR_ASSETS/garuda-mokka-${GARUDA_MOKKA_VERSION}/wallpapers/Mokka-tree.jpg\" /usr/share/backgrounds/mokka/Mokka-tree.jpg"

  "catppuccin-cosmic|https://github.com/catppuccin/cosmic-desktop/archive/${CATPPUCCIN_COSMIC_REF}.tar.gz|20cc9db04b8b157a8fbf7c50a21eedf543d983aa23d8a4633e9019982ad2d4cf||tar -xzf \"\$ARCHIVE\" -C \"\$TMPDIR_ASSETS\" && mkdir -p /usr/share/cosmic-mokka && install -Dm644 \"\$TMPDIR_ASSETS/cosmic-desktop-${CATPPUCCIN_COSMIC_REF}/themes/cosmic-settings/catppuccin-mocha-mauve+round.ron\" /usr/share/cosmic-mokka/theme-builder.ron && install -Dm644 \"\$TMPDIR_ASSETS/cosmic-desktop-${CATPPUCCIN_COSMIC_REF}/themes/cosmic-term/catppuccin-mocha.ron\" /usr/share/cosmic-mokka/cosmic-term-mocha.ron"

  "catppuccin-gtk|https://github.com/catppuccin/gtk/releases/download/v1.0.3/catppuccin-mocha-mauve-standard%2Bdefault.zip|cbacdac6161f98c315fb86740e21426ef6dda64f0ad69157cf28f3a1dda446fe||mkdir -p /usr/share/themes && unzip -qo \"\$ARCHIVE\" -d /usr/share/themes/"
)
