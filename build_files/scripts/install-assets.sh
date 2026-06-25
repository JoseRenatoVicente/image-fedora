#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*" >&2; }

export TMPDIR_ASSETS
TMPDIR_ASSETS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ASSETS"' EXIT

# curl wrapper with retry for transient network failures in container builds
fetch() { curl -L --fail --retry 3 --retry-delay 5 "$@"; }

# Verify SHA256 checksum
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

# ── Funções de instalação ────────────────────────────────────────────────────
# Cada função instala um asset. Recebem $ARCHIVE (ficheiro descarregado) e
# $TMPDIR_ASSETS (dir temporário) no ambiente, definidos pelo loop principal.
# Substituem o antigo eval de strings do manifesto: lintáveis e debugáveis.

_install_starship() {
    tar -xzf "$ARCHIVE" -C /usr/bin starship
    chmod 0755 /usr/bin/starship
    /usr/bin/starship --version
}

_install_jetbrains_mono() {
    local dir=/usr/share/fonts/JetBrainsMonoNerdFont
    mkdir -p "$dir"
    unzip -qo "$ARCHIVE" -d "$dir"
    # Mantém só as variantes Nerd Font (remove os .ttf originais sem patch)
    find "$dir" -name '*.ttf' ! -name '*NerdFont*' -delete 2>/dev/null || true
    # Mantém apenas os pesos essenciais (Regular/Bold/Italic/BoldItalic) em
    # versão normal e Mono. As 90+ variantes restantes (NL, ExtraLight, Thin,
    # Light, Medium, SemiBold, ExtraBold, etc.) aumentam a ISO em ~200 MB sem
    # ganho prático para o uso desta imagem.
    keep_re='JetBrainsMono(NerdFontMono|NerdFont)-(Regular|Bold|Italic|BoldItalic)\.ttf$'
    find "$dir" -name '*.ttf' -type f | while read -r font; do
        if [[ ! "$(basename "$font")" =~ $keep_re ]]; then
            rm -f "$font"
        fi
    done
    fc-cache -f "$dir"
}

_install_catppuccin_cursors() {
    unzip -qo "$ARCHIVE" -d /usr/share/icons/
}

_install_tela_circle() {
    tar -xzf "$ARCHIVE" -C "$TMPDIR_ASSETS"
    bash "$TMPDIR_ASSETS/Tela-circle-icon-theme-${TELA_CIRCLE_VERSION}/install.sh" \
        -d /usr/share/icons -c dracula
    # O script instala 3 variantes de brilho (padrão + light + dark).
    # Mantemos só a variante padrão; light/dark são redundantes para esta imagem.
    rm -rf /usr/share/icons/Tela-circle-dracula-light \
           /usr/share/icons/Tela-circle-dracula-dark
}

# Complex installer for Garuda Mokka (multiple rsync targets + skel)
_install_garuda_mokka() {
    tar -xzf "$ARCHIVE" -C "$TMPDIR_ASSETS"
    local dir="$TMPDIR_ASSETS/garuda-mokka-${GARUDA_MOKKA_VERSION}"
    if [[ ! -d "$dir" ]]; then
        warn "Tarball do Garuda Mokka não encontrado em $dir. Pulando."
        return
    fi

    _copy_if_exists() {
        if [[ -d "$1" ]]; then
            mkdir -p "$2"
            rsync -a "$1"/ "$2"/
        fi
    }
    _copy_if_exists "$dir/usr/share/plasma/look-and-feel"  /usr/share/plasma/look-and-feel
    _copy_if_exists "$dir/usr/share/color-schemes"         /usr/share/color-schemes
    _copy_if_exists "$dir/usr/share/plasma/desktoptheme"   /usr/share/plasma/desktoptheme
    _copy_if_exists "$dir/usr/share/aurorae/themes"        /usr/share/aurorae/themes
    _copy_if_exists "$dir/usr/share/wallpapers"            /usr/share/wallpapers
    # O pacote Mokka inclui o wallpaper "Next" com imagens de até 7680x2160
    # (~40 MB). Não é usado como padrão (o greeter usa Mokka-tree), por isso
    # removemos para economizar espaço na ISO.
    rm -rf /usr/share/wallpapers/Next
    _copy_if_exists "$dir/usr/share/konsole"               /usr/share/konsole
    _copy_if_exists "$dir/usr/share/Kvantum"               /usr/share/Kvantum
    _copy_if_exists "$dir/usr/share/sddm"                  /usr/share/sddm

    if [[ -d "$dir/etc/skel" ]]; then
        log "Aplicando skel do Garuda Mokka"
        rsync -a "$dir/etc/skel"/ /etc/skel/
    else
        warn "Skel não encontrado no tarball do Garuda Mokka."
    fi
}

_install_catppuccin_aurorae() {
    mkdir -p /usr/share/aurorae/themes
    tar -xzf "$ARCHIVE" -C /usr/share/aurorae/themes/
}

_install_catppuccin_sddm() {
    mkdir -p /usr/share/sddm/themes
    unzip -qo "$ARCHIVE" -d /usr/share/sddm/themes/
}

_install_catppuccin_gtk() {
    mkdir -p /usr/share/themes
    unzip -qo "$ARCHIVE" -d /usr/share/themes/
}

# Load the asset manifest
# shellcheck source=../assets/assets-manifest.sh
source "$(dirname "$0")/../assets/assets-manifest.sh"

CURRENT_ARCH="$(uname -m)"

for entry in "${ASSETS[@]}"; do
    IFS='|' read -r name url sha256 arch_filter install_fn <<< "$entry"

    if [[ -n "$arch_filter" && "$CURRENT_ARCH" != "$arch_filter" ]]; then
        warn "Arquitetura $CURRENT_ARCH sem binário pinado para $name — ignorado."
        continue
    fi

    if ! declare -F "$install_fn" >/dev/null; then
        echo "FATAL: função de instalação '$install_fn' não definida para o asset '$name'" >&2
        exit 1
    fi

    log "Instalando $name"
    export ARCHIVE="$TMPDIR_ASSETS/${name}.download"
    fetch -o "$ARCHIVE" "$url"
    verify_checksum "$ARCHIVE" "$sha256"

    "$install_fn"
done

log "Assets instalados com sucesso."
