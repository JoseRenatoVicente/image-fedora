#!/bin/bash
# Layer 1 — pacotes dnf + COPR
# Ficheiros necessários: /ctx-pkgs/{build-packages.sh,shared/copr-helpers.sh,configs/dnf-performance.conf}
# Cache invalidado apenas quando a lista de pacotes ou os helpers mudam.
set -euo pipefail

# shellcheck source=shared/common.sh
source /ctx-pkgs/shared/common.sh
install_error_trap

# shellcheck source=shared/copr-helpers.sh
source /ctx-pkgs/shared/copr-helpers.sh
# shellcheck source=shared/package-lists.sh
source /ctx-pkgs/shared/package-lists.sh

# ─── Setup ────────────────────────────────────────────────────────────────────
echo "::group:: Setup"
install -Dm644 /ctx-pkgs/configs/dnf-performance.conf /etc/dnf/conf.d/performance.conf
# Garante que o módulo ostree fica em TODOS os initramfs gerados durante o build,
# incluindo os disparados por scripts de pacotes — sem isto o initrd-switch-root
# falha porque ostree-prepare-root.service está ausente do initrd.
echo 'add_dracutmodules+=" ostree "' > /etc/dracut.conf.d/01-ostree-required.conf
echo "::endgroup::"

# ─── Remove base-atomic bloat ─────────────────────────────────────────────────
echo "::group:: Remove base-atomic bloat"

# Substituir glibc-all-langpacks por langpacks mínimos (pt_BR + en_US).
# Deve ser feito ANTES da remoção em massa porque glibc exige pelo menos um
# glibc-langpack — remover glibc-all-langpacks sem alternativa falha o resolver.
dnf5 install -y --allowerasing glibc-langpack-pt glibc-langpack-en
dnf5 remove -y glibc-all-langpacks

# REMOVE_PACKAGES vem de shared/package-lists.sh (fonte única).
mapfile -t FOUND_PKGS < <(installed_packages_from "${REMOVE_PACKAGES[@]}")
if [[ ${#FOUND_PKGS[@]} -gt 0 ]]; then
    dnf5 remove -y --setopt=clean_requirements_on_remove=False "${FOUND_PKGS[@]}"
    echo "Removidos ${#FOUND_PKGS[@]} pacotes: ${FOUND_PKGS[*]}"
else
    echo "Nenhum pacote de bloat encontrado."
fi
echo "::endgroup::"

# ─── Install Fedora packages ──────────────────────────────────────────────────
echo "::group:: Install packages"
# INSTALL_PACKAGES, INSTALL_EXCLUDES e BUILD_DEPS vêm de shared/package-lists.sh.
# BUILD_DEPS são instaladas aqui e removidas no Layer 2 (configure/70-build-deps.sh).
dnf5 install -y --allowerasing \
    --setopt=install_weak_deps=False \
    "${INSTALL_EXCLUDES[@]/#/--exclude=}" \
    "${INSTALL_PACKAGES[@]}" \
    "${BUILD_DEPS[@]}"
echo "::endgroup::"

# ─── SCX scheduler (best-effort) ─────────────────────────────────────────────
# scx-scheds/scx-tools podem não estar disponíveis em todos os snapshots de repo.
# Instalados separadamente para não bloquear a transação principal.
echo "::group:: SCX scheduler"
SCX_AVAILABLE=$(dnf5 repoquery --available --queryformat '%{name}' scx-scheds scx-tools 2>/dev/null | sort -u || true)
if grep -qx 'scx-scheds' <<<"$SCX_AVAILABLE" && grep -qx 'scx-tools' <<<"$SCX_AVAILABLE"; then
    dnf5 install -y scx-scheds scx-tools
else
    echo "INFO: scx-scheds/scx-tools não disponíveis nos repos; scheduler SCX inactivo"
fi
echo "::endgroup::"

# ─── COPR packages (isolados) ────────────────────────────────────────────────
echo "::group:: COPR packages"
# keyd (remapeamento de teclado ao nível do uinput) não está nos repos Fedora —
# vem do COPR alternateved/keyd, que tem builds fedora-44. Best-effort: se o COPR
# estiver indisponível, a config /etc/keyd/default.conf (via overlay) ainda é
# aplicada e os testes de keyd ficam em skip.
copr_install_isolated "alternateved/keyd" \
    keyd \
    || echo "WARN: keyd não instalado (COPR indisponível); apenas a config é aplicada"
# hardened_malloc (GrapheneOS-derived heap allocator): detecta use-after-free,
# heap overflows e double-free. Não está nos repos Fedora — vem do COPR
# secureblue/packages. Activado globalmente via /etc/ld.so.preload e
# DefaultEnvironment do systemd, por isso é obrigatório se a configuração o
# referencia. Falhar aqui evita uma imagem com preload quebrado.
copr_install_isolated "secureblue/packages" \
    hardened_malloc
echo "::endgroup::"

# flite/lpcnetfreedv parecem bloat, mas no Fedora 44 a transação de remoção
# arrasta ffmpeg-free (usado por pipewire/gstreamer/cosmic-files para media e
# thumbnails). Mantemos essa pilha para preservar o runtime validado em
# shared/tests.sh — ver nota junto a UNWANTED_PACKAGES em package-lists.sh.

# ─── Checkpoint da rpmdb (sqlite) ────────────────────────────────────────────
# O backend sqlite do rpm mantém um WAL (rpmdb.sqlite-wal) que só é fundido no
# ficheiro principal quando a última conexão fecha de forma limpa. Este RUN
# termina aqui e a camada é commitada pelo buildah a seguir — se o WAL não for
# consolidado antes disso, o Layer 2 (noutro processo/camada) abre uma rpmdb.sqlite
# desatualizada e "rpm -q" passa a reportar o estado ANTERIOR a este script
# inteiro (pacotes removidos parecem instalados, pacotes instalados parecem
# ausentes), mesmo com os ficheiros reais já corretos em disco. Forçamos o
# checkpoint explicitamente para garantir que a rpmdb committed na imagem
# reflete as instalações/remoções acima.
echo "::group:: Checkpoint rpmdb"
rpmdb --rebuilddb || {
    rebuild_dir="$(find /usr/share -maxdepth 1 -type d -name 'rpmrebuilddb.*' | sort | tail -1)"
    if [[ -n "$rebuild_dir" ]]; then
        rm -f /usr/share/rpm/rpmdb.sqlite /usr/share/rpm/rpmdb.sqlite-shm \
            /usr/share/rpm/rpmdb.sqlite-wal /usr/share/rpm/.rpm.lock
        cp -a "$rebuild_dir"/. /usr/share/rpm/
        rm -rf "$rebuild_dir"
    else
        echo "FATAL: rpmdb --rebuilddb falhou e nenhum rpmrebuilddb.* encontrado para recuperar" >&2
        exit 1
    fi
}
echo "::endgroup::"
