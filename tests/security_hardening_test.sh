#!/usr/bin/env bash
set -euo pipefail

repo_root=$(dirname "$(dirname "$0")")

assert_contains() {
    local file=$1
    local pattern=$2

    if ! grep -Fq "$pattern" "$file"; then
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

echo "ok: security hardening requirements are present"
