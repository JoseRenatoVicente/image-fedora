#!/usr/bin/env bash
set -euo pipefail

repo_root=$(dirname "$(dirname "$0")")
failed=0

fail() {
    echo "FAIL: $*" >&2
    failed=1
}

assert_contains() {
    local file=$1
    local pattern=$2

    if ! grep -Fq -- "$pattern" "$file"; then
        fail "expected '$pattern' in $file"
    fi
}

build_workflow="${repo_root}/.github/workflows/build.yml"
containerfile="${repo_root}/Containerfile"
tests_workflow="${repo_root}/.github/workflows/tests.yml"
integration_workflow="${repo_root}/.github/workflows/integration_tests.yml"
codeql_workflow="${repo_root}/.github/workflows/codeql.yml"
gitleaks_workflow="${repo_root}/.github/workflows/gitleaks.yml"
disk_workflow="${repo_root}/.github/workflows/build-disk.yml"

assert_contains "$build_workflow" 'step-security/harden-runner@'
assert_contains "$build_workflow" 'persist-credentials: false'
assert_contains "$build_workflow" 'cosign verify'
assert_contains "$build_workflow" 'cosign verify-attestation'
assert_contains "$build_workflow" 'cosign download sbom'
assert_contains "$build_workflow" "hashFiles('trivy-results.sarif')"
assert_contains "$tests_workflow" 'shellcheck'
assert_contains "$tests_workflow" 'apt-get install -y just'
assert_contains "$integration_workflow" 'cosign verify'
assert_contains "$integration_workflow" 'cosign verify-attestation'
assert_contains "$codeql_workflow" 'step-security/harden-runner@'
assert_contains "$gitleaks_workflow" 'step-security/harden-runner@'
assert_contains "$gitleaks_workflow" 'gitleaks/gitleaks-action@'
assert_contains "$build_workflow" 'BASE_IMAGE=$(awk'
assert_contains "$build_workflow" 'image != "scratch"'
assert_contains "$containerfile" 'ARG SOURCE_DATE_EPOCH'
assert_contains "$containerfile" 'SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}"'
assert_contains "$build_workflow" '--source-date-epoch=${{ env.SOURCE_DATE_EPOCH }}'
assert_contains "$disk_workflow" 'disk_config/disk.toml'
assert_contains "$disk_workflow" 'disk_config/iso.toml'
assert_contains "$disk_workflow" 'bootc-image-builder@sha256:'

if [[ $failed -ne 0 ]]; then
    exit 1
fi

echo "ok: workflow policy checks passed"
