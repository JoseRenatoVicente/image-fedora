#!/usr/bin/env bats
# Source-level tests: security hardening requirements

setup() {
    load '../helpers/common'
    packages="${REPO_ROOT}/build_files/scripts/shared/package-lists.sh"
    configure_dir="${REPO_ROOT}/build_files/scripts/configure"
    runtime_tests="${REPO_ROOT}/build_files/scripts/shared/tests.sh"
    container_hardening="${REPO_ROOT}/tests/container/hardening.bats"
    security_just="${REPO_ROOT}/just/security.just"
    preset="${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system-preset/35-security-desktop.preset"
}

# ── Kernel hardening args ─────────────────────────────────────────────────────

@test "kernel kargs include lockdown=integrity" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml" 'lockdown=integrity'
}

@test "kernel kargs include KVM hardware isolation mitigations" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml" 'kvm_amd.sev=1'
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml" 'kvm-intel.vmentry_l1d_flush=always'
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml" 'kvm.mitigate_smt_rsb=1'
}

@test "kernel kargs include pti=on" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml" 'pti=on'
}

@test "kernel kargs include module.sig_enforce=1" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml" 'module.sig_enforce=1'
}

# ── Crypto policy ────────────────────────────────────────────────────────────

@test "crypto policy set to DEFAULT:CHRONY-NTS" {
    assert_tree_contains "$configure_dir" 'update-crypto-policies --set DEFAULT:CHRONY-NTS'
}

# ── SELinux ───────────────────────────────────────────────────────────────────

@test "SELinux is set to enforcing" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/selinux/config" 'SELINUX=enforcing'
}

@test "SELinux policy grants Flatpak bwrap user namespaces for unconfined users" {
    assert_contains "${REPO_ROOT}/build_files/assets/selinux/grant_userns.cil" '(allow unconfined_t self (user_namespace (create)))'
}

@test "SELinux userns deny policies stay disabled for Flatpak browsers" {
    assert_contains "$configure_dir/60-selinux-suid.sh" 'REMOVIDOS: harden_userns.cil + harden_container_userns.cil'
    assert_not_contains "$configure_dir/60-selinux-suid.sh" '/ctx/assets/selinux/harden_userns.cil'
    assert_not_contains "$configure_dir/60-selinux-suid.sh" '/ctx/assets/selinux/harden_container_userns.cil'
}

@test "SELinux booleans are applied at boot when build-time persistence fails" {
    local unit="${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/selinux-booleans.service"
    local helper="${REPO_ROOT}/build_files/overlay/usr/libexec/image-fedora-selinux-setup"
    assert_file_exists "$unit"
    assert_file_exists "$helper"
    assert_contains "$unit" 'ConditionSecurity=selinux'
    assert_contains "$unit" 'ExecStart=/usr/libexec/image-fedora-selinux-setup'
    assert_contains "$helper" 'semodule -X 300 -i'
    assert_contains "$helper" 'setsebool deny_ptrace=on'
    assert_contains "$helper" 'setsebool container_allow_ptrace=off'
    assert_contains "$configure_dir/50-services.sh" 'selinux-booleans.service'
}

@test "SELinux CIL payload is shipped for boot-time install" {
    assert_contains "$configure_dir/60-selinux-suid.sh" '/usr/share/selinux/image-fedora'
    assert_contains "$runtime_tests" '/usr/share/selinux/image-fedora/secureblue_socket_utils.cil'
    assert_contains "$runtime_tests" '/usr/share/selinux/image-fedora/container-ptrace.cil'
    assert_not_contains "$runtime_tests" "grep -q 'secureblue_deny_ipsec_sockets'"
    assert_not_contains "$runtime_tests" "grep -q 'container-ptrace'"

    assert_contains "$container_hardening" '/usr/share/selinux/image-fedora/secureblue_socket_utils.cil'
    assert_contains "$container_hardening" '/usr/share/selinux/image-fedora/container-ptrace.cil'
}

@test "Tor Browser is installed through Flatpak" {
    assert_contains "${REPO_ROOT}/installer/flatpaks" 'app/org.torproject.torbrowser-launcher/x86_64/stable'
}

@test "systemd preset uses only preset directives" {
    assert_not_contains "$preset" 'mask ctrl-alt-del.target'
    assert_contains "$configure_dir/50-services.sh" 'ctrl-alt-del.target'
}

@test "configure force-masks ctrl-alt-del target" {
    assert_contains "$configure_dir/50-services.sh" 'systemctl mask --force ctrl-alt-del.target'
}

# ── Boot speed/security policy ────────────────────────────────────────────────

@test "LUKS dracut security config stays active by default" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/dracut.conf.d/90-luks-security.conf" 'add_dracutmodules'
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/dracut.conf.d/90-luks-security.conf" 'tpm2-tss'
}

@test "hardened_malloc is installed via COPR" {
    assert_contains "${REPO_ROOT}/build_files/scripts/build-packages.sh" 'hardened_malloc'
}

@test "ld.so.preload is present in overlay and references hardened_malloc" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/ld.so.preload" 'libhardened_malloc.so'
}

@test "ld.so.preload is chmod 600 in configure script" {
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/10-system.sh" 'chmod 600 /etc/ld.so.preload'
}

@test "rpm-ostreed.conf has Recommends=false" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/rpm-ostreed.conf" 'Recommends=false'
}

@test "modprobe blacklist covers MCTP and batman-adv" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/modprobe.d/security-hardening.conf" 'mctp-serial'
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/modprobe.d/security-hardening.conf" 'batman-adv'
}

@test "modprobe blacklist covers NFS server stack" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/modprobe.d/security-hardening.conf" 'install nfsd'
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/modprobe.d/security-hardening.conf" 'install lockd'
}

@test "modprobe blacklist covers legacy USB cameras (gspca)" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/modprobe.d/no-dvb-rc.conf" 'gspca_main'
}

@test "vm.max_map_count is set for gaming and dev workloads" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/sysctl.d/60-security-hardening.conf" 'vm.max_map_count = 1048576'
}

@test "hardened_malloc is preloaded via ld.so.preload only, not duplicated via systemd DefaultEnvironment" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/ld.so.preload" 'libhardened_malloc.so'
    assert_file_not_exists "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system.conf.d/40-hardened_malloc.conf"
}

@test "public desktop config files are made world-readable during configure" {
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/10-system.sh" '/etc/locale.conf'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/10-system.sh" '/usr/share/qt6/qtlogging.ini'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/10-system.sh" '/usr/share/wireplumber/wireplumber.conf.d/51-disable-suspension.conf'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/10-system.sh" 'chmod 0644'
}

@test "sshd is disabled by default but host key generation is not masked" {
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/50-services.sh" 'sshd.service'
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system-preset/35-security-desktop.preset" 'disable sshd.service'
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system-preset/35-security-desktop.preset" 'enable sshd-keygen.target'
}

@test "NFS server daemons are masked in configure script" {
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/50-services.sh" 'rpcbind.service'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/50-services.sh" 'nfs-server.service'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/50-services.sh" 'gssproxy.service'
}

@test "iSCSI daemons are masked in configure script" {
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/50-services.sh" 'iscsid.service'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/50-services.sh" 'iscsiuio.service'
}

@test "tpm2-first-enroll script is present in overlay" {
    run test -f "${REPO_ROOT}/build_files/overlay/usr/bin/tpm2-first-enroll"
    [ "$status" -eq 0 ]
}

@test "TPM2 interactive services run before display managers" {
    local first="${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/tpm2-first-enroll.service"
    local reenroll="${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/tpm2-reenroll-check.service"

    assert_contains "$first" 'Before=display-manager.service plasmalogin.service sddm.service greetd.service'
    assert_contains "$reenroll" 'Before=display-manager.service plasmalogin.service sddm.service greetd.service'
}

@test "tpm2-first-enroll service uses one-time condition marker" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/tpm2-first-enroll.service" 'ConditionPathExists=!/var/lib/tpm2-enrolled'
}

@test "TPM2 enroll scripts use Signed PCR Policy (PCR 11), not local initramfs regen" {
    # UKI é construído e assinado só no build (chave privada nunca sai do CI)
    # — o cliente não pode regenerar/assinar um UKI localmente, por isso estes
    # scripts não devem tentar 'rpm-ostree initramfs --enable' nem selar em
    # PCR 7 (raw, instável nalguns firmwares).
    for script in tpm2-luks-enroll tpm2-first-enroll tpm2-reenroll-check; do
        assert_not_contains "${REPO_ROOT}/build_files/overlay/usr/bin/$script" 'rpm-ostree initramfs --enable'
        assert_not_contains "${REPO_ROOT}/build_files/overlay/usr/bin/$script" 'tpm2-pcrs=7'
    done
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/bin/tpm2-first-enroll" 'tpm2-device=auto'
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/bin/tpm2-first-enroll" 'tpm2-public-key-pcrs=11'
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/bin/tpm2-luks-enroll" 'tpm2-public-key-pcrs="$PCRS"'
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/bin/tpm2-reenroll-check" 'tpm2-public-key-pcrs=11'
}

@test "uki-migrate mirrors sd-boot-migrate's opt-in pattern" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/uki-migrate.service" 'ConditionPathExists=/etc/uki-migrate-requested'
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/uki-migrate.service" 'ConditionPathExists=!/var/lib/uki-migrated'
    run test -x "${REPO_ROOT}/build_files/overlay/usr/libexec/uki-migrate"
    [ "$status" -eq 0 ]
    run test -x "${REPO_ROOT}/build_files/overlay/usr/bin/uki-migrate-enable"
    [ "$status" -eq 0 ]
}

@test "uki-migrate refuses to run without a password/recovery LUKS keyslot" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/libexec/uki-migrate" "grep -qE 'password|recovery'"
}

@test "tpm2-reenroll-check keeps cryptenroll prompts visible" {
    local script="${REPO_ROOT}/build_files/overlay/usr/bin/tpm2-reenroll-check"

    assert_contains "$script" 'systemd-cryptenroll --wipe-slot=tpm2 "$TARGET_DEV"'
    assert_not_contains "$script" 'systemd-cryptenroll --wipe-slot=tpm2 "$TARGET_DEV" 2>/dev/null'
}

@test "tpm2-reenroll-check does not block boot on ENTER-only pauses" {
    local script="${REPO_ROOT}/build_files/overlay/usr/bin/tpm2-reenroll-check"

    assert_contains "$script" 'pause_for_user_visibility'
    assert_not_contains "$script" 'Prima ENTER'
}

@test "DRM dracut config stays active by default" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/dracut.conf.d/02-drm-drivers.conf" 'virtio_gpu'
}

@test "container-built initramfs is hardware-generic" {
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/80-initramfs.sh" '--no-hostonly'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/80-initramfs.sh" '--hostonly'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/80-initramfs.sh" '--force-drivers'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/shared/initramfs.sh" '--no-hostonly'
}

@test "ld.so.preload only references installed hardened_malloc library" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/ld.so.preload" 'libhardened_malloc.so'
    assert_not_contains "${REPO_ROOT}/build_files/overlay/etc/ld.so.preload" 'libno_rlimit_as.so'
}

@test "initramfs generation avoids tmpfs for dracut staging" {
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/80-initramfs.sh" 'DRACUT_TMPDIR="/var/tmp/dracut-build"'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/80-initramfs.sh" '--tmpdir "$DRACUT_TMPDIR"'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/80-initramfs.sh" '--tmpdir /tmp'
}

@test "runtime initramfs keeps common rootfs discovery modules" {
    run grep -Eq '^omit_dracutmodules\+=".*\blvm\b' "${REPO_ROOT}/build_files/overlay/etc/dracut.conf.d/10-boot-performance.conf"
    [ "$status" -ne 0 ]
    run grep -Eq '^omit_dracutmodules\+=".*\bmdraid\b' "${REPO_ROOT}/build_files/overlay/etc/dracut.conf.d/10-boot-performance.conf"
    [ "$status" -ne 0 ]
}

@test "dracut failures remain diagnosable after updates" {
    run grep -Eq '^[[:space:]]*"rd\.shell=0"' "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml"
    [ "$status" -ne 0 ]
    run grep -Eq '^[[:space:]]*"rd\.emergency=halt"' "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml"
    [ "$status" -ne 0 ]
}

@test "SUID hardening preserves pkexec for polkit and Anaconda liveinst" {
    assert_contains "$configure_dir/60-selinux-suid.sh" 'rm -f /usr/bin/chsh /usr/bin/chfn'
    assert_contains "$configure_dir/60-selinux-suid.sh" '/usr/bin/pkexec|\'
    assert_not_contains "$configure_dir/60-selinux-suid.sh" 'rm -f /usr/bin/chsh /usr/bin/chfn /usr/bin/pkexec'
}

@test "SUID hardening preserves hardened_malloc preload libraries" {
    assert_contains "$configure_dir/60-selinux-suid.sh" 'libhardened_malloc*.so'
    assert_contains "$configure_dir/60-selinux-suid.sh" 'glibc-hwcaps/*/libhardened_malloc*.so'
}

@test "fast default does not disable native GPU drivers" {
    ! grep -RFq -- 'nomodeset' "${REPO_ROOT}/build_files"
    ! grep -RFq -- 'modprobe.blacklist=nouveau' "${REPO_ROOT}/build_files"
    ! grep -RFq -- 'rd.driver.blacklist=nouveau' "${REPO_ROOT}/build_files"
}

@test "security kargs stay active by default" {
    local kargs="${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml"
    assert_contains "$kargs" 'init_on_free=1'
    assert_contains "$kargs" 'iommu.strict=1'
    assert_contains "$kargs" 'random.trust_bootloader=off'
    assert_contains "$kargs" 'random.trust_cpu=off'
    assert_contains "$kargs" 'slab_nomerge'
    # slab_debug=FZ e page_poison=1 removidos por overhead — mantêm-se init_on_free
    # e slab_nomerge como defesas contra corrupção de heap.
}

# ── Image signing (Justfile) ─────────────────────────────────────────────────

@test "Justfile has cosign sign" {
    assert_contains "$security_just" 'cosign sign'
}

@test "Justfile has cosign verify" {
    assert_contains "$security_just" 'cosign verify'
}

@test "Justfile has verify-remote-image" {
    assert_contains "$security_just" 'verify-remote-image'
}

@test "Justfile has verify-attestation" {
    assert_contains "$security_just" 'verify-attestation'
}

# ── Workflow verification gates ──────────────────────────────────────────────

@test "build.yml has cosign verify" {
    assert_contains "${REPO_ROOT}/.github/workflows/build.yml" 'cosign verify'
}

@test "build.yml has cosign verify-attestation" {
    assert_contains "${REPO_ROOT}/.github/workflows/build.yml" 'cosign verify-attestation'
}

@test "integration_tests.yml has cosign verify" {
    assert_contains "${REPO_ROOT}/.github/workflows/integration_tests.yml" 'cosign verify'
}

# ── VS Code must not be in base image ────────────────────────────────────────

@test "Microsoft VS Code repo is not configured" {
    run grep -RFq 'packages.microsoft.com' "$packages" "$configure_dir"
    [ "$status" -ne 0 ]
}

@test "VS Code RPM is not installed in base" {
    run bash -c "source '$packages'; [[ ! \" \\${INSTALL_PACKAGES[*]} \" =~ [[:space:]]code([[:space:]]|$) ]]"
    [ "$status" -eq 0 ]
}

# ── Bluetooth not enabled by default ─────────────────────────────────────────

@test "Bluetooth is not enabled by default" {
    run grep -REq 'systemctl[[:space:]]+enable.*bluetooth(\.service|\.target)?' "$configure_dir"
    [ "$status" -ne 0 ]
}
