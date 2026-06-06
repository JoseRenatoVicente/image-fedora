#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*" >&2; }

TMPDIR_ASSETS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ASSETS"' EXIT

# ── Fontes: JetBrainsMono Nerd Font ──────────────────────────────────────────
log "Instalando JetBrainsMono Nerd Font"
FONT_DIR="/usr/share/fonts/JetBrainsMonoNerdFont"
mkdir -p "$FONT_DIR"
curl -L --fail -o "$TMPDIR_ASSETS/JetBrainsMono.zip" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip"
unzip -qo "$TMPDIR_ASSETS/JetBrainsMono.zip" -d "$FONT_DIR"
# Remove arquivos desnecessários (Windows, etc)
find "$FONT_DIR" -name "*.ttf" ! -name "*NerdFont*" -delete 2>/dev/null || true
fc-cache -f "$FONT_DIR"

# ── Cursores: Catppuccin Mocha Mauve ─────────────────────────────────────────
log "Instalando cursores Catppuccin Mocha Mauve"
curl -L --fail -o "$TMPDIR_ASSETS/catppuccin-cursors.zip" \
  "https://github.com/catppuccin/cursors/releases/download/v2.0.0/catppuccin-mocha-mauve-cursors.zip"
unzip -qo "$TMPDIR_ASSETS/catppuccin-cursors.zip" -d /usr/share/icons/

# ── Ícones: Tela Circle Dracula ───────────────────────────────────────────────
log "Instalando ícones Tela Circle Dracula"
git clone --depth=1 --branch 2025-02-10 https://github.com/vinceliuice/Tela-circle-icon-theme \
  "$TMPDIR_ASSETS/Tela-circle-icon-theme"
bash "$TMPDIR_ASSETS/Tela-circle-icon-theme/install.sh" \
  -d /usr/share/icons \
  -c dracula

# ── Tema Garuda Mokka ─────────────────────────────────────────────────────────
log "Baixando tema Garuda Mokka"
GARUDA_URL="https://gitlab.com/garuda-linux/themes-and-settings/settings/garuda-mokka/-/archive/main/garuda-mokka-main.tar.gz"
curl -L --fail -o "$TMPDIR_ASSETS/garuda-mokka.tar.gz" "$GARUDA_URL"
tar -xzf "$TMPDIR_ASSETS/garuda-mokka.tar.gz" -C "$TMPDIR_ASSETS"

GARUDA_DIR="$(find "$TMPDIR_ASSETS" -maxdepth 1 -type d -name 'garuda-mokka*' | head -n1)"
if [[ -z "$GARUDA_DIR" ]]; then
  warn "Tarball do Garuda Mokka não encontrado no caminho esperado. Pulando assets do tema."
else
  log "Instalando assets do Garuda Mokka de: $GARUDA_DIR"

  copy_dir_if_exists() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dst"
    rsync -a "$src"/ "$dst"/
  }

  copy_dir_if_exists "$GARUDA_DIR/usr/share/plasma/look-and-feel" \
    /usr/share/plasma/look-and-feel
  copy_dir_if_exists "$GARUDA_DIR/usr/share/color-schemes" \
    /usr/share/color-schemes
  copy_dir_if_exists "$GARUDA_DIR/usr/share/plasma/desktoptheme" \
    /usr/share/plasma/desktoptheme
  copy_dir_if_exists "$GARUDA_DIR/usr/share/aurorae/themes" \
    /usr/share/aurorae/themes
  copy_dir_if_exists "$GARUDA_DIR/usr/share/wallpapers" \
    /usr/share/wallpapers
  copy_dir_if_exists "$GARUDA_DIR/usr/share/konsole" \
    /usr/share/konsole

  # Skel do Garuda Mokka (configs KDE defaults)
  SKEL_SRC=""
  [[ -d "$GARUDA_DIR/etc/skel" ]] && SKEL_SRC="$GARUDA_DIR/etc/skel"
  if [[ -n "$SKEL_SRC" ]]; then
    log "Aplicando skel do Garuda Mokka"
    rsync -a "$SKEL_SRC"/ /etc/skel/
  else
    warn "Skel não encontrado no tarball do Garuda Mokka."
  fi
fi

# ── SDDM: Catppuccin Mocha Mauve theme ───────────────────────────────────────
log "Instalando tema SDDM Catppuccin Mocha Mauve"
mkdir -p /usr/share/sddm/themes
curl -L --fail -o "$TMPDIR_ASSETS/catppuccin-sddm.zip" \
  "https://github.com/catppuccin/sddm/releases/download/v1.1.2/catppuccin-mocha-mauve-sddm.zip"
unzip -qo "$TMPDIR_ASSETS/catppuccin-sddm.zip" -d /usr/share/sddm/themes/

log "Assets instalados com sucesso."
