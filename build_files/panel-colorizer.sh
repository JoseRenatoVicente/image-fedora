#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

TMPDIR_PC="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_PC"' EXIT

log "Clonando Panel Colorizer v7.2.0"
git clone --depth=1 --branch v7.2.0 https://github.com/luisbocanegra/plasma-panel-colorizer \
  "$TMPDIR_PC/plasma-panel-colorizer"

cd "$TMPDIR_PC/plasma-panel-colorizer"

# ── Plasmoid QML (package/) ───────────────────────────────────────────────────
# Copia directamente para /usr/share/plasma/plasmoids/ sem kpackagetool6.
# install.sh usa sudo que falha em container build (sem sessão PAM).
META="package/metadata.json"
if [[ -f "$META" ]]; then
    PLUGIN_ID=$(python3 -c \
        "import json; d=json.load(open('$META')); print(d.get('KPlugin',{}).get('Id',''))" \
        2>/dev/null || echo "")
    if [[ -n "$PLUGIN_ID" ]]; then
        log "Instalando plasmoid QML: $PLUGIN_ID"
        mkdir -p "/usr/share/plasma/plasmoids/$PLUGIN_ID"
        rsync -a "package/" "/usr/share/plasma/plasmoids/$PLUGIN_ID/"
        echo "OK: /usr/share/plasma/plasmoids/$PLUGIN_ID"
    else
        echo "WARN: plugin ID vazio em $META — plasmoid não instalado" >&2
    fi
else
    echo "WARN: $META não encontrado — plasmoid não instalado" >&2
fi

# ── Plugin C++ ────────────────────────────────────────────────────────────────
# Compila e instala sem sudo: somos root dentro do container build.
# Usa sempre o CMakeLists.txt da raiz (plugin/ é subdirectório, não standalone).
if [[ -f "CMakeLists.txt" ]]; then
    log "Construindo plugin C++"
    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build --parallel "$(nproc)"
    cmake --install build
else
    log "Sem CMakeLists.txt — apenas plasmoid QML"
fi

log "Panel Colorizer instalado."
