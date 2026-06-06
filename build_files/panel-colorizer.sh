#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

TMPDIR_PC="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_PC"' EXIT

log "Clonando Panel Colorizer"
git clone --depth=1 https://github.com/luisbocanegra/plasma-panel-colorizer \
  "$TMPDIR_PC/plasma-panel-colorizer"

# Cria HOME falso para o install.sh instalar sem sessão de usuário
FAKE_HOME="$TMPDIR_PC/fakehome"
mkdir -p "$FAKE_HOME"

log "Instalando Panel Colorizer (HOME temporário)"
(
  cd "$TMPDIR_PC/plasma-panel-colorizer"
  export HOME="$FAKE_HOME"
  # install.sh usa kpackagetool6 ou cópia direta dependendo da versão
  if [[ -f install.sh ]]; then
    bash ./install.sh
  else
    echo "ERRO: install.sh não encontrado no repositório do Panel Colorizer" >&2
    exit 1
  fi
)

# Copia o plasmoid instalado para /usr/share/ (system-wide)
PLASMOID_SRC=""
if [[ -d "$FAKE_HOME/.local/share/plasma/plasmoids" ]]; then
  PLASMOID_SRC="$FAKE_HOME/.local/share/plasma/plasmoids"
fi

if [[ -n "$PLASMOID_SRC" ]]; then
  log "Movendo Panel Colorizer para /usr/share/plasma/plasmoids/"
  mkdir -p /usr/share/plasma/plasmoids
  cp -r "$PLASMOID_SRC"/. /usr/share/plasma/plasmoids/
else
  # Fallback: copia o diretório package diretamente
  log "Fallback: copiando package/ diretamente para /usr/share/plasma/plasmoids/"
  PACKAGE_DIR="$(find "$TMPDIR_PC/plasma-panel-colorizer" -maxdepth 2 -type d -name 'luisbocanegra.panelcolorizer*' | head -n1 || true)"
  if [[ -n "$PACKAGE_DIR" ]]; then
    mkdir -p /usr/share/plasma/plasmoids
    cp -r "$PACKAGE_DIR" /usr/share/plasma/plasmoids/
  else
    echo "WARN: Panel Colorizer não encontrado após instalação. Pulando." >&2
  fi
fi

log "Panel Colorizer instalado."
