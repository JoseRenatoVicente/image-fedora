export image_name := env("IMAGE_NAME", "fedora-kde-custom") # output image name, usually same as repo name, change as needed
export image_vendor := env("IMAGE_VENDOR", env("GITHUB_REPOSITORY_OWNER", "")) # ghcr.io owner; auto-detected in CI
export default_tag := env("DEFAULT_TAG", "latest")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder@sha256:7ae88b8d6f2cabfa971d7836b96d6cac19cd1384e658031bd154f9687e929905")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2
alias test := test-container

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SUDO_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# This Justfile recipe builds a container image using Podman.
#
# Arguments:
#   $target_image - The tag you want to apply to the image (default: $image_name).
#   $tag - The tag for the image (default: $default_tag).
#
# The script constructs the version string using the tag and the current date.
# If the git working directory is clean, it also includes the short SHA of the current HEAD.
#
# just build $target_image $tag
#
# Example usage:
#   just build aurora lts
#
# This will build an image 'aurora:lts' with DX and GDX enabled.
#

# Build the image using the specified parameters
build $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash

    BUILD_ARGS=()
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    if [[ -n "${image_vendor:-}" ]]; then
        BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR=${image_vendor}")
    fi

    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Command: _rootful_load_image
# Description: This script checks if the current user is root or running under sudo. If not, it attempts to resolve the image tag using podman inspect.
#              If the image is found, it loads it into rootful podman. If the image is not found, it pulls it from the repository.
#
# Parameters:
#   $target_image - The name of the target image to be loaded or pulled.
#   $tag - The tag of the target image to be loaded or pulled. Default is 'default_tag'.
#
# Example usage:
#   _rootful_load_image my_image latest
#
# Steps:
# 1. Check if the script is already running as root or under sudo.
# 2. Check if target image is in the non-root podman container storage)
# 3. If the image is found, load it into rootful podman using podman scp.
# 4. If the image is not found, pull it from the remote repository into reootful podman.

_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/bash
    set -eoux pipefail

    # Check if already running as root or under sudo
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        # Verify the image actually exists in root podman storage
        if podman image exists "${target_image}:${tag}" 2>/dev/null; then
            echo "Already root/sudo and image exists in root storage."
            exit 0
        fi

        # Image not in root storage; try to copy from the calling user's storage
        if [[ -n "${SUDO_USER:-}" ]]; then
            SUDO_UID=$(id -u "${SUDO_USER}")
            set +e
            sudo -u "${SUDO_USER}" podman image exists "${target_image}:${tag}" 2>/dev/null
            user_has_image=$?
            set -e
            if [[ $user_has_image -eq 0 ]]; then
                echo "Copying image from ${SUDO_USER}'s podman storage to root storage..."
                COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
                chmod 1777 "${COPYTMP}"
                TMPDIR=${COPYTMP} podman image scp ${SUDO_UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
                rm -rf "${COPYTMP}"
                exit 0
            fi
        fi

        echo "Error: Image '${target_image}:${tag}' not found in root podman storage."
        echo "Build it first with: just build"
        echo "Then re-run: sudo just build-qcow2"
        exit 1
    fi

    # Try to resolve the image tag using podman inspect
    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")

    if [[ $return_code -eq 0 ]]; then
        # If the image is found, load it into rootful podman
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            # If the image ID is not found or different from user, copy the image from user podman to root podman
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            chmod 1777 "${COPYTMP}"
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        # If the image is not found, pull it from the repository
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 disk_config/disk.toml
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)

    sudo podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${target_image}:${tag}"

    mkdir -p output
    sudo rm -rf "output/${type}"
    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Podman builds the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (deafult: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 disk_config/disk.toml
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "disk_config/disk.toml")

# Build a RAW virtual machine image
[group('Build Virtal Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "raw" "disk_config/disk.toml")

# Build an ISO virtual machine image
[group('Build Virtal Machine Image')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "iso" "disk_config/iso.toml")

# Rebuild a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "disk_config/disk.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtal Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "raw" "disk_config/disk.toml")

# Rebuild an ISO virtual machine image
[group('Build Virtal Machine Image')]
rebuild-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=6G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "BOOT_MODE=uefi")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "WIDTH=1920")
    run_args+=(--env "HEIGHT=1080")
    run_args+=(--device=/dev/kvm)

    # Passa dispositivos DRI do host para habilitar aceleração GPU (VirtGL)
    # Sem estes devices o qemux não consegue criar /dev/dri/card0 e cai em CPU rendering
    if [[ -d /dev/dri ]]; then
        run_args+=(--device=/dev/dri)
        run_args+=(--env "GPU=Y")
    else
        run_args+=(--env "GPU=N")
        echo "WARN: /dev/dri não encontrado, GPU desabilitada"
    fi

    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect (como usuário real se via sudo)
    if [[ -n "${SUDO_USER:-}" ]]; then
      (sleep 30 && sudo -u "${SUDO_USER}" xdg-open http://localhost:"$port") &
    else
      (sleep 30 && xdg-open http://localhost:"$port") &
    fi
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "disk_config/disk.toml")

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "disk_config/disk.toml")

# Run a virtual machine from an ISO
[group('Run Virtal Machine')]
run-vm-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine with native QEMU + virtio-vga-gl (OpenGL real via virgl)
# Requer: qemu-system-x86_64, edk2-ovmf  →  sudo dnf install -y qemu-kvm edk2-ovmf
# Usa virtio-vga-gl: dá GL acelerado (virgl) → sem o flood de "ZINK: failed to
# choose pdev" que o qxl provoca (qxl não tem Vulkan). Contrapartida: o virtio_gpu
# NÃO está no initramfs, então o Plymouth não aparece nesta VM (cai em texto). No
# HW real o Plymouth funciona (rhgb + driver nativo no initramfs). Para ter Plymouth
# TAMBÉM na VM seria preciso pôr virtio_gpu/simpledrm no initramfs (regenerá-lo).
[group('Run Virtal Machine')]
run-vm-gl type="qcow2" ram="8G" cpus="4":
    #!/usr/bin/env bash
    set -euo pipefail

    image_file="output/{{ type }}/disk.{{ type }}"
    if [[ ! -f "${image_file}" ]]; then
        echo "Imagem não encontrada: ${image_file}"
        echo "Execute primeiro: just build-{{ type }}"
        exit 1
    fi

    # Verificar dependências
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        echo "qemu-system-x86_64 não encontrado. Instale com:"
        echo "  sudo dnf install -y qemu-kvm edk2-ovmf"
        exit 1
    fi

    # Localizar firmware UEFI
    OVMF_CODE=""
    OVMF_VARS_SRC=""
    for candidate in \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/qemu/OVMF_CODE.fd; do
        if [[ -f "$candidate" ]]; then
            OVMF_CODE="$candidate"
            OVMF_VARS_SRC="${candidate/CODE/VARS}"
            break
        fi
    done
    if [[ -z "$OVMF_CODE" ]]; then
        echo "OVMF não encontrado. Instale: sudo dnf install -y edk2-ovmf"
        exit 1
    fi

    # VARS precisa de uma cópia gravável por sessão
    # Usa XDG_RUNTIME_DIR (/run/user/UID) que tem espaço garantido; /tmp pode ter quota
    _tmpdir="${XDG_RUNTIME_DIR:-${HOME}/.cache}"
    OVMF_VARS_TMP=$(mktemp "${_tmpdir}/OVMF_VARS_XXXXXXXXXX.fd")
    cp "${OVMF_VARS_SRC:-${OVMF_CODE/CODE/VARS}}" "$OVMF_VARS_TMP"
    trap "rm -f '$OVMF_VARS_TMP'" EXIT

    RAM_BYTES=$(echo "{{ ram }}" | numfmt --from=iec)
    RAM_MB=$(( RAM_BYTES / 1024 / 1024 ))

    echo "Iniciando VM KDE — janela SDL com OpenGL (virtio-vga-gl/virgl)"
    echo "  Imagem : ${image_file}"
    echo "  RAM    : ${RAM_MB}M  CPUs: {{ cpus }}"
    echo "  GPU    : virtio-vga-gl (OpenGL via host; sem Plymouth na VM)"

    qemu-system-x86_64 \
        -enable-kvm \
        -machine q35 \
        -cpu host \
        -smp "{{ cpus }}" \
        -m "${RAM_MB}M" \
        -device virtio-vga-gl,xres=1920,yres=1080 \
        -display sdl,gl=on \
        -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,file=${OVMF_VARS_TMP}" \
        -drive "file=${image_file},format={{ type }},if=virtio,cache=writeback,discard=unmap" \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -device virtio-balloon-pci \
        -device virtio-rng-pci \
        -usb -device usb-tablet \
        -audiodev pa,id=snd0 \
        -device ich9-intel-hda \
        -device hda-duplex,audiodev=snd0 \
        -rtc base=localtime \
        -boot menu=on

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'

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
        --certificate-identity-regexp='https://github.com/.+' \
        --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
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
        --certificate-identity-regexp='https://github.com/.+' \
        --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
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

# ── Testes automatizados ──────────────────────────────────────────────────────

# Corre os testes estáticos contra a imagem de container já construída (sem boot).
# Rápido (~30s). Equivalente ao que corre no final do build, mas invocável a qualquer momento.
# Requer: just build (ou just rebuild-qcow2 — a imagem container deve existir)
[group('Testing')]
test-container $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    local_ref="${target_image}:${tag}"
    podman image exists "${local_ref}" 2>/dev/null || local_ref="localhost/${target_image}:${tag}"
    if ! podman image exists "${local_ref}" 2>/dev/null; then
        echo "Imagem não encontrada. Execute primeiro: just build"
        exit 1
    fi
    echo "A correr testes estáticos em: ${local_ref}"
    # O tests.sh corre dentro do container com bind-mount do host — não precisa de estar na imagem
    podman run --rm \
        --security-opt label=disable \
        -v "$(pwd)/build_files/shared/tests.sh:/run/tests.sh:ro,z" \
        "${local_ref}" \
        bash /run/tests.sh

# Constrói a imagem de teste (extensão da produção com health check de boot).
# A imagem de produção deve existir localmente; `just test-boot` reconstrói-a antes.
[group('Testing')]
test-build:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! podman image exists "localhost/{{ image_name }}:{{ default_tag }}" 2>/dev/null && \
       ! podman image exists "{{ image_name }}:{{ default_tag }}" 2>/dev/null; then
        echo "Imagem de produção não encontrada. Execute primeiro: just build"
        exit 1
    fi
    echo "A construir imagem de teste..."
    podman build \
        -f Containerfile.test \
        --tag "fedora-kde-test:latest" \
        .
    echo "Imagem de teste pronta: fedora-kde-test:latest"

# Boot test headless: reconstrói a imagem de produção, constrói QCOW2 de teste,
# arranca em QEMU sem display, aguarda o health check e reporta PASS/FAIL.
# Dependências: qemu-kvm edk2-ovmf  →  sudo dnf install -y qemu-kvm edk2-ovmf
[group('Testing')]
test-boot timeout="420":
    #!/usr/bin/env bash
    set -euo pipefail

    # Garante que o teste usa a imagem de produção gerada a partir do working tree atual.
    just build

    # Garante que a imagem de teste está construída sobre a produção atual.
    just test-build

    if ! command -v qemu-system-x86_64 &>/dev/null; then
        echo "qemu-system-x86_64 não encontrado. Instale: sudo dnf install -y qemu-kvm edk2-ovmf"
        exit 1
    fi

    # Localizar OVMF
    OVMF_CODE=""
    for candidate in \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/qemu/OVMF_CODE.fd; do
        [[ -f "$candidate" ]] && OVMF_CODE="$candidate" && break
    done
    [[ -z "$OVMF_CODE" ]] && { echo "OVMF não encontrado. Instale: sudo dnf install -y edk2-ovmf"; exit 1; }

    _tmpdir="${XDG_RUNTIME_DIR:-${HOME}/.cache}"
    OVMF_VARS=$(mktemp "${_tmpdir}/OVMF_VARS_XXXXXX.fd")
    cp "${OVMF_CODE/CODE/VARS}" "$OVMF_VARS"
    trap "rm -f '$OVMF_VARS'" EXIT

    # Construir QCOW2 de teste via bootc-image-builder
    echo "A converter imagem de teste para QCOW2..."
    just _rootful_load_image localhost/fedora-kde-test latest
    TEST_BUILDTMP=$(mktemp -d -p "${PWD}" _build-test.XXXXXX)
    sudo podman run --rm -it --privileged --pull=newer \
        --net=host \
        --security-opt label=type:unconfined_t \
        -v "$(pwd)/disk_config/disk.toml":/config.toml:ro \
        -v "${TEST_BUILDTMP}":/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "${bib_image}" \
        --type qcow2 --use-librepo=True --rootfs=btrfs \
        localhost/fedora-kde-test:latest
    sudo chown -R "$USER:$USER" "${TEST_BUILDTMP}" 2>/dev/null || true

    TEST_QCOW="${TEST_BUILDTMP}/qcow2/disk.qcow2"
    [[ -f "$TEST_QCOW" ]] || { echo "QCOW2 de teste não encontrado em $TEST_QCOW"; exit 1; }

    RESULTS_LOG=$(mktemp "${_tmpdir}/boot-test-results.XXXXXX")
    CLEAN_TEST_BUILDTMP=1
    trap 'rm -f "'$OVMF_VARS'"; [[ "${CLEAN_TEST_BUILDTMP:-0}" == "1" ]] && rm -rf "'${TEST_BUILDTMP}'"' EXIT

    echo ""
    echo "A iniciar boot test headless (timeout: {{ timeout }}s)..."
    echo "QCOW2 : $TEST_QCOW"
    echo "Log   : $RESULTS_LOG"
    echo ""

    # Boot headless:
    #   -display none       → descarta output VGA (sem janela)
    #   -device virtio-vga  → VGA existe (SDDM/KDE precisa de um device)
    #   -serial mon:stdio   → serial (ttyS0) capturado em stdout → log
    # NÃO usar -nographic aqui: implica sem VGA device e redirects serial
    # de forma diferente — conflita com -display none + -serial explícito.
    qemu-system-x86_64 \
        -enable-kvm \
        -machine q35,kernel-irqchip=split \
        -device intel-iommu,intremap=on,caching-mode=on \
        -cpu host \
        -smp 4 \
        -m 4G \
        -display none \
        -device virtio-vga \
        -serial mon:stdio \
        -no-reboot \
        -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,file=${OVMF_VARS}" \
        -drive "file=${TEST_QCOW},format=qcow2,if=virtio,cache=writeback" \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -device virtio-rng-pci \
        -device virtio-balloon-pci \
        >"$RESULTS_LOG" 2>&1 &
    QEMU_PID=$!

    echo "QEMU PID: $QEMU_PID — aguardando marcadores BOOT- (timeout: {{ timeout }}s)..."
    echo "─────────────────────────────────────────────────"

    # Mostra linhas BOOT- em tempo real enquanto espera
    tail -n 0 -f "$RESULTS_LOG" 2>/dev/null | grep --line-buffered "BOOT-" &
    TAIL_PID=$!

    # Poll por BOOT-DONE ou até timeout
    DEADLINE=$(( SECONDS + {{ timeout }} ))
    while [[ $SECONDS -lt $DEADLINE ]] && kill -0 "$QEMU_PID" 2>/dev/null; do
        grep -q "BOOT-DONE:" "$RESULTS_LOG" 2>/dev/null && break
        sleep 5
    done

    kill "$TAIL_PID" 2>/dev/null || true
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true

    echo ""
    echo "═══════════════════════════════════════"

    # Analisar resultados
    FAILS=$(grep "^BOOT-FAIL" "$RESULTS_LOG" 2>/dev/null || true)
    WARNS=$(grep "^BOOT-WARN" "$RESULTS_LOG" 2>/dev/null || true)
    DONE=$(grep "^BOOT-DONE:" "$RESULTS_LOG" 2>/dev/null || true)

    # Avisos são informativos (não falham o teste) mas são sempre exibidos.
    if [[ -n "$WARNS" ]]; then
        echo ""
        echo "── AVISOS surfacados (não-fatais, para correção) ──"
        echo "$WARNS"
    fi

    if [[ -z "$DONE" ]]; then
        CLEAN_TEST_BUILDTMP=0
        echo "RESULTADO: INCONCLUSIVO (timeout sem BOOT-DONE)"
        echo ""
        echo "Possíveis erros no log:"
        grep -iE "fail|error|emergency|dracut|ostree|mount|root" "$RESULTS_LOG" 2>/dev/null | tail -80 || true
        echo ""
        echo "Últimas linhas do log:"
        tail -80 "$RESULTS_LOG"
        echo ""
        echo "Log preservado para análise: $RESULTS_LOG"
        echo "QCOW2 preservado para análise: $TEST_QCOW"
        exit 1
    elif [[ -n "$FAILS" ]]; then
        CLEAN_TEST_BUILDTMP=0
        echo "RESULTADO: FALHOU"
        echo ""
        echo "$FAILS"
        echo ""
        echo "Log preservado para análise: $RESULTS_LOG"
        echo "QCOW2 preservado para análise: $TEST_QCOW"
        exit 1
    else
        echo "RESULTADO: PASSOU ✓"
        grep "^BOOT-PASS\|^BOOT-INFO" "$RESULTS_LOG" 2>/dev/null || true
    fi
    echo "═══════════════════════════════════════"
