#!/usr/bin/env bats
# Source-level tests: low-resource performance configuration

setup() {
    load '../helpers/common'
}

@test "zram-generator.conf exists and uses zstd" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/systemd/zram-generator.conf" 'compression-algorithm=zstd'
}

@test "zram-generator.conf limits RAM usage" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/systemd/zram-generator.conf" 'zram-size = min(ram / 2 + 512, 4096)'
}

@test "low-resource sysctl template sorts after 99-performance.conf" {
    # sysctl.d aplica em ordem lexical e o último vence; 100-* ordenava ANTES
    # de 99-* ('1' < '9') e o perfil ficava inerte a partir do segundo boot.
    assert_file_exists "${REPO_ROOT}/build_files/overlay/usr/share/image-fedora/low-resource/99-zz-low-resource.conf"
    assert_file_not_exists "${REPO_ROOT}/build_files/overlay/usr/share/image-fedora/low-resource/100-low-resource.conf"
}

@test "low-resource sysctl does not shadow zram swappiness" {
    # swappiness=180 (99-performance.conf) vale também em low-RAM: o swap é
    # zram + tier de recompressão, não disco.
    run grep -E '^\s*vm\.swappiness' \
        "${REPO_ROOT}/build_files/overlay/usr/share/image-fedora/low-resource/99-zz-low-resource.conf"
    [ "$status" -ne 0 ]
}

@test "low-resource sysctl increases cache pressure" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/share/image-fedora/low-resource/99-zz-low-resource.conf" 'vm.vfs_cache_pressure = 200'
}

@test "low-resource sysctl disables swap read-ahead" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/share/image-fedora/low-resource/99-zz-low-resource.conf" 'vm.page-cluster = 0'
}

@test "low-resource tuning is gated behind a RAM condition, not unconditional" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/low-resource-tuning.service" 'ConditionMemory=<=6G'
    assert_file_not_exists "${REPO_ROOT}/build_files/overlay/etc/sysctl.d/100-low-resource.conf"
    assert_file_not_exists "${REPO_ROOT}/build_files/overlay/etc/sysctl.d/99-zz-low-resource.conf"
}

@test "low-resource tuning installs the new profile and migrates the old one" {
    local service="${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/low-resource-tuning.service"
    assert_contains "$service" 'install -Dm0644 /usr/share/image-fedora/low-resource/99-zz-low-resource.conf /etc/sysctl.d/99-zz-low-resource.conf'
    assert_contains "$service" 'rm -f /etc/sysctl.d/100-low-resource.conf'
    assert_contains "$service" 'ConditionPathExists=!/etc/sysctl.d/99-zz-low-resource.conf'
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

@test "cosmic-initial-setup autostart is hidden" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/xdg/autostart/com.system76.CosmicInitialSetup.desktop" 'Hidden=true'
}

@test "unused GPU/homed daemons are masked in 50-services.sh" {
    local script="${REPO_ROOT}/build_files/scripts/configure/50-services.sh"
    assert_contains "$script" 'switcheroo-control.service'
    assert_contains "$script" 'systemd-homed.service'
    assert_contains "$script" 'systemd-homed-activate.service'
}

@test "VS Code flatpak override seeds native Wayland" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/skel/.local/share/flatpak/overrides/com.visualstudio.code" 'ELECTRON_OZONE_PLATFORM_HINT=auto'
}

@test "AMD CPB boost supports both AMD CPU frequency drivers" {
    local service="${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/amd-cpb-boost.service"
    assert_contains "$service" 'AuthenticAMD'
    assert_contains "$service" '/sys/devices/system/cpu/amd_pstate/cpb_boost'
    assert_contains "$service" '/sys/devices/system/cpu/cpufreq/boost'
}

@test "zram tiered recompression helper registers a dense secondary algorithm" {
    local helper="${REPO_ROOT}/build_files/overlay/usr/libexec/zram-recompress"
    assert_contains "$helper" 'recomp_algorithm'
    assert_contains "$helper" 'type=idle'
    assert_contains "$helper" 'algo=zstd level=15 priority=1'
}

@test "zram-recompress runs on a periodic timer, not unconditionally at boot" {
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/zram-recompress.timer" 'OnUnitActiveSec='
    assert_contains "${REPO_ROOT}/build_files/overlay/usr/lib/systemd/system/zram-recompress.service" 'ConditionPathExists=/sys/block/zram0/recompress'
}

@test "user.slice enables proactive MemoryHigh reclaim before oomd kills" {
    assert_contains "${REPO_ROOT}/build_files/overlay/etc/systemd/system/user.slice.d/15-memory-high.conf" 'MemoryHigh='
}

@test "orphaned session helpers are masked to /dev/null" {
    for unit in mpris-proxy.service obex.service; do
        local path="${REPO_ROOT}/build_files/overlay/etc/systemd/user/${unit}"
        [ -L "$path" ]
        [ "$(readlink "$path")" = "/dev/null" ]
    done
}
