#!/bin/bash
# Remove as dependências de build (sbsigntools, systemd-ukify) instaladas no
# Layer 1 só para assinatura Secure Boot / composição do UKI — já não são
# necessárias na imagem final.
set -euo pipefail

# shellcheck source=../shared/common.sh
source /ctx/scripts/shared/common.sh
install_error_trap

# BUILD_DEPS vem de shared/package-lists.sh (mesma lista usada na instalação).
# shellcheck source=../shared/package-lists.sh
source /ctx/scripts/shared/package-lists.sh

mapfile -t FOUND_BUILD_DEPS < <(installed_packages_from "${BUILD_DEPS[@]}")
[[ ${#FOUND_BUILD_DEPS[@]} -gt 0 ]] && dnf5 remove -y --setopt=clean_requirements_on_remove=False "${FOUND_BUILD_DEPS[@]}"

# clean_requirements_on_remove=False acima é intencional (ver commit b176365):
# com True, a cascata do dnf5 podia apanhar pacotes do runtime ainda em uso.
# Calculamos os órfãos reais AGORA (pós-remoção do BUILD_DEPS) via
# repoquery --unneeded em vez de listar nomes fixos, para não ficar
# desatualizado quando as versões dos pacotes mudarem.
mapfile -t ORPHANED_DEPS < <(dnf5 repoquery --unneeded --qf '%{name}\n' 2>/dev/null)
[[ ${#ORPHANED_DEPS[@]} -gt 0 ]] && dnf5 remove -y --setopt=clean_requirements_on_remove=False "${ORPHANED_DEPS[@]}"

# NOTA: flite e lpcnetfreedv reaparecem depois do INSTALL_PACKAGES (Layer 1) e
# NÃO são removidos aqui de propósito — ver comentário junto a UNWANTED_PACKAGES
# em shared/package-lists.sh. ffmpeg-free liga-se a libflite.so (dependência por
# soname, invisível a `rpm -q --whatrequires flite`) e codec2 tem hard-Requires
# em lpcnetfreedv; removê-los arrasta plasma-desktop/plasma-workspace/kwin/
# dolphin/ffmpeg-free (confirmado ao vivo). Ficam como bloat aceite.
