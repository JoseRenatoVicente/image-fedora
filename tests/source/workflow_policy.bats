#!/usr/bin/env bats
# Source-level tests: workflow security and reproducibility policy
# shellcheck disable=SC2016  # asserts comparam strings literais com ${...}

setup() {
    load '../helpers/common'
    build_workflow="${REPO_ROOT}/.github/workflows/build.yml"
    containerfile="${REPO_ROOT}/Containerfile"
    tests_workflow="${REPO_ROOT}/.github/workflows/tests.yml"
    integration_workflow="${REPO_ROOT}/.github/workflows/integration_tests.yml"
    codeql_workflow="${REPO_ROOT}/.github/workflows/codeql.yml"
    gitleaks_workflow="${REPO_ROOT}/.github/workflows/gitleaks.yml"
    disk_workflow="${REPO_ROOT}/.github/workflows/build-disk.yml"
}

# ── Harden Runner ────────────────────────────────────────────────────────────

@test "build.yml uses harden-runner" {
    assert_contains "$build_workflow" 'step-security/harden-runner@'
}

@test "codeql.yml uses harden-runner" {
    assert_contains "$codeql_workflow" 'step-security/harden-runner@'
}

@test "gitleaks.yml uses harden-runner" {
    assert_contains "$gitleaks_workflow" 'step-security/harden-runner@'
}

# ── Credentials ──────────────────────────────────────────────────────────────

@test "build.yml disables persist-credentials" {
    assert_contains "$build_workflow" 'persist-credentials: false'
}

# ── Cosign supply-chain ──────────────────────────────────────────────────────

@test "build.yml has cosign verify" {
    assert_contains "$build_workflow" 'cosign verify'
}

@test "build.yml has cosign verify-attestation" {
    assert_contains "$build_workflow" 'cosign verify-attestation'
}

@test "build.yml has cosign download sbom" {
    assert_contains "$build_workflow" 'cosign download sbom'
}

@test "build.yml generates SBOM from local image archive" {
    assert_contains "$build_workflow" 'syft /tmp/image-scan.tar --from docker-archive -o spdx-json=sbom.spdx.json'
}

@test "build.yml keeps scan archive until SBOM generation finishes" {
    run bash -c "awk '/Clean up scan artifacts/{clean=NR} /Generate SBOM with Syft/{sbom=NR} END{exit !(clean > sbom)}' '$build_workflow'"
    [ "$status" -eq 0 ]
}

@test "build.yml restricts cosign verification identity" {
    assert_contains "$build_workflow" '--certificate-identity-regexp "^https://github.com/${{ github.repository }}/.github/workflows/build.yml@refs/heads/"'
    assert_not_contains "$build_workflow" "--certificate-identity-regexp 'https://github.com/.+'"
}

@test "integration_tests.yml has cosign verify" {
    assert_contains "$integration_workflow" 'cosign verify'
}

@test "integration_tests.yml has cosign verify-attestation" {
    assert_contains "$integration_workflow" 'cosign verify-attestation'
}

# ── Trivy / SARIF ────────────────────────────────────────────────────────────

@test "build.yml uses hashFiles for trivy-results.sarif" {
    assert_contains "$build_workflow" "hashFiles('trivy-results.sarif')"
}

@test "build.yml uses lowercase image registry for build cache without tag" {
    assert_contains "$build_workflow" '--cache-from=${{ env.IMAGE_REGISTRY }}/${{ env.IMAGE_NAME }}'
    assert_not_contains "$build_workflow" '--cache-from=ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}'
    assert_not_contains "$build_workflow" '--cache-from=${{ env.IMAGE_REGISTRY }}/${{ env.IMAGE_NAME }}:latest'
}

# ── Static analysis ─────────────────────────────────────────────────────────

@test "tests.yml runs shellcheck" {
    assert_contains "$tests_workflow" 'shellcheck'
}

@test "tests.yml lints operational tools scripts" {
    assert_contains "$tests_workflow" 'find build_files tests tools'
}

@test "tests.yml installs just" {
    assert_contains "$tests_workflow" 'extractions/setup-just'
}

# ── Gitleaks ─────────────────────────────────────────────────────────────────

@test "gitleaks.yml uses gitleaks-action" {
    assert_contains "$gitleaks_workflow" 'gitleaks/gitleaks-action@'
}

# ── Base image extraction and filtering ──────────────────────────────────────

@test "build.yml extracts BASE_IMAGE with awk" {
    assert_contains "$build_workflow" 'BASE_IMAGE=$(awk'
}

@test "build.yml filters scratch image" {
    assert_contains "$build_workflow" 'image != "scratch"'
}

# ── Reproducibility (SOURCE_DATE_EPOCH) ──────────────────────────────────────

@test "Containerfile declares SOURCE_DATE_EPOCH ARG" {
    assert_contains "$containerfile" 'ARG SOURCE_DATE_EPOCH'
}

@test "Containerfile uses SOURCE_DATE_EPOCH" {
    assert_contains "$containerfile" 'SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}"'
}

@test "build.yml passes SOURCE_DATE_EPOCH as build arg" {
    assert_contains "$build_workflow" 'SOURCE_DATE_EPOCH=${{ env.SOURCE_DATE_EPOCH }}'
    assert_not_contains "$build_workflow" '--source-date-epoch=${{ env.SOURCE_DATE_EPOCH }}'
}

# ── Disk image build ────────────────────────────────────────────────────────

@test "build-disk.yml references disk.toml" {
    assert_contains "$disk_workflow" 'disk_config/disk.toml'
}

@test "build-disk.yml references iso.toml" {
    assert_contains "$disk_workflow" 'disk_config/iso.toml'
}

@test "BIB is pinned by digest" {
    assert_contains "$disk_workflow" 'bootc-image-builder@sha256:'
}

@test "build-disk.yml defaults pull requests to amd64 runner" {
    assert_contains "$disk_workflow" "(inputs.platform || 'amd64') == 'amd64'"
}
