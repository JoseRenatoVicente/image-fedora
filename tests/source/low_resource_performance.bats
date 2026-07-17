#!/usr/bin/env bats
# Source-level tests: low-resource performance configuration

setup() {
    load '../helpers/common'
}

@test "zram-generator.conf exists and uses zstd" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/systemd/zram-generator.conf" 'compression-algorithm=zstd'
}

@test "zram-generator.conf limits RAM usage" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/systemd/zram-generator.conf" 'zram-size = min(ram / 4 + 1024, 4096)'
}

@test "low-resource sysctl exists and sets swappiness" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/share/image-fedora/low-resource/100-low-resource.conf" 'vm.swappiness = 60'
}

@test "low-resource sysctl increases cache pressure" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/share/image-fedora/low-resource/100-low-resource.conf" 'vm.vfs_cache_pressure = 200'
}

@test "low-resource sysctl disables swap read-ahead" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/share/image-fedora/low-resource/100-low-resource.conf" 'vm.page-cluster = 0'
}

@test "low-resource tuning is gated behind a RAM condition, not unconditional" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/low-resource-tuning.service" 'ConditionMemory=<=6G'
    assert_file_not_exists "${REPO_ROOT}/build_files/overlay/etc/sysctl.d/100-low-resource.conf"
}

@test "99-performance.conf swappiness is not shadowed by an unconditional overlay" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/sysctl.d/99-performance.conf" 'vm.swappiness = 180'
}

@test "bluetooth is disabled by preset" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system-preset/35-security-desktop.preset" 'disable bluetooth.service'
}

@test "geoclue-demo-agent autostart is hidden" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/xdg/autostart/geoclue-demo-agent.desktop" 'Hidden=true'
}

@test "AMD CPB boost supports both AMD CPU frequency drivers" {
    local service="${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/amd-cpb-boost.service"
    assert_contains "$service" 'AuthenticAMD'
    assert_contains "$service" '/sys/devices/system/cpu/amd_pstate/cpb_boost'
    assert_contains "$service" '/sys/devices/system/cpu/cpufreq/boost'
}

@test "orphaned session helpers are masked to /dev/null" {
    for unit in mpris-proxy.service obex.service; do
        local path="${REPO_ROOT}/build_files/overlay/etc/systemd/user/${unit}"
        [ -L "$path" ]
        [ "$(readlink "$path")" = "/dev/null" ]
    done
}
