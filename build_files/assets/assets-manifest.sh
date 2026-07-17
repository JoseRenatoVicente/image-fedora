# shellcheck shell=bash
# assets-manifest.sh — Definições centralizadas de assets de theming/CLI.
# Sourced por install-assets.sh (não executado) — sem shebang nem +x.
# Versões, URLs e checksums num único sítio.
# shellcheck disable=SC2034  # ASSETS/*_VERSION consumidos por quem faz source
#
# Para atualizar um asset: muda versão/URL/checksum aqui.
# Para adicionar um asset: acrescenta uma entrada ao array ASSETS e define a
# função de instalação correspondente em install-assets.sh.

# ── Versões pinadas ──────────────────────────────────────────────────────────
STARSHIP_VERSION="v1.25.1"
WINAPPS_COMMIT="abc2c3da1a7980a8e87c616f7387bd898aadfeb3"
TELA_CIRCLE_VERSION="2025-02-10"
# catppuccin/cosmic-desktop não publica releases tagged — pinado por commit do
# branch main. Contém os temas COSMIC (RON) Mocha/Mauve para cosmic-settings e
# cosmic-term, substituto do garuda-mokka (Plasma) da era KDE.
CATPPUCCIN_COSMIC_COMMIT="95e81098042dd2102f0b258f6990f886c5759692"

# ── Asset definitions ────────────────────────────────────────────────────────
# Formato: name|url|sha256|arch_filter|install_fn
#   arch_filter: vazio = todas as arquiteturas; "x86_64" = só essa
#   install_fn:  nome de uma função definida em install-assets.sh, chamada com
#                $ARCHIVE (ficheiro descarregado) e $TMPDIR_ASSETS no ambiente.
ASSETS=(
  "starship|https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu.tar.gz|4488c11ca632327d1f1f16fb2f102c0646094c35479cd5435991385da43c61ac|x86_64|_install_starship"

  "JetBrainsMono|https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip|76f05ff3ace48a464a6ca57977998784ff7bdbb65a6d915d7e401cd3927c493c||_install_jetbrains_mono"

  "catppuccin-cursors|https://github.com/catppuccin/cursors/releases/download/v2.0.0/catppuccin-mocha-mauve-cursors.zip|971e113a49de65529b3b706ce8529c1c80f22b2828b9c2f4732b3363fb69fcbb||_install_catppuccin_cursors"

  "tela-circle|https://github.com/vinceliuice/Tela-circle-icon-theme/archive/refs/tags/${TELA_CIRCLE_VERSION}.tar.gz|61dece3ab25711af9516565dd300d23b1c532fe69eac5cad42d2e9c57fa7c331||_install_tela_circle"

  "catppuccin-cosmic|https://github.com/catppuccin/cosmic-desktop/archive/${CATPPUCCIN_COSMIC_COMMIT}.tar.gz|20cc9db04b8b157a8fbf7c50a21eedf543d983aa23d8a4633e9019982ad2d4cf||_install_catppuccin_cosmic"

  "catppuccin-gtk|https://github.com/catppuccin/gtk/releases/download/v1.0.3/catppuccin-mocha-mauve-standard%2Bdefault.zip|cbacdac6161f98c315fb86740e21426ef6dda64f0ad69157cf28f3a1dda446fe||_install_catppuccin_gtk"

  "winapps|https://github.com/winapps-org/winapps/archive/${WINAPPS_COMMIT}.tar.gz|448bd39a2ac27e927cd493471466af94e1b8d5f889491a259f14a4b15045ae82||_install_winapps"
)
