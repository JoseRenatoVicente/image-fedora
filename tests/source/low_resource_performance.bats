#!/usr/bin/env bats
# Source-level tests: low-resource performance configuration

setup() {
    load '../helpers/common'
}

@test "zram-generator.conf exists and uses zstd" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/systemd/zram-generator.conf" 'compression-algorithm = zstd'
}

@test "zram-generator.conf allocates half RAM" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/systemd/zram-generator.conf" 'zram-size = ram / 2'
}

@test "low-resource sysctl exists and sets swappiness" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/sysctl.d/100-low-resource.conf" 'vm.swappiness = 60'
}

@test "low-resource sysctl increases cache pressure" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/sysctl.d/100-low-resource.conf" 'vm.vfs_cache_pressure = 200'
}

@test "low-resource sysctl disables swap read-ahead" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/sysctl.d/100-low-resource.conf" 'vm.page-cluster = 0'
}

@test "bluetooth is disabled by preset" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system-preset/35-security-desktop.preset" 'disable bluetooth.service'
}
