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
