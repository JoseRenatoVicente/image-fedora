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

    if ! grep -Fq "$pattern" "$file"; then
        fail "expected '$pattern' in $file"
    fi
}

build_workflow="${repo_root}/.github/workflows/build.yml"
tests_workflow="${repo_root}/.github/workflows/tests.yml"
integration_workflow="${repo_root}/.github/workflows/integration_tests.yml"
codeql_workflow="${repo_root}/.github/workflows/codeql.yml"
gitleaks_workflow="${repo_root}/.github/workflows/gitleaks.yml"

assert_contains "$build_workflow" 'step-security/harden-runner@'
assert_contains "$build_workflow" 'persist-credentials: false'
assert_contains "$build_workflow" 'cosign verify'
assert_contains "$build_workflow" 'cosign verify-attestation'
assert_contains "$build_workflow" 'cosign download sbom'
assert_contains "$tests_workflow" 'shellcheck'
assert_contains "$integration_workflow" 'cosign verify'
assert_contains "$integration_workflow" 'cosign verify-attestation'
assert_contains "$codeql_workflow" 'step-security/harden-runner@'
assert_contains "$gitleaks_workflow" 'step-security/harden-runner@'
assert_contains "$gitleaks_workflow" 'gitleaks/gitleaks-action@'

if [[ $failed -ne 0 ]]; then
    exit 1
fi

echo "ok: workflow policy checks passed"
