#!/bin/bash
set -euo pipefail

trap '[[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

TMPDIR_PC="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_PC"' EXIT

log "Baixando Panel Colorizer v7.2.0"
curl -L --fail --retry 3 --retry-delay 5 \
  -o "$TMPDIR_PC/panel-colorizer.tar.gz" \
  "https://github.com/luisbocanegra/plasma-panel-colorizer/archive/refs/tags/v7.2.0.tar.gz"
tar -xzf "$TMPDIR_PC/panel-colorizer.tar.gz" -C "$TMPDIR_PC"
PC_SRC="$(find "$TMPDIR_PC" -maxdepth 1 -type d -name 'plasma-panel-colorizer-*' | head -n1)"
[[ -n "$PC_SRC" ]] || { echo "ERROR: diretório plasma-panel-colorizer não encontrado em $TMPDIR_PC"; exit 1; }
mv "$PC_SRC" "$TMPDIR_PC/plasma-panel-colorizer"

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
