#!/bin/bash
# Serviços systemd + perfil tuned + authselect. Verifica também que o
# flathub.flatpakrepo estático chegou pela árvore espelhada (10-system.sh).
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Habilita units só quando existem. Um pacote opcional ou de COPR ausente
# (ex.: COPR indisponível para a arquitectura, ou unit que não existe em todas
# as versões da base) não deve abortar a build no enable — com set -e, um
# `systemctl enable` sobre uma unit inexistente mataria todo o build.
enable_unit() {
    local unit
    for unit in "$@"; do
        if systemctl list-unit-files "$unit" &>/dev/null; then
            systemctl enable "$unit"
        else
            echo "INFO: $unit ausente nesta base, ignorando"
        fi
    done
}

enable_unit \
    podman.socket \
    tuned.service \
    earlyoom.service \
    firewalld.service \
    chronyd.service \
    rpm-ostreed-automatic.timer \
    podman-auto-update.timer \
    flatpak-system-update.timer \
    dconf-update.service \
    flatpak-nuke-fedora.service \
    flathub-system-setup.service \
    keyd.service \
    thermald.service \
    irqbalance.service \
    systemd-oomd.service

if rpm -q scx-scheds &>/dev/null; then
    install -Dm644 /ctx/assets/configs/scx-default.conf /etc/default/scx
    setfattr -n user.component -v "image-config" /etc/default/scx
    enable_unit scx.service
fi

# bolt e fwupd são D-Bus/udev-activated; o enable não é necessário (nem funciona no container)
systemctl preset power-profiles-daemon.service 2>/dev/null || true

# Mascarar serviços desnecessários (boot mais rápido + menos superfície):
#   NetworkManager-wait-online — bloqueia o boot à espera da rede
#   ModemManager               — sem modem celular neste hardware (pacote removido)
#   avahi-daemon(.socket)      — mDNS/zeroconf não usado no perfil seguro
#   ctrl-alt-del.target        — bloqueia reboot físico via consola
# plymouth-quit-wait NÃO é mascarado (preservar o splash Plymouth afinado).
# Mascarar funciona mesmo para units de pacotes ausentes (symlink → /dev/null).
systemctl mask \
    NetworkManager-wait-online.service \
    ModemManager.service \
    avahi-daemon.service \
    avahi-daemon.socket \
    systemd-remount-fs.service
systemctl mask --force ctrl-alt-del.target

mkdir -p /etc/tuned
echo "balanced" > /etc/tuned/active_profile
echo "auto" > /etc/tuned/profile_mode

if command -v authselect >/dev/null 2>&1; then
    authselect current --raw &>/dev/null || authselect select minimal --force
    authselect enable-feature with-fingerprint || true
    authselect enable-feature with-faillock || true
fi

# flathub.flatpakrepo é um ficheiro estático: vem da árvore espelhada
# (build_files/usr/share/flatpak/) via o cp -aT do 10-system.sh — sem rede.
[[ -f /usr/share/flatpak/flathub.flatpakrepo ]] \
    || { echo "FATAL: /usr/share/flatpak/flathub.flatpakrepo ausente da árvore espelhada"; exit 1; }
