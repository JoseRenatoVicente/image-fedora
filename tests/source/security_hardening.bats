#!/usr/bin/env bats
# Source-level tests: security hardening requirements

setup() {
    load '../helpers/common'
    packages="${REPO_ROOT}/build_files/scripts/shared/package-lists.sh"
    configure_dir="${REPO_ROOT}/build_files/scripts/configure"
    security_just="${REPO_ROOT}/just/security.just"
    preset="${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system-preset/35-security-desktop.preset"
}

# ── Kernel hardening args ─────────────────────────────────────────────────────

@test "kernel kargs include lockdown=confidentiality" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml" 'lockdown=confidentiality'
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

@test "systemd DefaultEnvironment preloads hardened_malloc for all services" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system.conf.d/40-hardened_malloc.conf" 'LD_PRELOAD=libhardened_malloc.so'
}

@test "sshd is masked in configure script" {
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/50-services.sh" 'sshd.service'
    assert_contains "${REPO_ROOT}/build_files/scripts/configure/50-services.sh" 'sshd.socket'
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
    assert_success
}

@test "tpm2-first-enroll service runs before greetd" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/tpm2-first-enroll.service" 'Before=greetd.service'
}

@test "tpm2-first-enroll service uses one-time condition marker" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/tpm2-first-enroll.service" 'ConditionPathExists=!/var/lib/tpm2-enrolled'
}

@test "DRM dracut config stays active by default" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/dracut.conf.d/02-drm-drivers.conf" 'virtio_gpu'
}

@test "initramfs generation uses host-only hardware defaults" {
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/80-initramfs.sh" '--no-hostonly'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/80-initramfs.sh" '--force-drivers'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/shared/initramfs.sh" '--no-hostonly'
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
