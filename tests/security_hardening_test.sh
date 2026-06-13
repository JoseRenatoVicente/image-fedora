#!/usr/bin/env bash
set -euo pipefail

repo_root=$(dirname "$(dirname "$0")")

assert_contains() {
    local file=$1
    local pattern=$2

    if ! grep -Fq -- "$pattern" "$file"; then
        echo "failed: expected '$pattern' in $file"
        exit 1
    fi
}

# Kernel hardening args
assert_contains "${repo_root}/build_files/configs/bootc-kargs.toml" 'lockdown=integrity'
assert_contains "${repo_root}/build_files/configs/bootc-kargs.toml" 'pti=on'
assert_contains "${repo_root}/build_files/configs/bootc-kargs.toml" 'module.sig_enforce=1'

# Crypto policy
assert_contains "${repo_root}/build_files/build.sh" 'update-crypto-policies --set FUTURE'

# SELinux enforcing
assert_contains "${repo_root}/build_files/configs/selinux-enforcing.conf" 'SELINUX=enforcing'

# LUKS dracut config
assert_contains "${repo_root}/build_files/configs/dracut-luks.conf" 'add_dracutmodules'

# Image signing
assert_contains "${repo_root}/Justfile" 'cosign sign'
assert_contains "${repo_root}/Justfile" 'cosign verify'
assert_contains "${repo_root}/Justfile" 'verify-remote-image'
assert_contains "${repo_root}/Justfile" 'verify-attestation'

# Workflow verification gates
assert_contains "${repo_root}/.github/workflows/build.yml" 'cosign verify'
assert_contains "${repo_root}/.github/workflows/build.yml" 'cosign verify-attestation'
assert_contains "${repo_root}/.github/workflows/integration_tests.yml" 'cosign verify'

# Atomic base contract: VS Code must not be installed as an RPM in the base image.
if grep -Fq 'packages.microsoft.com' "${repo_root}/build_files/build.sh"; then
    echo "failed: Microsoft VS Code repo must not be configured in the base image" >&2
    exit 1
fi
if grep -Eq '(^|[[:space:]])code($|[[:space:]])' "${repo_root}/build_files/build.sh"; then
    echo "failed: VS Code RPM must not be installed in the base image" >&2
    exit 1
fi

# Secure profile: Bluetooth is opt-in, not enabled by default.
if grep -Eq 'systemctl[[:space:]]+enable.*bluetooth(\.service|\.target)?' "${repo_root}/build_files/build.sh"; then
    echo "failed: Bluetooth must not be enabled by default" >&2
    exit 1
fi

echo "ok: security hardening requirements are present"
