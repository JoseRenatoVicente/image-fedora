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
    grep -q 'compression-algorithm = zstd' /etc/systemd/zram-generator.conf
}

@test "low-resource sysctl is present in image" {
    [ -f /etc/sysctl.d/100-low-resource.conf ]
    grep -q 'vm.swappiness = 60' /etc/sysctl.d/100-low-resource.conf
}

@test "bluetooth service is disabled by preset" {
    systemctl is-enabled bluetooth.service 2>/dev/null | grep -q "^disabled$"
}
