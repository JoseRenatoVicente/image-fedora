#!/bin/bash
set -euo pipefail

trap '[[ $BASH_COMMAND != log* ]] && [[ $BASH_COMMAND != warn* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*" >&2; }

TMPDIR_ASSETS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ASSETS"' EXIT

# curl wrapper with retry for transient network failures in container builds
fetch() { curl -L --fail --retry 3 --retry-delay 5 "$@"; }

# ── Verificação de integridade ────────────────────────────────────────────────
# Verifica SHA256 de um ficheiro baixado contra o hash esperado.
# Uso: verify_checksum <ficheiro> <sha256_esperado>
verify_checksum() {
  local file="$1" expected="$2"
  local actual
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FATAL: checksum mismatch para $(basename "$file")"
    echo "  Esperado: $expected"
    echo "  Obtido:   $actual"
    echo "  Ficheiro: $file"
    exit 1
  fi
  echo "  SHA256 OK: $(basename "$file")"
}

# ── Checksums hardcoded (atualizar ao mudar versões) ─────────────────────────
declare -A CHECKSUMS=(
  [JetBrainsMono]="76f05ff3ace48a464a6ca57977998784ff7bdbb65a6d915d7e401cd3927c493c"
  [catppuccin-cursors]="971e113a49de65529b3b706ce8529c1c80f22b2828b9c2f4732b3363fb69fcbb"
  [tela-circle]="61dece3ab25711af9516565dd300d23b1c532fe69eac5cad42d2e9c57fa7c331"
  [garuda-mokka]="e7ae5e7f61bdf959b3065c84006edea86cc201891d61d32f4bdfff2060038700"
  [catppuccin-cosmic]="20cc9db04b8b157a8fbf7c50a21eedf543d983aa23d8a4633e9019982ad2d4cf"
  [catppuccin-gtk]="cbacdac6161f98c315fb86740e21426ef6dda64f0ad69157cf28f3a1dda446fe"
  [starship]="4488c11ca632327d1f1f16fb2f102c0646094c35479cd5435991385da43c61ac"
)

# ── starship (prompt do shell, substitui Oh My Zsh + Powerlevel10k) ───────────
# Não está nos repos Fedora — binário do release oficial, pinado e verificado.
# Só x86_64 traz checksum; noutras arquiteturas é ignorado (o .zshrc protege o
# init com `command -v starship`).
STARSHIP_VERSION="v1.25.1"
if [[ "$(uname -m)" == "x86_64" ]]; then
  log "Instalando starship ${STARSHIP_VERSION}"
  fetch -o "$TMPDIR_ASSETS/starship.tar.gz" \
    "https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu.tar.gz"
  verify_checksum "$TMPDIR_ASSETS/starship.tar.gz" "${CHECKSUMS[starship]}"
  tar -xzf "$TMPDIR_ASSETS/starship.tar.gz" -C /usr/bin starship
  chmod 0755 /usr/bin/starship
  /usr/bin/starship --version
else
  warn "Arquitetura $(uname -m) sem binário starship pinado — ignorado."
fi

# ── Fontes: JetBrainsMono Nerd Font ──────────────────────────────────────────
log "Instalando JetBrainsMono Nerd Font"
FONT_DIR="/usr/share/fonts/JetBrainsMonoNerdFont"
mkdir -p "$FONT_DIR"
fetch -o "$TMPDIR_ASSETS/JetBrainsMono.zip" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip"
verify_checksum "$TMPDIR_ASSETS/JetBrainsMono.zip" "${CHECKSUMS[JetBrainsMono]}"
unzip -qo "$TMPDIR_ASSETS/JetBrainsMono.zip" -d "$FONT_DIR"
# Remove arquivos desnecessários (Windows, etc)
find "$FONT_DIR" -name "*.ttf" ! -name "*NerdFont*" -delete 2>/dev/null || true
fc-cache -f "$FONT_DIR"

# ── Cursores: Catppuccin Mocha Mauve ─────────────────────────────────────────
log "Instalando cursores Catppuccin Mocha Mauve"
fetch -o "$TMPDIR_ASSETS/catppuccin-cursors.zip" \
  "https://github.com/catppuccin/cursors/releases/download/v2.0.0/catppuccin-mocha-mauve-cursors.zip"
verify_checksum "$TMPDIR_ASSETS/catppuccin-cursors.zip" "${CHECKSUMS[catppuccin-cursors]}"
unzip -qo "$TMPDIR_ASSETS/catppuccin-cursors.zip" -d /usr/share/icons/

# ── Ícones: Tela Circle Dracula ───────────────────────────────────────────────
# Use tarball download instead of git clone to avoid transient SSL/EOF failures
log "Instalando ícones Tela Circle Dracula"
fetch -o "$TMPDIR_ASSETS/tela-circle.tar.gz" \
  "https://github.com/vinceliuice/Tela-circle-icon-theme/archive/refs/tags/2025-02-10.tar.gz"
verify_checksum "$TMPDIR_ASSETS/tela-circle.tar.gz" "${CHECKSUMS[tela-circle]}"
tar -xzf "$TMPDIR_ASSETS/tela-circle.tar.gz" -C "$TMPDIR_ASSETS"
TELA_DIR="$TMPDIR_ASSETS/Tela-circle-icon-theme-2025-02-10"
[[ -d "$TELA_DIR" ]] || { echo "ERROR: diretório $TELA_DIR não encontrado após extração"; exit 1; }
bash "$TELA_DIR/install.sh" \
  -d /usr/share/icons \
  -c dracula

# ── Wallpaper Mokka-tree (do Garuda Mokka) ────────────────────────────────────
# Só o wallpaper é reaproveitado do Garuda Mokka — o resto (look-and-feel KDE,
# Kvantum, Aurorae, SDDM, konsole) não tem equivalente no COSMIC.
log "Baixando wallpaper Mokka-tree (Garuda Mokka v${GARUDA_MOKKA_VERSION:=1.4.7})"
GARUDA_URL="https://gitlab.com/garuda-linux/themes-and-settings/settings/garuda-mokka/-/archive/${GARUDA_MOKKA_VERSION}/garuda-mokka-${GARUDA_MOKKA_VERSION}.tar.gz"
fetch -o "$TMPDIR_ASSETS/garuda-mokka.tar.gz" "$GARUDA_URL"
verify_checksum "$TMPDIR_ASSETS/garuda-mokka.tar.gz" "${CHECKSUMS[garuda-mokka]}"
mkdir -p /usr/share/backgrounds/mokka
# A versão full-res do wallpaper está em wallpapers/Mokka-tree.jpg
tar -xzf "$TMPDIR_ASSETS/garuda-mokka.tar.gz" -C "$TMPDIR_ASSETS" \
  "garuda-mokka-${GARUDA_MOKKA_VERSION}/wallpapers/Mokka-tree.jpg"
install -Dm644 \
  "$TMPDIR_ASSETS/garuda-mokka-${GARUDA_MOKKA_VERSION}/wallpapers/Mokka-tree.jpg" \
  /usr/share/backgrounds/mokka/Mokka-tree.jpg
log "Wallpaper instalado em /usr/share/backgrounds/mokka/Mokka-tree.jpg"

# ── Tema COSMIC: Catppuccin Mocha Mauve (staging) ─────────────────────────────
# O repo Catppuccin fornece os ficheiros .ron de import (ThemeBuilder do desktop
# e color scheme do cosmic-term). São colocados em /usr/share/cosmic-mokka/ para
# o build-configure.sh os consumir ao montar o skel COSMIC. Pinado por commit.
CATPPUCCIN_COSMIC_REF="95e81098042dd2102f0b258f6990f886c5759692"
log "Baixando tema Catppuccin para COSMIC (commit ${CATPPUCCIN_COSMIC_REF:0:12})"
fetch -o "$TMPDIR_ASSETS/catppuccin-cosmic.tar.gz" \
  "https://github.com/catppuccin/cosmic-desktop/archive/${CATPPUCCIN_COSMIC_REF}.tar.gz"
verify_checksum "$TMPDIR_ASSETS/catppuccin-cosmic.tar.gz" "${CHECKSUMS[catppuccin-cosmic]}"
tar -xzf "$TMPDIR_ASSETS/catppuccin-cosmic.tar.gz" -C "$TMPDIR_ASSETS"
CAT_COSMIC_DIR="$TMPDIR_ASSETS/cosmic-desktop-${CATPPUCCIN_COSMIC_REF}"
mkdir -p /usr/share/cosmic-mokka
install -Dm644 \
  "$CAT_COSMIC_DIR/themes/cosmic-settings/catppuccin-mocha-mauve+round.ron" \
  /usr/share/cosmic-mokka/theme-builder.ron
install -Dm644 \
  "$CAT_COSMIC_DIR/themes/cosmic-term/catppuccin-mocha.ron" \
  /usr/share/cosmic-mokka/cosmic-term-mocha.ron
log "Tema Catppuccin-COSMIC em /usr/share/cosmic-mokka/"

# ── GTK: Catppuccin Mocha Standard Mauve Dark ────────────────────────────────
log "Instalando tema GTK Catppuccin Mocha Standard Mauve Dark"
mkdir -p /usr/share/themes
fetch -o "$TMPDIR_ASSETS/catppuccin-gtk.zip" \
  "https://github.com/catppuccin/gtk/releases/download/v1.0.3/catppuccin-mocha-mauve-standard%2Bdefault.zip"
verify_checksum "$TMPDIR_ASSETS/catppuccin-gtk.zip" "${CHECKSUMS[catppuccin-gtk]}"
unzip -qo "$TMPDIR_ASSETS/catppuccin-gtk.zip" -d /usr/share/themes/

log "Assets instalados com sucesso."
