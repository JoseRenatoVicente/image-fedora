#!/usr/bin/env bats
# Container tests — run inside the built image
# Tests: security hardening, crypto, sysctl, ZRAM, login.defs, SELinux, boot, initramfs
# shellcheck disable=SC2012  # nomes de versão de kernel são seguros para ls
# shellcheck disable=SC2314  # `! grep` é idiomático para asserção negativa aqui

setup() {
    load '../helpers/common'
}

# ── run0 alias ───────────────────────────────────────────────────────────────

@test "run0 binary exists" {
    [ -x /usr/bin/run0 ]
}

@test "sudo alias points to run0" {
    grep -q "alias sudo='run0'" /etc/profile.d/run0-alias.sh
}

# ── SELinux ──────────────────────────────────────────────────────────────────

@test "SELinux is enforcing" {
    grep -qx 'SELINUX=enforcing' /etc/selinux/config
}

# ── Crypto policy ────────────────────────────────────────────────────────────

@test "crypto policy is DEFAULT or DEFAULT:*" {
    grep -qE '^DEFAULT' /etc/crypto-policies/config
}

# ── sysctl ───────────────────────────────────────────────────────────────────

@test "kernel.sysrq is 0" {
    grep -qE '^kernel\.sysrq\s*=\s*0' /etc/sysctl.d/60-security-hardening.conf
}

@test "ICMP echo is ignored" {
    grep -qE '^net\.ipv4\.icmp_echo_ignore_all\s*=\s*1' /etc/sysctl.d/60-security-hardening.conf
}

@test "vm.swappiness is 180 for aggressive ZRAM use" {
    grep -q 'vm.swappiness = 180' /etc/sysctl.d/99-performance.conf
}

@test "vm.max_map_count is configured" {
    grep -q 'vm.max_map_count' /etc/sysctl.d/99-performance.conf
}

@test "Cachy Sauce performance tunables are present" {
    grep -qE '^kernel\.sched_autogroup_enabled\s*=\s*1' /etc/sysctl.d/99-performance.conf
    grep -qE '^net\.core\.netdev_max_backlog\s*=' /etc/sysctl.d/99-performance.conf
}

@test "split_lock_mitigate is disabled for performance" {
    grep -qE '^kernel\.split_lock_mitigate\s*=\s*0' /etc/sysctl.d/99-performance.conf
}

@test "nmi_watchdog is disabled for performance" {
    grep -qE '^kernel\.nmi_watchdog\s*=\s*0' /etc/sysctl.d/99-performance.conf
}

# ── ZRAM ─────────────────────────────────────────────────────────────────────

@test "ZRAM uses zstd compression" {
    grep -q 'compression-algorithm=zstd' /etc/systemd/zram-generator.conf
}

@test "ZRAM size is limited" {
    grep -q 'zram-size = min(ram / 4, 4096)' /etc/systemd/zram-generator.conf
}

# ── login.defs hardening ────────────────────────────────────────────────────

@test "UMASK is 027 in login.defs" {
    grep -qE '^UMASK[[:space:]]+027' /etc/login.defs
}

@test "YESCRYPT_COST_FACTOR is 8" {
    grep -qE '^YESCRYPT_COST_FACTOR[[:space:]]+8' /etc/login.defs
}

# ── Authselect faillock ─────────────────────────────────────────────────────

@test "faillock is active in PAM" {
    authselect current 2>/dev/null | grep -q 'with-faillock' \
        || grep -rqs 'pam_faillock\.so' /etc/pam.d
}

# ── SUID removal ────────────────────────────────────────────────────────────

@test "chsh has been removed (SUID)" {
    [ ! -f /usr/bin/chsh ]
}

@test "chfn has been removed (SUID)" {
    [ ! -f /usr/bin/chfn ]
}

@test "pkexec is preserved for polkit and live installer flows" {
    [ -x /usr/bin/pkexec ]
    [ -u /usr/bin/pkexec ]
}

@test "sudo retains SUID bit" {
    [ -u /usr/bin/sudo ]
}

@test "hardened_malloc preload libraries retain SUID bit" {
    mapfile -d '' libs < <(find /usr/lib /usr/lib64 -type f -name 'libhardened_malloc*.so' -print0 2>/dev/null || true)
    [ "${#libs[@]}" -gt 0 ]
    for lib in "${libs[@]}"; do
        [ -u "$lib" ]
    done
}

# ── Container signing ───────────────────────────────────────────────────────

@test "container signing policy for fedora-ostree-desktops exists" {
    [ -f /etc/containers/registries.d/quay.io-fedora-ostree-desktops.yaml ]
}

@test "container signing policy for toolbx-images exists" {
    [ -f /etc/containers/registries.d/quay.io-toolbx-images.yaml ]
}

# ── SELinux CIL policies ────────────────────────────────────────────────────

@test "SELinux secureblue CIL payload is shipped" {
    [ -f /usr/share/selinux/image-fedora/secureblue_socket_utils.cil ]
    [ -f /usr/share/selinux/image-fedora/secureblue_deny_ipsec_sockets.cil ]
}

@test "SELinux userns deny modules are not loaded" {
    ! find /usr/share/selinux/image-fedora -type f -name '*harden_userns*.cil' | grep -q .
    ! find /usr/share/selinux/image-fedora -type f -name '*harden_container_userns*.cil' | grep -q .
}

@test "SELinux boot-time setup installs CIL and booleans" {
    [ -x /usr/libexec/image-fedora-selinux-setup ]
    grep -q 'semodule -X 300 -i' /usr/libexec/image-fedora-selinux-setup
    grep -q 'setsebool deny_ptrace=on' /usr/libexec/image-fedora-selinux-setup
    grep -q 'setsebool container_allow_ptrace=off' /usr/libexec/image-fedora-selinux-setup
}

# ── modprobe DVB/RC ──────────────────────────────────────────────────────────

@test "modprobe blacklist for DVB/RC exists" {
    [ -f /etc/modprobe.d/no-dvb-rc.conf ]
}

@test "dvb-core is blacklisted" {
    grep -q 'dvb-core' /etc/modprobe.d/no-dvb-rc.conf
}

# ── GRUB ─────────────────────────────────────────────────────────────────────

@test "GRUB timeout is 0" {
    grep -q 'set timeout=0' /usr/lib/bootupd/grub2-static/configs.d/05_timeout.cfg
}

@test "GRUB timeout_style is hidden" {
    grep -q 'timeout_style=hidden' /usr/lib/bootupd/grub2-static/configs.d/05_timeout.cfg
}

# ── kargs ────────────────────────────────────────────────────────────────────

@test "kargs include quiet" {
    grep -q '"quiet"' /usr/lib/bootc/kargs.d/10-hardening.toml
}

@test "kargs include rhgb" {
    grep -q '"rhgb"' /usr/lib/bootc/kargs.d/10-hardening.toml
}

@test "kargs include splash" {
    grep -q '"splash"' /usr/lib/bootc/kargs.d/10-hardening.toml
}

# ── Performance (cachyos-settings-derived) ───────────────────────────────────

@test "perf kargs disable zswap (zram is the swap backend)" {
    grep -q 'zswap.enabled=0' /usr/lib/bootc/kargs.d/20-performance.toml
}

@test "perf kargs select full preemption model" {
    grep -q 'preempt=full' /usr/lib/bootc/kargs.d/20-performance.toml
}

@test "THP tuning tmpfiles configures defrag and shrinker" {
    grep -q 'transparent_hugepage/defrag' /usr/lib/tmpfiles.d/thp-tuning.conf
    grep -q 'max_ptes_none' /usr/lib/tmpfiles.d/thp-tuning.conf
}

@test "user@ sessions delegate cgroup controllers" {
    grep -qE '^Delegate=.*\bmemory\b' /etc/systemd/system/user@.service.d/10-delegate.conf
}

@test "user@ sessions enable KSM memory merging" {
    grep -qE '^MemoryKSM=yes' /etc/systemd/system/user@.service.d/10-ksm.conf
}

@test "KSM global scanner is enabled via tmpfiles" {
    grep -q '/sys/kernel/mm/ksm/run' /usr/lib/tmpfiles.d/ksm-enable.conf
}

@test "audio group has realtime scheduling priority" {
    grep -qE '^@audio\s+-\s+rtprio\s+99' /etc/security/limits.d/61-audio-rtprio.conf
}

@test "systemd raises DefaultLimitNOFILE" {
    grep -qE '^DefaultLimitNOFILE=' /etc/systemd/system.conf.d/10-nofile-limit.conf
}

# ── Required files ───────────────────────────────────────────────────────────

@test "/etc/sysctl.d/60-security-hardening.conf exists" {
    [ -e /etc/sysctl.d/60-security-hardening.conf ]
}

@test "/etc/sysctl.d/99-performance.conf exists" {
    [ -e /etc/sysctl.d/99-performance.conf ]
}

@test "/usr/lib/bootc/kargs.d/10-hardening.toml exists" {
    [ -e /usr/lib/bootc/kargs.d/10-hardening.toml ]
}

@test "/etc/dracut.conf.d/01-ostree-required.conf exists" {
    [ -e /etc/dracut.conf.d/01-ostree-required.conf ]
}

@test "/etc/dracut.conf.d/02-drm-drivers.conf exists" {
    [ -e /etc/dracut.conf.d/02-drm-drivers.conf ]
}

@test "/etc/dracut.conf.d/99-omit-firewire.conf exists" {
    [ -e /etc/dracut.conf.d/99-omit-firewire.conf ]
}


@test "/etc/dracut.conf.d/90-luks-security.conf exists" {
    [ -e /etc/dracut.conf.d/90-luks-security.conf ]
}

@test "/usr/libexec/fedora-flatpak-setup exists" {
    [ -e /usr/libexec/fedora-flatpak-setup ]
}

@test "/usr/libexec/fedora-shell-setup exists" {
    [ -e /usr/libexec/fedora-shell-setup ]
}

@test "/usr/libexec/fedora-dev-setup exists" {
    [ -e /usr/libexec/fedora-dev-setup ]
}

@test "/usr/libexec/fedora-brew-setup exists" {
    [ -e /usr/libexec/fedora-brew-setup ]
}

@test "/etc/selinux/config exists" {
    [ -e /etc/selinux/config ]
}

@test "/etc/chrony.conf exists" {
    [ -e /etc/chrony.conf ]
}

@test "/etc/rpm-ostreed.conf exists" {
    [ -e /etc/rpm-ostreed.conf ]
}

@test "/etc/systemd/zram-generator.conf exists" {
    [ -e /etc/systemd/zram-generator.conf ]
}

@test "/etc/systemd/system.conf.d/timeout.conf exists" {
    [ -e /etc/systemd/system.conf.d/timeout.conf ]
}

@test "/etc/systemd/user.conf.d/timeout.conf exists" {
    [ -e /etc/systemd/user.conf.d/timeout.conf ]
}

@test "/etc/security/limits.d/50-memlock.conf exists" {
    [ -e /etc/security/limits.d/50-memlock.conf ]
}

@test "libvirt user qemu config disables core dumps in skel" {
    grep -qx 'max_core = 0' /etc/skel/.config/libvirt/qemu.conf
}

@test "/etc/dnf/conf.d/no-weak-deps.conf exists" {
    [ -e /etc/dnf/conf.d/no-weak-deps.conf ]
}

@test "flatpak-nuke-fedora.service exists" {
    [ -e /usr/lib/systemd/system/flatpak-nuke-fedora.service ]
}

@test "flathub-system-setup.service exists" {
    [ -e /usr/lib/systemd/system/flathub-system-setup.service ]
}

@test "flathub.flatpakrepo exists" {
    [ -e /usr/share/flatpak/flathub.flatpakrepo ]
}

@test "/etc/keyd/default.conf exists" {
    [ -e /etc/keyd/default.conf ]
}

@test "oomd.conf.d/10-oomd.conf exists" {
    [ -e /etc/systemd/oomd.conf.d/10-oomd.conf ]
}

@test "/etc/locale.conf exists" {
    [ -e /etc/locale.conf ]
}

@test "/usr/bin/run0 exists" {
    [ -e /usr/bin/run0 ]
}

@test "/etc/profile.d/run0-alias.sh exists" {
    [ -e /etc/profile.d/run0-alias.sh ]
}

@test "io-schedulers udev rules exist" {
    [ -e /usr/lib/udev/rules.d/60-io-schedulers.rules ]
}

@test "gpu-reset udev rules exist" {
    [ -e /usr/lib/udev/rules.d/80-gpu-reset.rules ]
}

@test "wine-ntsync module config exists" {
    [ -e /usr/lib/modules-load.d/wine-ntsync.conf ]
}

@test "copr.vendor.conf exists" {
    [ -e /usr/share/dnf/plugins/copr.vendor.conf ]
}

@test "JetBrainsMono Nerd Font exists" {
    [ -e /usr/share/fonts/JetBrainsMonoNerdFont ]
}

@test "image-info.json exists" {
    [ -e /usr/share/image-info.json ]
}

@test "wireplumber disable-suspension config exists" {
    [ -e /usr/share/wireplumber/wireplumber.conf.d/51-disable-suspension.conf ]
}

@test "/usr/bin/dnf exists" {
    [ -e /usr/bin/dnf ]
}

@test "GRUB timeout config exists" {
    [ -e /usr/lib/bootupd/grub2-static/configs.d/05_timeout.cfg ]
}

# ── Initramfs ────────────────────────────────────────────────────────────────

@test "initramfs exists and is not empty" {
    KVER=$(ls /usr/lib/modules 2>/dev/null | sort -V | tail -1)
    [ -n "$KVER" ]
    INITRAMFS="/usr/lib/modules/$KVER/initramfs.img"
    [ -s "$INITRAMFS" ]
}
