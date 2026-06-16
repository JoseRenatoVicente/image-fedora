#!/bin/bash
# Layer 2 — configuração, theming, skel, dracut, cleanup
# Cache invalidado quando qualquer ficheiro em build_files/ muda.
# Os pacotes já estão instalados pelo Layer 1 (build-packages.sh).
#
# Este script é um orquestrador fino: carrega o setup comum e depois
# executa cada módulo em ordem numérica.

source /ctx/configure/_common.sh

for module in /ctx/configure/[0-9][0-9]-*.sh; do
    echo "── Módulo: $(basename "$module") ──"
    # shellcheck source=/dev/null
    source "$module"
done
