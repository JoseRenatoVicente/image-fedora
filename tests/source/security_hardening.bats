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

@test "kernel kargs include lockdown=integrity" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/bootc/kargs.d/10-hardening.toml" 'lockdown=integrity'
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

@test "systemd preset uses only preset directives" {
    assert_not_contains "$preset" 'mask ctrl-alt-del.target'
    assert_contains "$configure_dir/50-services.sh" 'ctrl-alt-del.target'
}

@test "configure force-masks ctrl-alt-del target" {
    assert_contains "$configure_dir/50-services.sh" 'systemctl mask --force ctrl-alt-del.target'
}

# ── LUKS dracut ───────────────────────────────────────────────────────────────

@test "LUKS dracut config has add_dracutmodules" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/dracut.conf.d/90-luks-security.conf" 'add_dracutmodules'
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
