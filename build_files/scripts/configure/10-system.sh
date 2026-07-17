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
# Fedora bases may ship /usr/bin/dnf as a symlink to dnf5; remove it so the
# immutable dnf wrapper does not overwrite /usr/bin/dnf5 through the symlink.
rm -f /usr/bin/dnf
cp -aT /ctx/overlay/usr/ /usr/

# The build runs with a restrictive umask, but desktop/user daemons must be able
# to read public configuration from /etc and /usr/share. Keep explicit secrets
# out of these lists; root-only files such as shadow, sudoers and host keys are
# handled separately below or by their owning packages.
for public_config in \
    /etc/locale.conf \
    /etc/motd \
    /etc/timezone \
    /etc/vconsole.conf \
    /usr/share/qt6/qtlogging.ini \
    /usr/share/wireplumber/wireplumber.conf.d/51-disable-suspension.conf; do
    [[ -e "$public_config" ]] && chmod 0644 "$public_config"
done

for public_config_dir in \
    /etc/dracut.conf.d \
    /etc/modprobe.d \
    /etc/profile.d \
    /etc/security/limits.d \
    /etc/skel \
    /etc/sysctl.d \
    /etc/systemd \
    /etc/tmpfiles.d \
    /etc/xdg \
    /usr/lib/systemd/system \
    /usr/lib/systemd/system-preset; do
    [[ -d "$public_config_dir" ]] && find "$public_config_dir" -type f -exec chmod 0644 {} +
done

# systemd-sysusers is the single authority for system accounts. Copying the
# altfiles databases into /etc freezes their previous UID allocation; adding a
# new account later can then make two services share an UID (for example,
# dnsmasq and cosmic-greeter). Materialize the current sysusers definitions
# only after all package transactions and overlays are in place.
echo "Materializando contas de sistema com systemd-sysusers..."
systemd-sysusers

# Executables from the mirrored tree need explicit permission bits.
chmod 755 /usr/bin/dnf
chmod 755 /usr/libexec/fedora-shell-setup \
          /usr/libexec/fedora-dev-setup \
          /usr/libexec/fedora-brew-setup \
          /usr/libexec/fedora-toolbox-setup \
          /usr/libexec/fedora-first-setup-runner \
          /usr/libexec/zram-recompress \
          /usr/libexec/image-fedora-selinux-setup
# Wrappers docker-cli usados pelo VSCode (Flatpak) via flatpak-spawn --host —
# ver dev.containers.dockerPath no settings.json do skel.
chmod 755 /etc/skel/.local/bin/docker-host \
          /etc/skel/.local/bin/docker-compose-host
chmod 755 /usr/bin/tpm2-luks-enroll
chmod 755 /usr/bin/tpm2-first-enroll
chmod 755 /usr/bin/tpm2-reenroll-check
chmod 755 /usr/bin/mok-enroll
chmod 755 /usr/bin/sd-boot-migrate-enable
# /etc/ld.so.preload: root-only (0600) — applied by the dynamic linker to ALL
# processes including setuid binaries. World-readable would leak what's preloaded
# and historically root-only is the convention for this file.
chmod 600 /etc/ld.so.preload

# sudoers.d TÊM de ser 0440 (git só preserva 0644): um drop-in group/world-writable
# é ignorado pelo sudo e gera aviso em cada invocação. Validar a sintaxe também.
chmod 0440 /etc/sudoers.d/10-cis-hardening
visudo -cf /etc/sudoers.d/10-cis-hardening

# Wireplumber: bloquear Steam de limpar defaults de áudio (equiv. ao patch Nobara)
mv /usr/bin/wpctl /usr/bin/wpctl.real
install -Dm755 /ctx/assets/configs/wpctl-steam-wrapper /usr/bin/wpctl

# login.defs: UMASK 027 (ficheiros novos não são world-readable por defeito)
# e YESCRYPT_COST_FACTOR 8 (hashing de password mais resistente a brute-force)
sed -i 's/^UMASK\s\+022/UMASK\t\t027/' /etc/login.defs
sed -i 's/^#\?YESCRYPT_COST_FACTOR.*/YESCRYPT_COST_FACTOR 8/' /etc/login.defs
# Envelhecimento de passwords (NSA/STIG)
sed -i 's/^#\?PASS_MAX_DAYS.*/PASS_MAX_DAYS\t60/'  /etc/login.defs
sed -i 's/^#\?PASS_MIN_DAYS.*/PASS_MIN_DAYS\t1/'   /etc/login.defs
sed -i 's/^#\?PASS_WARN_AGE.*/PASS_WARN_AGE\t7/'   /etc/login.defs

# STIG RHEL-09-411050 — desativa contas após 35 dias de inatividade. Aplica-se a
# contas criadas depois (default em /etc/default/useradd).
useradd -D -f 35

# Anotar ficheiros de hardening com metadados de componente
setfattr -n user.component -v "security-hardening" \
    /usr/bin/tpm2-luks-enroll \
    /usr/bin/tpm2-first-enroll \
    /usr/bin/tpm2-reenroll-check \
    /usr/lib/systemd/system/tpm2-first-enroll.service \
    /usr/lib/systemd/system/tpm2-reenroll-check.service \
    /usr/bin/mok-enroll \
    /usr/bin/sd-boot-migrate-enable \
    /etc/dracut.conf.d/90-luks-security.conf \
    /etc/ld.so.preload \
    /etc/sysctl.d/60-security-hardening.conf \
    /etc/sysctl.d/61-ptrace-scope.conf \
    /etc/modprobe.d/security-hardening.conf \
    /etc/modprobe.d/blacklist-framebuffer.conf \
    /usr/lib/bootc/kargs.d/10-hardening.toml \
    /usr/lib/udev/rules.d/99-hardening.rules \
    /etc/dracut.conf.d/03-storage-drivers.conf \
    /etc/issue \
    /etc/issue.net \
    /etc/motd \
    /etc/sudoers.d/10-cis-hardening \
    /etc/audit/rules.d/60-cis-hardening.rules \
    /etc/tmpfiles.d/audit-log-dir.conf \
    /etc/security/pwhistory.conf \
    /etc/fstab \
    /usr/lib/bootc/kargs.d/30-audit.toml \
    /usr/lib/systemd/system/selinux-booleans.service \
    /usr/libexec/image-fedora-selinux-setup

setfattr -n user.component -v "image-config" \
    /etc/dracut.conf.d/10-boot-performance.conf \
    /etc/systemd/system/tuned.service.d/deferred.conf \
    /etc/systemd/system/tuned-ppd.service.d/no-block-multiuser.conf \
    /etc/sysctl.d/99-performance.conf \
    /usr/share/image-fedora/low-resource/100-low-resource.conf \
    /usr/lib/systemd/system/low-resource-tuning.service \
    /etc/systemd/zram-generator.conf \
    /usr/lib/systemd/system/zram-recompress.service \
    /usr/lib/systemd/system/zram-recompress.timer \
    /usr/libexec/zram-recompress \
    /etc/systemd/system/user.slice.d/15-memory-high.conf \
    /etc/xdg/autostart/geoclue-demo-agent.desktop \
    /usr/lib/bootc/kargs.d/20-performance.toml \
    /usr/lib/tmpfiles.d/thp-tuning.conf \
    /etc/systemd/system/user@.service.d/10-delegate.conf \
    /etc/systemd/system.conf.d/10-nofile-limit.conf \
    /etc/systemd/user.conf.d/10-nofile-limit.conf \
    /usr/lib/systemd/system/amd-cpb-boost.service \
    /usr/lib/systemd/system/intel-pstate-floor.service \
    /usr/lib/systemd/system/cpu-epp-tune.service \
    /etc/systemd/resolved.conf.d/60-security-dns.conf \
    /etc/systemd/resolved.conf.d/10-disable-llmnr.conf \
    /etc/chrony.conf \
    /etc/security/pwquality.conf \
    /etc/security/faillock.conf \
    /usr/lib/NetworkManager/conf.d/40-hardening.conf \
    /usr/lib/systemd/system-preset/35-security-desktop.preset \
    /etc/systemd/journald.conf.d/size-limit.conf \
    /etc/profile.d/tmout.sh \
    /etc/scx_loader/config.toml \
    /etc/security/limits.d/60-gaming-nice.conf \
    /usr/lib/tuned/profiles/balanced-workstation/tuned.conf \
    /usr/lib/tuned/profiles/balanced-workstation/script.sh \
    /usr/lib/tuned/profiles/throughput-performance-workstation/tuned.conf \
    /usr/lib/tuned/profiles/throughput-performance-workstation/script.sh \
    /usr/lib/tuned/profiles/powersave-workstation/tuned.conf \
    /usr/lib/tuned/profiles/powersave-workstation/script.sh \
    /etc/tuned/active_profile \
    /etc/tuned/profile_mode
