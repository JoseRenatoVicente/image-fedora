#!/usr/bin/env bats
# Source-level tests: script maintenance policies

setup() {
    load '../helpers/common'
    build_just="${REPO_ROOT}/just/build.just"
    testing_just="${REPO_ROOT}/just/testing.just"
    utility_just="${REPO_ROOT}/just/utility.just"
    log_collector="${REPO_ROOT}/tools/log-uploader/collect-vm-logs.sh"
    build_packages="${REPO_ROOT}/build_files/scripts/build-packages.sh"
    build_deps="${REPO_ROOT}/build_files/scripts/configure/70-build-deps.sh"
    build_configure="${REPO_ROOT}/build_files/scripts/build-configure.sh"
    system_configure="${REPO_ROOT}/build_files/scripts/configure/10-system.sh"
    cleanup_configure="${REPO_ROOT}/build_files/scripts/configure/90-cleanup.sh"
    install_assets="${REPO_ROOT}/build_files/scripts/install-assets.sh"
    plasmalogin_configure="${REPO_ROOT}/build_files/scripts/configure/20-plasmalogin.sh"
    skel_configure="${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh"
    services_configure="${REPO_ROOT}/build_files/scripts/configure/50-services.sh"
    overlay="${REPO_ROOT}/build_files/overlay"
    installer_build="${REPO_ROOT}/installer/build.sh"
    installer_containerfile="${REPO_ROOT}/installer/Containerfile"
    anaconda_profile_installer="${REPO_ROOT}/installer/system_files/shared/etc/anaconda/profile.d/image-fedora.conf"
    anaconda_profile_overlay="${REPO_ROOT}/build_files/overlay/etc/anaconda/profile.d/image-fedora.conf"
}

@test "podman test boot does not force interactive TTY" {
    assert_not_contains "$testing_just" 'sudo podman run --rm -it --privileged --pull=newer'
}

@test "temporary podman copy directories are cleaned with traps" {
    assert_contains "$build_just" 'cleanup_copytmp()'
    assert_contains "$build_just" 'trap cleanup_copytmp EXIT'
}

@test "podman copy cleanup trap succeeds after temp dir is cleared" {
    local script="$BATS_TEST_TMPDIR/cleanup-copytmp.sh"
    {
        printf '%s\n' 'set -euo pipefail'
        printf '%s\n' 'COPYTMP=""'
        awk '
            /^[[:space:]]+cleanup_copytmp\(\) \{/ { in_func=1 }
            in_func {
                line = $0
                sub(/^    /, "", line)
                print line
                if (line == "}") exit
            }
        ' "$build_just"
        printf '%s\n' 'trap cleanup_copytmp EXIT'
        printf '%s\n' 'COPYTMP=""'
    } > "$script"

    run bash "$script"
    [ "$status" -eq 0 ]
}

@test "temporary bootc image builder directory is cleaned with trap" {
    assert_contains "$build_just" 'cleanup_buildtmp()'
    assert_contains "$build_just" 'trap cleanup_buildtmp EXIT'
}

@test "bootc image builder cleanup trap succeeds after temp dir is cleared" {
    local script="$BATS_TEST_TMPDIR/cleanup-buildtmp.sh"
    {
        printf '%s\n' 'set -euo pipefail'
        printf '%s\n' 'BUILDTMP=""'
        awk '
            /^[[:space:]]+cleanup_buildtmp\(\) \{/ { in_func=1 }
            in_func {
                line = $0
                sub(/^    /, "", line)
                print line
                if (line == "}") exit
            }
        ' "$build_just"
        printf '%s\n' 'trap cleanup_buildtmp EXIT'
        printf '%s\n' 'BUILDTMP=""'
    } > "$script"

    run bash "$script"
    [ "$status" -eq 0 ]
}

@test "local build passes package and config cache keys" {
    assert_contains "$build_just" 'set -euo pipefail'
    assert_contains "$build_just" 'PKG_CACHE_KEY=$(git ls-files'
    assert_contains "$build_just" 'CONFIG_CACHE_KEY=$(git ls-files'
    assert_contains "$build_just" 'PKG_CACHE_KEY=${PKG_CACHE_KEY}'
    assert_contains "$build_just" 'CONFIG_CACHE_KEY=${CONFIG_CACHE_KEY}'
}

@test "just formatting stays in versioned script paths" {
    assert_not_contains "$utility_just" '/usr/bin/find . -iname "*.sh"'
    assert_contains "$utility_just" 'find build_files tests tools'
}

@test "just syntax formatting avoids worktrees" {
    assert_contains "$utility_just" 'for file in Justfile just/*.just; do'
    assert_not_contains "$utility_just" 'find . -type f -name "*.just"'
}

@test "clean removes only known generated paths" {
    assert_not_contains "$utility_just" 'find *_build* -exec rm -rf {} \;'
    assert_contains "$utility_just" 'rm -rf _build-bib.* _build-test.* _build_podman_scp.*'
}

@test "log collector grep capture filters applet loading errors" {
    assert_contains "$log_collector" 'grep -iE "error.*loading.*applet|applet.*error"'
}

@test "package filtering is centralized" {
    assert_contains "$build_packages" 'installed_packages_from'
    assert_contains "$build_deps" 'installed_packages_from'
}

@test "configure step closes GitHub log group on failures" {
    assert_contains "$build_configure" 'trap '\''echo "::endgroup::"'\'' RETURN'
}

@test "usr overlay does not overwrite dnf5 through dnf symlink" {
    local remove_line overlay_line
    remove_line=$(grep -nF 'rm -f /usr/bin/dnf' "$system_configure" | cut -d: -f1)
    overlay_line=$(grep -nF 'cp -aT /ctx/overlay/usr/ /usr/' "$system_configure" | cut -d: -f1)

    [[ -n "$remove_line" ]] || { echo "expected /usr/bin/dnf to be removed before usr overlay"; return 1; }
    [[ -n "$overlay_line" ]] || { echo "expected usr overlay copy in $system_configure"; return 1; }
    [[ "$remove_line" -lt "$overlay_line" ]] \
        || { echo "expected /usr/bin/dnf removal before usr overlay copy"; return 1; }
}

@test "plasmalogin workaround files live in overlay" {
    assert_file_exists "$overlay/usr/lib/systemd/system/fedora-kinoite-plasmalogin-workaround.service"
    assert_file_exists "$overlay/usr/libexec/fedora-kinoite-plasmalogin-workaround"
    assert_contains "$overlay/usr/lib/systemd/system/fedora-kinoite-plasmalogin-workaround.service" 'ExecStart=/usr/libexec/fedora-kinoite-plasmalogin-workaround'
}

@test "plasmalogin configure script does not generate static files" {
    assert_not_contains "$plasmalogin_configure" 'cat > /usr/lib/systemd/system/fedora-kinoite-plasmalogin-workaround.service'
    assert_not_contains "$plasmalogin_configure" 'cat > /usr/libexec/fedora-kinoite-plasmalogin-workaround'
    assert_not_contains "$plasmalogin_configure" 'cat >> /usr/lib/systemd/system-preset/35-security-desktop.preset'
}

@test "tuned active profile files live in overlay" {
    assert_file_exists "$overlay/etc/tuned/active_profile"
    assert_file_exists "$overlay/etc/tuned/profile_mode"
    assert_contains "$overlay/etc/tuned/active_profile" 'balanced-workstation'
    assert_contains "$overlay/etc/tuned/profile_mode" 'auto'
}

@test "KDE first-boot user units live in overlay" {
    for script in fedora-shell-setup fedora-dev-setup fedora-brew-setup; do
        assert_file_exists "$overlay/etc/skel/.config/systemd/user/${script}.service"
        assert_file_exists "$overlay/etc/skel/.config/systemd/user/${script}.timer"
        assert_file_exists "$overlay/etc/skel/.config/systemd/user/timers.target.wants/${script}.timer"
        run test -L "$overlay/etc/skel/.config/systemd/user/timers.target.wants/${script}.timer"
        [ "$status" -eq 0 ]
        run readlink "$overlay/etc/skel/.config/systemd/user/timers.target.wants/${script}.timer"
        [ "$status" -eq 0 ]
        [ "$output" = "../${script}.timer" ]
    done
}

@test "libvirt user qemu config disables core dumps in skel" {
    local qemu_config="$overlay/etc/skel/.config/libvirt/qemu.conf"
    assert_file_exists "$qemu_config"
    assert_contains "$qemu_config" 'max_core = 0'
}

@test "local Plasma desktop layout lives in overlay" {
    assert_file_exists "$overlay/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
    assert_contains "$skel_configure" '/ctx/overlay/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc'
    assert_not_contains "$skel_configure" '/ctx/skel/.config/plasma-org.kde.plasma.desktop-appletsrc'
}

@test "kwin VM compatibility files live in overlay" {
    assert_file_exists "$overlay/usr/libexec/kwin-vm-compat.sh"
    assert_file_exists "$overlay/etc/xdg/autostart/kwin-vm-compat.desktop"
    assert_contains "$overlay/etc/xdg/autostart/kwin-vm-compat.desktop" 'Exec=/usr/libexec/kwin-vm-compat.sh'
}

@test "skel configure script does not install overlay-owned static files" {
    assert_not_contains "$skel_configure" '/ctx/skel/.config/systemd/user/'
    assert_not_contains "$skel_configure" '/ctx/skel/.local/bin/kwin-vm-compat.sh'
    assert_not_contains "$skel_configure" '/ctx/skel/.config/autostart/kwin-vm-compat.desktop'
}

@test "local timezone is represented by overlay" {
    run test -L "$overlay/etc/localtime"
    [ "$status" -eq 0 ]
    run readlink "$overlay/etc/localtime"
    [ "$status" -eq 0 ]
    [ "$output" = "/usr/share/zoneinfo/America/Sao_Paulo" ]
    assert_not_contains "$cleanup_configure" 'ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime'
}

@test "services configure script does not generate tuned active profile files" {
    assert_not_contains "$services_configure" 'echo "balanced-workstation" > /etc/tuned/active_profile'
    assert_not_contains "$services_configure" 'echo "auto" > /etc/tuned/profile_mode'
}

@test "legacy scx.service config asset is removed" {
    run test -e "${REPO_ROOT}/build_files/assets/configs/scx-default.conf"
    [ "$status" -ne 0 ]
}

@test "installer image reference parser preserves ports and digests" {
    assert_contains "$installer_build" 'install_image_ref="${_ref}"'
    assert_not_contains "$installer_build" 'imageref="${_ref%%:*}"'
    assert_not_contains "$installer_build" 'imagetag="${_ref##*:}"'
}

@test "installer ISO does not force SELinux permissive mode" {
    assert_not_contains "${REPO_ROOT}/installer/iso.yaml" 'enforcing=0'
}

@test "image-fedora Anaconda profile lives in installer and overlay" {
    assert_file_exists "$anaconda_profile_installer"
    assert_file_exists "$anaconda_profile_overlay"
    cmp -s "$anaconda_profile_installer" "$anaconda_profile_overlay" || {
        echo "expected installer and overlay Anaconda profiles to match" >&2
        return 1
    }
}

@test "image-fedora Anaconda profile uses BTRFS defaults" {
    assert_contains "$anaconda_profile_installer" 'profile_id = image-fedora'
    assert_contains "$anaconda_profile_installer" 'os_id = fedora'
    assert_contains "$anaconda_profile_installer" 'default_scheme = BTRFS'
    assert_contains "$anaconda_profile_installer" 'btrfs_compression = zstd:1'
    assert_contains "$anaconda_profile_installer" 'default_partitioning ='
    assert_contains "$anaconda_profile_installer" '    /     (min 1 GiB, max 70 GiB)'
    assert_contains "$anaconda_profile_installer" '    /home (min 500 MiB, free 50 GiB)'
    assert_contains "$anaconda_profile_installer" '    /var  (btrfs)'
    assert_contains "$anaconda_profile_installer" 'hidden_webui_pages ='
    assert_contains "$anaconda_profile_installer" '    network'
}

@test "installer copies shared system files into live image" {
    assert_contains "$installer_build" 'cp -a /src/system_files/shared/. /'
}

@test "installer embeds payload and installs from container storage" {
    assert_contains "$installer_build" 'mountpoint -q /usr/lib/containers/storage'
    assert_contains "$installer_build" 'podman save --format oci-archive "$INSTALL_IMAGE_PAYLOAD"'
    assert_contains "$installer_build" 'podman pull "$INSTALL_IMAGE_PAYLOAD"'
    assert_contains "$installer_build" '--transport=containers-storage --no-signature-verification'
    assert_not_contains "$installer_build" '--transport=registry --no-signature-verification'
}

@test "installer lets Anaconda profile own storage defaults" {
    assert_not_contains "$installer_build" 'part / --fstype=xfs --size=20480'
    assert_not_contains "$installer_build" 'part /home --fstype=xfs --size=1 --grow'
}

@test "installer Containerfile uses literal ARG defaults" {
    assert_contains "$installer_containerfile" 'ARG BASE_IMAGE=ghcr.io/joserenatovicente/image-fedora:latest'
    assert_contains "$installer_containerfile" 'ARG INSTALL_IMAGE_PAYLOAD=ghcr.io/joserenatovicente/image-fedora:latest'
    assert_not_contains "$installer_containerfile" '${BASE_IMAGE:-'
}

@test "winapps assets are installed under immutable /usr/share" {
    assert_contains "$install_assets" 'SYS_APP_PATH="/usr/share/winapps"'
    assert_contains "$install_assets" 'mkdir -p /usr/share/winapps'
    assert_not_contains "$install_assets" 'mkdir -p /usr/local/share/winapps'
}

@test "cleanup removes build-time var state flagged by bootc lint" {
    assert_contains "$cleanup_configure" 'rm -rf /var/lib/authselect/checksum'
    assert_contains "$cleanup_configure" 'rm -rf /var/lib/fprint /var/lib/iscsi'
}
