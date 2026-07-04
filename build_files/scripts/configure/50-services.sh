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
    sshd.service \
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
    systemd-oomd.service \
    auditd.service \
    sd-boot-migrate.service \
    selinux-booleans.service \
    amd-cpb-boost.service \
    tpm2-first-enroll.service

# /tmp como tmpfs (CIS 1.1.2.1) — a unit upstream já traz nosuid,nodev nas Options.
# Fora do enable_unit: se a base marcar tmp.mount como 'static', o `enable` falha e
# NÃO deve abortar o build; nesse caso /tmp continua no rootfs (protegido pelos
# fs.protected_* sysctls). auditd tem [Install] e vai pelo enable_unit.
# NOTA: /dev/shm é configurado via /etc/fstab (CIS 1.1.2.3) — systemd recusa
# unidades .mount para API filesystems gerenciados pelo kernel.
systemctl enable tmp.mount 2>/dev/null \
    || echo "INFO: tmp.mount não habilitável (static/ausente); /tmp permanece no rootfs"

if rpm -q scx-tools &>/dev/null; then
    enable_unit scx_loader.service
fi

# libvirt: socket activation (só arranca quando necessário; sem overhead no boot)
if rpm -q libvirt &>/dev/null; then
    enable_unit libvirtd.socket virtlogd.socket virtlockd.socket
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
    systemd-remount-fs.service \
    irqbalance.service \
    lm_sensors.service \
    geoclue.service \
    rpcbind.service \
    rpcbind.socket \
    rpcbind.target \
    nfs-server.service \
    nfsdcld.service \
    rpc-statd.service \
    rpc-gssd.service \
    rpc-statd-notify.service \
    gssproxy.service \
    nfs-blkmap.service \
    nfs-idmapd.service \
    nfs-mountd.service \
    nfs-client.target \
    iscsid.service \
    iscsid.socket \
    iscsiuio.service
systemctl mask --force ctrl-alt-del.target

# bluetoothd ConfigurationDirectoryMode=0555 exige este modo; o pacote cria com 755.
chmod 555 /etc/bluetooth

if command -v authselect >/dev/null 2>&1; then
    authselect current --raw &>/dev/null || authselect select minimal --force
    authselect enable-feature with-fingerprint || true
    authselect enable-feature with-faillock || true
    # CIS §5.3.3.4 — histórico de passwords. with-pwhistory pode não existir em
    # todas as versões do authselect; é best-effort. Se falhar, o pwhistory.conf
    # fica presente mas inativo no stack (sem quebrar o PAM/login).
    authselect enable-feature with-pwhistory 2>/dev/null \
        || echo "INFO: authselect sem with-pwhistory; pwhistory.conf presente mas inativo no stack"
fi

# flathub.flatpakrepo é um ficheiro estático: vem da árvore espelhada
# (build_files/usr/share/flatpak/) via o cp -aT do 10-system.sh — sem rede.
[[ -f /usr/share/flatpak/flathub.flatpakrepo ]] \
    || { echo "FATAL: /usr/share/flatpak/flathub.flatpakrepo ausente da árvore espelhada"; exit 1; }
