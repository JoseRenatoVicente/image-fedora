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
