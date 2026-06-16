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

# Complex installer for Garuda Mokka (multiple rsync targets + skel)
_install_garuda_mokka() {
    tar -xzf "$ARCHIVE" -C "$TMPDIR_ASSETS"
    local dir="$TMPDIR_ASSETS/garuda-mokka-${GARUDA_MOKKA_VERSION}"
    if [[ ! -d "$dir" ]]; then
        warn "Tarball do Garuda Mokka não encontrado em $dir. Pulando."
        return
    fi

    _copy_if_exists() {
        [[ -d "$1" ]] && { mkdir -p "$2"; rsync -a "$1"/ "$2"/; }
    }
    _copy_if_exists "$dir/usr/share/plasma/look-and-feel"  /usr/share/plasma/look-and-feel
    _copy_if_exists "$dir/usr/share/color-schemes"         /usr/share/color-schemes
    _copy_if_exists "$dir/usr/share/plasma/desktoptheme"   /usr/share/plasma/desktoptheme
    _copy_if_exists "$dir/usr/share/aurorae/themes"        /usr/share/aurorae/themes
    _copy_if_exists "$dir/usr/share/wallpapers"            /usr/share/wallpapers
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

# Load the asset manifest
# shellcheck source=assets-manifest.sh
source "$(dirname "$0")/assets-manifest.sh"

CURRENT_ARCH="$(uname -m)"

for entry in "${ASSETS[@]}"; do
    IFS='|' read -r name url sha256 arch_filter post_install <<< "$entry"

    if [[ -n "$arch_filter" && "$CURRENT_ARCH" != "$arch_filter" ]]; then
        warn "Arquitetura $CURRENT_ARCH sem binário pinado para $name — ignorado."
        continue
    fi

    log "Instalando $name"
    export ARCHIVE="$TMPDIR_ASSETS/${name}.download"
    fetch -o "$ARCHIVE" "$url"
    verify_checksum "$ARCHIVE" "$sha256"

    if [[ -n "$post_install" ]]; then
        eval "$post_install"
    fi
done

log "Assets instalados com sucesso."
