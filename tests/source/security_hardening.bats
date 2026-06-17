#!/usr/bin/env bats
# Source-level tests: security hardening requirements

setup() {
    load '../helpers/common'
    packages="${REPO_ROOT}/build_files/build-packages.sh"
    configure="${REPO_ROOT}/build_files/build-configure.sh"
    configure_cleanup="${REPO_ROOT}/build_files/build-configure.sh"
    security_just="${REPO_ROOT}/just/security.just"
}

# ── Kernel hardening args ─────────────────────────────────────────────────────

@test "kernel kargs include lockdown=integrity" {
    assert_contains "${REPO_ROOT}/build_files/usr/lib/bootc/kargs.d/10-hardening.toml" 'lockdown=integrity'
}

@test "kernel kargs include pti=on" {
    assert_contains "${REPO_ROOT}/build_files/usr/lib/bootc/kargs.d/10-hardening.toml" 'pti=on'
}

@test "kernel kargs include module.sig_enforce=1" {
    assert_contains "${REPO_ROOT}/build_files/usr/lib/bootc/kargs.d/10-hardening.toml" 'module.sig_enforce=1'
}

# ── Crypto policy ────────────────────────────────────────────────────────────

@test "crypto policy set to FUTURE:CHRONY-NTS" {
    assert_contains "$configure_cleanup" 'update-crypto-policies --set FUTURE:CHRONY-NTS'
}

# ── SELinux ───────────────────────────────────────────────────────────────────

@test "SELinux is set to enforcing" {
    assert_contains "${REPO_ROOT}/build_files/etc/selinux/config" 'SELINUX=enforcing'
}

# ── LUKS dracut ───────────────────────────────────────────────────────────────

@test "LUKS dracut config has add_dracutmodules" {
    assert_contains "${REPO_ROOT}/build_files/etc/dracut.conf.d/90-luks-security.conf" 'add_dracutmodules'
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
    run grep -Fq 'packages.microsoft.com' "$packages" "$configure"
    [ "$status" -ne 0 ]
}

@test "VS Code RPM is not installed in base" {
    run grep -Eq '(^|[[:space:]])code($|[[:space:]])' "$packages" "$configure"
    [ "$status" -ne 0 ]
}

# ── Bluetooth not enabled by default ─────────────────────────────────────────

@test "Bluetooth is not enabled by default" {
    run grep -Eq 'systemctl[[:space:]]+enable.*bluetooth(\.service|\.target)?' "$configure"
    [ "$status" -ne 0 ]
}
