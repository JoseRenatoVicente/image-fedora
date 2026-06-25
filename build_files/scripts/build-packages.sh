#!/bin/bash
# Layer 1 — pacotes dnf + COPR
# Ficheiros necessários: /ctx-pkgs/{build-packages.sh,shared/copr-helpers.sh,configs/dnf-performance.conf}
# Cache invalidado apenas quando a lista de pacotes ou os helpers mudam.
set -euo pipefail

trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

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
FOUND_PKGS=()
for pkg in "${REMOVE_PACKAGES[@]}"; do
    rpm -q "$pkg" &>/dev/null && FOUND_PKGS+=("$pkg")
done
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

# ─── COPR packages (isolados) ────────────────────────────────────────────────
echo "::group:: COPR packages"
# kwin-effect-roundcorners não está nos repos Fedora
copr_install_isolated "matinlotfali/KDE-Rounded-Corners" \
    kwin-effect-roundcorners kwin-effect-roundcorners-x11 \
    || echo "WARN: kwin-effect-roundcorners não instalado"
# scx-scheds não está nos repos padrão do Fedora (disponível via COPR sched_ext)
copr_install_isolated "sched_ext/scx" \
    scx-scheds \
    || echo "WARN: scx-scheds não instalado"
# keyd (remapeamento de teclado ao nível do uinput) não está nos repos Fedora —
# vem do COPR alternateved/keyd, que tem builds fedora-44. Best-effort: se o COPR
# estiver indisponível, a config /etc/keyd/default.conf (via overlay) ainda é
# aplicada e os testes de keyd ficam em skip.
copr_install_isolated "alternateved/keyd" \
    keyd \
    || echo "WARN: keyd não instalado (COPR indisponível); apenas a config é aplicada"
echo "::endgroup::"

# ─── Remove weak deps / orphan bloat ───────────────────────────────────────────
echo "::group:: Remove weak deps e pacotes órfãos"
# Estes pacotes são puxados como recommends/weak-deps de outras partes do stack
# (ex.: qt6-qtspeech → flite) e não são requeridos por nada na imagem final.
# A remoção explícita evita que o bloat de TTS (text-to-speech) fique na ISO.
ORPHAN_BLOAT=(
    qt6-qtspeech
    qt6-qtspeech-flite
    espeak-ng
    flite
    lpcnetfreedv
)
FOUND_ORPHAN=()
for pkg in "${ORPHAN_BLOAT[@]}"; do
    rpm -q "$pkg" &>/dev/null && FOUND_ORPHAN+=("$pkg")
done
if [[ ${#FOUND_ORPHAN[@]} -gt 0 ]]; then
    dnf5 remove -y --setopt=clean_requirements_on_remove=True "${FOUND_ORPHAN[@]}"
    echo "Removidos ${#FOUND_ORPHAN[@]} pacotes órfãos: ${FOUND_ORPHAN[*]}"
else
    echo "Nenhum pacote órfão de TTS encontrado."
fi
echo "::endgroup::"
