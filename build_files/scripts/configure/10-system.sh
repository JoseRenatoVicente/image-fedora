#!/bin/bash
# Configuração base do sistema: overlay da árvore espelhada, permissões dos
# executáveis, wrapper wpctl (Steam), hardening do login.defs e anotação de
# metadados de componente nos ficheiros de config.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Remove repos rpmfusion
rm -f /etc/yum.repos.d/rpmfusion-*.repo

# Mirrored filesystem tree: each file already lives at its final path under
# build_files/etc/ and build_files/usr/; cp -aT overlays them in one shot.
cp -aT /ctx/overlay/etc/ /etc/
cp -aT /ctx/overlay/usr/ /usr/

# Executables from the mirrored tree need explicit permission bits.
chmod 755 /usr/bin/dnf
chmod 755 /usr/libexec/fedora-flatpak-setup \
          /usr/libexec/fedora-shell-setup \
          /usr/libexec/fedora-dev-setup \
          /usr/libexec/fedora-brew-setup

# Wireplumber: bloquear Steam de limpar defaults de áudio (equiv. ao patch Nobara)
mv /usr/bin/wpctl /usr/bin/wpctl.real
install -Dm755 /ctx/assets/configs/wpctl-steam-wrapper /usr/bin/wpctl

# login.defs: UMASK 027 (ficheiros novos não são world-readable por defeito)
# e YESCRYPT_COST_FACTOR 8 (hashing de password mais resistente a brute-force)
sed -i 's/^UMASK\s\+022/UMASK\t\t027/' /etc/login.defs
sed -i 's/^#\?YESCRYPT_COST_FACTOR.*/YESCRYPT_COST_FACTOR 8/' /etc/login.defs

# Anotar ficheiros de hardening com metadados de componente
setfattr -n user.component -v "security-hardening" \
    /etc/sysctl.d/60-security-hardening.conf \
    /etc/sysctl.d/61-ptrace-scope.conf \
    /etc/modprobe.d/security-hardening.conf \
    /etc/modprobe.d/blacklist-framebuffer.conf \
    /usr/lib/bootc/kargs.d/10-hardening.toml \
    /usr/lib/udev/rules.d/99-hardening.rules

setfattr -n user.component -v "image-config" \
    /etc/sysctl.d/99-performance.conf \
    /usr/lib/bootc/kargs.d/20-performance.toml \
    /usr/lib/tmpfiles.d/thp-tuning.conf \
    /etc/systemd/system/user@.service.d/10-delegate.conf \
    /etc/systemd/system.conf.d/10-nofile-limit.conf \
    /etc/systemd/user.conf.d/10-nofile-limit.conf \
    /etc/systemd/resolved.conf.d/60-security-dns.conf \
    /etc/systemd/resolved.conf.d/10-disable-llmnr.conf \
    /etc/chrony.conf \
    /etc/security/pwquality.conf \
    /etc/security/faillock.conf \
    /usr/lib/NetworkManager/conf.d/40-hardening.conf \
    /usr/lib/systemd/system-preset/35-security-desktop.preset \
    /etc/xdg/kwinrc \
    /etc/xdg/kdeglobals \
    /etc/systemd/journald.conf.d/size-limit.conf \
    /etc/plasmalogin.conf.d/10-theme.conf
