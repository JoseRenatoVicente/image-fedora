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
    grep -q 'zram-size = min(ram / 2 + 512, 4096)' /etc/systemd/zram-generator.conf
}

@test "low-resource sysctl template is present in image" {
    [ -f /usr/share/image-fedora/low-resource/99-zz-low-resource.conf ]
    grep -q 'vm.vfs_cache_pressure = 200' /usr/share/image-fedora/low-resource/99-zz-low-resource.conf
}

@test "low-resource sysctl template sorts after 99-performance.conf" {
    # sysctl.d aplica em ordem lexical e o último vence; o nome antigo
    # (100-low-resource.conf) ordenava ANTES de 99-performance.conf e o
    # perfil ficava inerte a partir do segundo boot.
    [ ! -e /usr/share/image-fedora/low-resource/100-low-resource.conf ]
    run bash -c "printf '99-performance.conf\n99-zz-low-resource.conf\n' | sort -c"
    [ "$status" -eq 0 ]
}

@test "low-resource sysctl does not shadow zram swappiness" {
    # swappiness=180 (99-performance.conf) é intencional também em low-RAM:
    # swap é zram + tier de recompressão, não disco.
    ! grep -qE '^\s*vm\.swappiness' /usr/share/image-fedora/low-resource/99-zz-low-resource.conf
}

@test "low-resource tuning only activates on constrained hardware" {
    [ -f /usr/lib/systemd/system/low-resource-tuning.service ]
    grep -qE '^ConditionMemory=<=' /usr/lib/systemd/system/low-resource-tuning.service
    systemctl is-enabled low-resource-tuning.service 2>/dev/null | grep -q "^enabled$"
}

@test "low-resource tuning installs the new profile and migrates the old one" {
    grep -q 'install -Dm0644 /usr/share/image-fedora/low-resource/99-zz-low-resource.conf' \
        /usr/lib/systemd/system/low-resource-tuning.service
    grep -q 'rm -f /etc/sysctl.d/100-low-resource.conf' \
        /usr/lib/systemd/system/low-resource-tuning.service
    grep -q 'ConditionPathExists=!/etc/sysctl.d/99-zz-low-resource.conf' \
        /usr/lib/systemd/system/low-resource-tuning.service
}

@test "bluetooth service is disabled by preset" {
    systemctl is-enabled bluetooth.service 2>/dev/null | grep -q "^disabled$"
}

@test "geoclue-demo-agent autostart is hidden" {
    [ -f /etc/xdg/autostart/geoclue-demo-agent.desktop ]
    grep -q '^Hidden=true$' /etc/xdg/autostart/geoclue-demo-agent.desktop
}

@test "cosmic-initial-setup autostart is hidden" {
    # A imagem já pré-configura o COSMIC; o wizard fica residente a sessão
    # inteira (~72 MiB Pss) sem função.
    [ -f /etc/xdg/autostart/com.system76.CosmicInitialSetup.desktop ]
    grep -q '^Hidden=true$' /etc/xdg/autostart/com.system76.CosmicInitialSetup.desktop
}

@test "unused GPU/homed daemons are masked" {
    for unit in switcheroo-control.service systemd-homed.service; do
        [ "$(systemctl is-enabled "$unit" 2>/dev/null)" = "masked" ]
    done
}

@test "VS Code flatpak override seeds native Wayland" {
    grep -q 'ELECTRON_OZONE_PLATFORM_HINT=auto' \
        /etc/skel/.local/share/flatpak/overrides/com.visualstudio.code
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
