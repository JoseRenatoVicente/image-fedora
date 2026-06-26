#!/bin/bash
# Layer 2 — driver de configuração.
# Orquestra os módulos em build_files/configure/ (overlay, theming, skel, KDE,
# serviços, hardening, initramfs, cleanup) e os scripts de validação em
# build_files/shared/. Os pacotes já foram instalados pelo Layer 1
# (build-packages.sh). Cache invalidado quando qualquer ficheiro em
# build_files/ muda.
set -euo pipefail

# shellcheck source=shared/common.sh
source /ctx/scripts/shared/common.sh
install_error_trap

# Exportar variáveis de imagem para sub-scripts (image-info.sh, etc.)
export IMAGE_NAME="${IMAGE_NAME:-fedora}"
export IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Fedora}"
export IMAGE_VENDOR="${IMAGE_VENDOR:-}"
export SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"
# SOURCE_DATE_EPOCH só deve ser exportado quando tem um valor numérico válido
if [[ "${SOURCE_DATE_EPOCH:-}" =~ ^[0-9]+$ ]]; then
    export SOURCE_DATE_EPOCH
else
    unset SOURCE_DATE_EPOCH
fi

CONFIGURE_DIR="/ctx/scripts/configure"

# Corre um módulo de configuração, embrulhando-o num grupo de log do GitHub
# Actions. Os módulos não emitem ::group:: próprios — é o driver que o faz.
run_step() {
    local script="$1"
    echo "::group:: $(basename "$script")"
    trap 'echo "::endgroup::"' RETURN
    bash "$script"
    trap - RETURN
    echo "::endgroup::"
}

# ─── Configuração (ordem importa: 10 espelha a árvore antes dos restantes) ────
run_step "$CONFIGURE_DIR/10-system.sh"
run_step "$CONFIGURE_DIR/20-plasmalogin.sh"
run_step "$CONFIGURE_DIR/30-theming.sh"
run_step "$CONFIGURE_DIR/40-skel-kde.sh"
run_step "$CONFIGURE_DIR/50-services.sh"
run_step "$CONFIGURE_DIR/60-selinux-suid.sh"
run_step "$CONFIGURE_DIR/70-build-deps.sh"
run_step "$CONFIGURE_DIR/80-initramfs.sh"
run_step "$CONFIGURE_DIR/90-cleanup.sh"

# ─── Validação + metadados (sem rede → seguros antes da crypto policy) ────────
# Estes scripts já emitem o seu próprio ::group::, por isso são chamados direto.
/ctx/scripts/shared/validate-repos.sh
/ctx/scripts/shared/image-info.sh

# ─── Crypto policy (penúltimo: FUTURE bloqueia downloads, ver módulo) ─────────
run_step "$CONFIGURE_DIR/95-crypto.sh"

# ─── Tests (após crypto policy para validar FUTURE) ──────────────────────────
/ctx/scripts/shared/tests.sh
