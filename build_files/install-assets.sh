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
  [catppuccin-aurorae]="5622fa6cadc8f82890c1e51d6a8c0aee0224984f05809208c7084680a6a22b08"
  [catppuccin-sddm]="3d9bcc540924e06ae1aaef6994130170db7f630d7d1b25fe5e780d08493ed67f"
  [catppuccin-gtk]="cbacdac6161f98c315fb86740e21426ef6dda64f0ad69157cf28f3a1dda446fe"
)

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

# ── Tema Garuda Mokka ─────────────────────────────────────────────────────────
# Pinado por tag para builds reprodutíveis. Atualizar GARUDA_MOKKA_VERSION e
# o checksum correspondente em CHECKSUMS[] ao atualizar.
log "Baixando tema Garuda Mokka (v${GARUDA_MOKKA_VERSION:=1.4.7})"
GARUDA_URL="https://gitlab.com/garuda-linux/themes-and-settings/settings/garuda-mokka/-/archive/${GARUDA_MOKKA_VERSION}/garuda-mokka-${GARUDA_MOKKA_VERSION}.tar.gz"
fetch -o "$TMPDIR_ASSETS/garuda-mokka.tar.gz" "$GARUDA_URL"
verify_checksum "$TMPDIR_ASSETS/garuda-mokka.tar.gz" "${CHECKSUMS[garuda-mokka]}"
tar -xzf "$TMPDIR_ASSETS/garuda-mokka.tar.gz" -C "$TMPDIR_ASSETS"

GARUDA_DIR="$TMPDIR_ASSETS/garuda-mokka-${GARUDA_MOKKA_VERSION}"
if [[ ! -d "$GARUDA_DIR" ]]; then
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
  copy_dir_if_exists "$GARUDA_DIR/usr/share/Kvantum" \
    /usr/share/Kvantum
  copy_dir_if_exists "$GARUDA_DIR/usr/share/sddm" \
    /usr/share/sddm

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

# ── Aurorae: Catppuccin Mocha Classic ────────────────────────────────────────
log "Instalando Aurorae CatppuccinMocha-Classic"
mkdir -p /usr/share/aurorae/themes
fetch -o "$TMPDIR_ASSETS/catppuccin-aurorae.tar.gz" \
  "https://github.com/catppuccin/kde/releases/download/v0.2.6/Classic-Aurorae-Theme.tar.gz"
verify_checksum "$TMPDIR_ASSETS/catppuccin-aurorae.tar.gz" "${CHECKSUMS[catppuccin-aurorae]}"
tar -xzf "$TMPDIR_ASSETS/catppuccin-aurorae.tar.gz" -C /usr/share/aurorae/themes/

# ── SDDM: Catppuccin Mocha Mauve theme ───────────────────────────────────────
log "Instalando tema SDDM Catppuccin Mocha Mauve"
mkdir -p /usr/share/sddm/themes
fetch -o "$TMPDIR_ASSETS/catppuccin-sddm.zip" \
  "https://github.com/catppuccin/sddm/releases/download/v1.1.2/catppuccin-mocha-mauve-sddm.zip"
verify_checksum "$TMPDIR_ASSETS/catppuccin-sddm.zip" "${CHECKSUMS[catppuccin-sddm]}"
unzip -qo "$TMPDIR_ASSETS/catppuccin-sddm.zip" -d /usr/share/sddm/themes/

# ── GTK: Catppuccin Mocha Standard Mauve Dark ────────────────────────────────
log "Instalando tema GTK Catppuccin Mocha Standard Mauve Dark"
mkdir -p /usr/share/themes
fetch -o "$TMPDIR_ASSETS/catppuccin-gtk.zip" \
  "https://github.com/catppuccin/gtk/releases/download/v1.0.3/catppuccin-mocha-mauve-standard%2Bdefault.zip"
verify_checksum "$TMPDIR_ASSETS/catppuccin-gtk.zip" "${CHECKSUMS[catppuccin-gtk]}"
unzip -qo "$TMPDIR_ASSETS/catppuccin-gtk.zip" -d /usr/share/themes/

log "Assets instalados com sucesso."
