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
    cleanup_configure="${REPO_ROOT}/build_files/scripts/configure/90-cleanup.sh"
    install_assets="${REPO_ROOT}/build_files/scripts/install-assets.sh"
    plasmalogin_configure="${REPO_ROOT}/build_files/scripts/configure/20-plasmalogin.sh"
    services_configure="${REPO_ROOT}/build_files/scripts/configure/50-services.sh"
    overlay="${REPO_ROOT}/build_files/overlay"
    installer_build="${REPO_ROOT}/installer/build.sh"
    installer_containerfile="${REPO_ROOT}/installer/Containerfile"
}

@test "podman test boot does not force interactive TTY" {
    assert_not_contains "$testing_just" 'sudo podman run --rm -it --privileged --pull=newer'
}

@test "temporary podman copy directories are cleaned with traps" {
    assert_contains "$build_just" 'cleanup_copytmp()'
    assert_contains "$build_just" 'trap cleanup_copytmp EXIT'
}

@test "temporary bootc image builder directory is cleaned with trap" {
    assert_contains "$build_just" 'cleanup_buildtmp()'
    assert_contains "$build_just" 'trap cleanup_buildtmp EXIT'
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
