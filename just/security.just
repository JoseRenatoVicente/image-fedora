# ── Security Verification ─────────────────────────────────────────────────────

# Verify cosign signature of the published image
[group('Security')]
verify-signature $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v cosign &> /dev/null; then
        echo "cosign not found. Install: go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
        exit 1
    fi
    echo "Verifying signature for ${target_image}:${tag}..."
    cosign verify \
        --certificate-identity-regexp='{{ sign_identity }}' \
        --certificate-oidc-issuer="{{ sign_oidc_issuer }}" \
        "${target_image}:${tag}"
    echo "Signature verified successfully."

# Verify provenance attestation of the published image
[group('Security')]
verify-provenance $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v cosign &> /dev/null; then
        echo "cosign not found. Install: go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
        exit 1
    fi
    echo "Verifying provenance for ${target_image}:${tag}..."
    cosign verify-attestation \
        --certificate-identity-regexp='{{ provenance_identity }}' \
        --certificate-oidc-issuer='{{ sign_oidc_issuer }}' \
        --type slsaprovenance \
        "${target_image}:${tag}"
    echo "Provenance verified successfully."

# Verify the published SBOM attachment
[group('Security')]
verify-sbom $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v cosign &> /dev/null; then
        echo "cosign not found. Install: go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
        exit 1
    fi
    tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' EXIT
    echo "Downloading SBOM for ${target_image}:${tag}..."
    cosign download sbom "${target_image}:${tag}" > "$tmpfile"
    test -s "$tmpfile"
    grep -q '"spdxVersion"' "$tmpfile"
    echo "SBOM attachment verified successfully."

# Verify remote supply-chain artifacts together
[group('Security')]
audit-supply-chain $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    just verify-signature "{{ target_image }}" "{{ tag }}"
    just verify-provenance "{{ target_image }}" "{{ tag }}"
    just verify-sbom "{{ target_image }}" "{{ tag }}"

# Alias for downstream image verification
[group('Security')]
verify-remote-image $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    just audit-supply-chain "{{ target_image }}" "{{ tag }}"

# Scan image for vulnerabilities with Trivy
[group('Security')]
scan-vulnerabilities $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v trivy &> /dev/null; then
        echo "trivy not found. Install: sudo dnf install trivy"
        exit 1
    fi
    echo "Scanning ${target_image}:${tag} for vulnerabilities..."
    trivy image --severity CRITICAL,HIGH "localhost/${target_image}:${tag}"

# Generate SBOM for the image
[group('Security')]
generate-sbom $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v syft &> /dev/null; then
        echo "syft not found. Install: curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s"
        exit 1
    fi
    echo "Generating SBOM for ${target_image}:${tag}..."
    syft "localhost/${target_image}:${tag}" -o spdx-json > "sbom-${target_image}-${tag}.spdx.json"
    echo "SBOM saved to sbom-${target_image}-${tag}.spdx.json"

# List all installed RPM packages in the image
[group('Security')]
list-packages $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    local_ref="${target_image}:${tag}"
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        local_ref="localhost/${target_image}:${tag}"
    fi
    echo "Listing packages in ${local_ref}..."
    podman run --rm "${local_ref}" rpm -qa --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort

# Audit security configuration inside the image
[group('Security')]
audit-security $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    local_ref="${target_image}:${tag}"
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        local_ref="localhost/${target_image}:${tag}"
    fi
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        echo "Image not found in local storage: ${target_image}:${tag}"
        exit 1
    fi

    check() {
        local name=$1
        shift
        echo "── ${name} ──"
        "$@"
        echo "ok"
        echo ""
    }

    echo "=== Security Audit: ${local_ref} ==="
    echo ""

    check "SELinux enforcing config" \
        podman run --rm "${local_ref}" bash -lc "grep -qx 'SELINUX=enforcing' /etc/selinux/config"
    check "Crypto policy FUTURE" \
        podman run --rm "${local_ref}" bash -lc "grep -qE '^FUTURE' /etc/crypto-policies/config"
    check "Sysctl hardening" \
        podman run --rm "${local_ref}" bash -lc "test \$(grep -c '=' /etc/sysctl.d/60-security-hardening.conf 2>/dev/null) -gt 0"
    check "Kernel module blacklist" \
        podman run --rm "${local_ref}" bash -lc "test \$(grep -c 'install.*false' /etc/modprobe.d/security-hardening.conf 2>/dev/null) -gt 0"
    check "Boot parameters" \
        podman run --rm "${local_ref}" bash -lc "test \$(grep -c '=' /usr/lib/bootc/kargs.d/10-hardening.toml 2>/dev/null) -gt 0"
    check "Firewalld zone" \
        podman run --rm "${local_ref}" bash -lc "test -s /etc/firewalld/zones/FedoraWorkstation.xml"
    check "Core dumps disabled" \
        podman run --rm "${local_ref}" bash -lc "test -s /etc/security/limits.d/60-disable-coredump.conf"
    check "Password policy" \
        podman run --rm "${local_ref}" bash -lc "test -s /etc/security/pwquality.conf"
    check "Ptrace scope" \
        podman run --rm "${local_ref}" bash -lc "test -s /etc/sysctl.d/61-ptrace-scope.conf"
    check "Chrony NTS" \
        podman run --rm "${local_ref}" bash -lc "grep -q 'nts' /etc/chrony.conf"
    check "Systemd preset" \
        podman run --rm "${local_ref}" bash -lc "grep -q '^disable' /usr/lib/systemd/system-preset/35-security-desktop.preset"

    echo "=== Audit complete ==="

# Audit package surface inside the image
[group('Security')]
audit-package-surface $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    local_ref="${target_image}:${tag}"
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        local_ref="localhost/${target_image}:${tag}"
    fi
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        echo "Image not found in local storage: ${target_image}:${tag}"
        exit 1
    fi

    forbidden=(firefox mediawriter krfb kmail)
    for pkg in "${forbidden[@]}"; do
        if podman run --rm "${local_ref}" rpm -q "${pkg}" >/dev/null 2>&1; then
            echo "Forbidden package present: ${pkg}"
            exit 1
        fi
    done

    echo "Package surface audit passed for ${local_ref}"

# Push a local image to the target registry
[group('Security')]
push-local $source_image=image_name $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    local_ref="${source_image}:${tag}"
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        local_ref="localhost/${source_image}:${tag}"
    fi
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        echo "Local image not found: ${source_image}:${tag}"
        echo "Build it first with: just build"
        exit 1
    fi

    digest_dir="output/signing"
    mkdir -p "${digest_dir}"
    ref_key=${target_image//\//_}
    ref_key=${ref_key//:/_}
    digest_file="${digest_dir}/${ref_key}-${tag}.digest"

    podman tag "${local_ref}" "${target_image}:${tag}"
    podman push --digestfile "${digest_file}" "${target_image}:${tag}"

# Sign a pushed image using local cosign keys
[group('Security')]
sign-local $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v cosign &> /dev/null; then
        echo "cosign not found. Install: go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
        exit 1
    fi
    [[ -f cosign.key ]] || { echo "Missing cosign.key"; exit 1; }
    [[ -f cosign.pub ]] || { echo "Missing cosign.pub"; exit 1; }

    ref_key=${target_image//\//_}
    ref_key=${ref_key//:/_}
    digest_file="output/signing/${ref_key}-${tag}.digest"
    if [[ ! -f "${digest_file}" ]]; then
        echo "No digest file found for ${target_image}:${tag}"
        echo "Push it first with: just push-local ${image_name} ${target_image} ${tag}"
        exit 1
    fi
    digest_ref="${target_image}@$(<"${digest_file}")"

    cosign sign --key cosign.key -y "${digest_ref}"

# Verify a pushed image signature using the local public key
[group('Security')]
verify-local-signature $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v cosign &> /dev/null; then
        echo "cosign not found. Install: go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
        exit 1
    fi
    [[ -f cosign.pub ]] || { echo "Missing cosign.pub"; exit 1; }
    ref_key=${target_image//\//_}
    ref_key=${ref_key//:/_}
    digest_file="output/signing/${ref_key}-${tag}.digest"
    [[ -f "${digest_file}" ]] || { echo "Missing digest file for ${target_image}:${tag}"; exit 1; }
    digest_ref="${target_image}@$(<"${digest_file}")"
    cosign verify --key cosign.pub "${digest_ref}"

# Build, audit, push, sign, and verify locally
[group('Security')]
promote-local $source_image=image_name $target_image=("ghcr.io/" + env("GITHUB_REPOSITORY_OWNER", env("USER", "local")) + "/" + image_name) $tag=default_tag:
    just build "{{ source_image }}" "{{ tag }}"
    just audit-security "{{ source_image }}" "{{ tag }}"
    just audit-package-surface "{{ source_image }}" "{{ tag }}"
    just push-local "{{ source_image }}" "{{ target_image }}" "{{ tag }}"
    just sign-local "{{ target_image }}" "{{ tag }}"
    just verify-local-signature "{{ target_image }}" "{{ tag }}"
    just verify-remote-image "{{ target_image }}" "{{ tag }}"
