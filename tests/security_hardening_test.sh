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

assert_contains "${repo_root}/build_files/configs/bootc-kargs.toml" '"fips=1"'
assert_contains "${repo_root}/build_files/build.sh" 'update-crypto-policies --set FUTURE'
assert_contains "${repo_root}/build_files/build.sh" 'dracut-fips'
assert_contains "${repo_root}/Justfile" 'cosign sign --key cosign.key'
assert_contains "${repo_root}/Justfile" 'cosign verify --key cosign.pub'
assert_contains "${repo_root}/build_files/configs/selinux-enforcing.conf" 'SELINUX=enforcing'

echo "ok: security hardening requirements are present"
