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

# Load the asset manifest
# shellcheck source=assets-manifest.sh
source "$(dirname "$0")/assets-manifest.sh"

CURRENT_ARCH="$(uname -m)"

for entry in "${ASSETS[@]}"; do
    IFS='|' read -r name url sha256 arch_filter post_install <<< "$entry"

    # Skip if architecture filter doesn't match
    if [[ -n "$arch_filter" && "$CURRENT_ARCH" != "$arch_filter" ]]; then
        warn "Arquitectura $CURRENT_ARCH sem binário pinado para $name — ignorado."
        continue
    fi

    log "Instalando $name"

    # Download to temp file
    export ARCHIVE="$TMPDIR_ASSETS/${name}.download"
    fetch -o "$ARCHIVE" "$url"

    # Verify checksum
    verify_checksum "$ARCHIVE" "$sha256"

    # Run post-install commands
    if [[ -n "$post_install" ]]; then
        eval "$post_install"
    fi
done

log "Assets instalados com sucesso."
