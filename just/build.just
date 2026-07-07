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
    set -euo pipefail

    BUILD_ARGS=()
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    if [[ -n "${image_vendor:-}" ]]; then
        BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR=${image_vendor}")
    fi
    PKG_CACHE_INPUTS=(
        Containerfile
        build_files/scripts/build-packages.sh
        build_files/scripts/shared/copr-helpers.sh
        build_files/scripts/shared/common.sh
        build_files/scripts/shared/package-lists.sh
        build_files/assets/configs/dnf-performance.conf
    )
    PKG_CACHE_KEY=$(git ls-files --cached --others --exclude-standard "${PKG_CACHE_INPUTS[@]}" | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
    CONFIG_CACHE_KEY=$(git ls-files --cached --others --exclude-standard Containerfile build_files | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
    BUILD_ARGS+=("--build-arg" "PKG_CACHE_KEY=${PKG_CACHE_KEY}")
    BUILD_ARGS+=("--build-arg" "CONFIG_CACHE_KEY=${CONFIG_CACHE_KEY}")

    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Build the dev toolbox image locally (same image published to ghcr.io/<owner>/toolbox-dev)
[group('Toolbox')]
build-toolbox-dev $tag=default_tag:
    podman build --pull=newer --tag "toolbox-dev:{{tag}}" -f Containerfile.toolbox-dev .

# Build the infra toolbox image locally (same image published to ghcr.io/<owner>/toolbox-infra)
[group('Toolbox')]
build-toolbox-infra $tag=default_tag:
    podman build --pull=newer --tag "toolbox-infra:{{tag}}" -f Containerfile.toolbox-infra .

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

    COPYTMP=""
    cleanup_copytmp() {
        [[ -n "${COPYTMP}" ]] && rm -rf "${COPYTMP}"
        return 0
    }
    trap cleanup_copytmp EXIT

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
                COPYTMP=""
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
            COPYTMP=""
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

    BUILDTMP=""
    cleanup_buildtmp() {
        [[ -n "${BUILDTMP}" ]] && sudo rm -rf "${BUILDTMP}"
        return 0
    }
    trap cleanup_buildtmp EXIT

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
    BUILDTMP=""
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
