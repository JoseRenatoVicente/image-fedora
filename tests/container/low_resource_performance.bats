#!/usr/bin/env bats
# Container tests: low-resource performance runtime configuration

setup() {
    load '../helpers/common'
}

@test "zram-generator package is installed" {
    rpm -q zram-generator
}

@test "zram-generator.conf is present in image" {
    [ -f /etc/systemd/zram-generator.conf ]
    grep -q 'compression-algorithm=zstd' /etc/systemd/zram-generator.conf
    grep -q 'zram-size = min(ram / 4 + 1024, 4096)' /etc/systemd/zram-generator.conf
}

@test "low-resource sysctl template is present in image" {
    [ -f /usr/share/image-fedora/low-resource/100-low-resource.conf ]
    grep -q 'vm.swappiness = 60' /usr/share/image-fedora/low-resource/100-low-resource.conf
}

@test "low-resource tuning only activates on constrained hardware" {
    [ -f /usr/lib/systemd/system/low-resource-tuning.service ]
    grep -qE '^ConditionMemory=<=' /usr/lib/systemd/system/low-resource-tuning.service
    systemctl is-enabled low-resource-tuning.service 2>/dev/null | grep -q "^enabled$"
}

@test "bluetooth service is disabled by preset" {
    systemctl is-enabled bluetooth.service 2>/dev/null | grep -q "^disabled$"
}

@test "geoclue-demo-agent autostart is hidden" {
    [ -f /etc/xdg/autostart/geoclue-demo-agent.desktop ]
    grep -q '^Hidden=true$' /etc/xdg/autostart/geoclue-demo-agent.desktop
}

@test "zram tiered recompression helper is present and executable" {
    [ -x /usr/libexec/zram-recompress ]
    grep -q 'recomp_algorithm' /usr/libexec/zram-recompress
    grep -q 'type=idle' /usr/libexec/zram-recompress
}

@test "zram-recompress timer is enabled" {
    systemctl is-enabled zram-recompress.timer 2>/dev/null | grep -q "^enabled$"
}

@test "user.slice has proactive MemoryHigh reclaim" {
    [ -f /etc/systemd/system/user.slice.d/15-memory-high.conf ]
    grep -q '^MemoryHigh=' /etc/systemd/system/user.slice.d/15-memory-high.conf
}

@test "orphaned session helpers are masked" {
    for unit in mpris-proxy.service obex.service; do
        [ -L "/etc/systemd/user/${unit}" ]
        [ "$(readlink "/etc/systemd/user/${unit}")" = "/dev/null" ]
    done
}
