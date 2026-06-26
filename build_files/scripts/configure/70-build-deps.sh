#!/bin/bash
# Remove as dependências de build (compiladores, devel headers, sass) que foram
# instaladas no Layer 1 só para compilar temas/efeitos e já não são necessárias
# na imagem final.
set -euo pipefail

# shellcheck source=../shared/common.sh
source /ctx/scripts/shared/common.sh
install_error_trap

# BUILD_DEPS vem de shared/package-lists.sh (mesma lista usada na instalação).
# shellcheck source=../shared/package-lists.sh
source /ctx/scripts/shared/package-lists.sh

mapfile -t FOUND_BUILD_DEPS < <(installed_packages_from "${BUILD_DEPS[@]}")
[[ ${#FOUND_BUILD_DEPS[@]} -gt 0 ]] && dnf5 remove -y --setopt=clean_requirements_on_remove=False "${FOUND_BUILD_DEPS[@]}"
