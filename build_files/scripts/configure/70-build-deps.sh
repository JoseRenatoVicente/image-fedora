#!/bin/bash
# Remove as dependências de build (compiladores, devel headers, sass) que foram
# instaladas no Layer 1 só para compilar temas/efeitos e já não são necessárias
# na imagem final.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# BUILD_DEPS vem de shared/package-lists.sh (mesma lista usada na instalação).
# shellcheck source=../shared/package-lists.sh
source /ctx/scripts/shared/package-lists.sh

FOUND_BUILD_DEPS=()
for pkg in "${BUILD_DEPS[@]}"; do
    rpm -q "$pkg" &>/dev/null && FOUND_BUILD_DEPS+=("$pkg")
done
[[ ${#FOUND_BUILD_DEPS[@]} -gt 0 ]] && dnf5 remove -y --setopt=clean_requirements_on_remove=True "${FOUND_BUILD_DEPS[@]}"
