#!/usr/bin/env bats
# Source-level tests: Dell/Intel hardware support policy

setup() {
    load '../helpers/common'
    packages="${REPO_ROOT}/build_files/build-packages.sh"
    configure="${REPO_ROOT}/build_files/build-configure.sh"
    runtime_tests="${REPO_ROOT}/build_files/shared/tests.sh"
    preset="${REPO_ROOT}/build_files/usr/lib/systemd/system-preset/35-security-desktop.preset"
}

# ── Dell/Intel required packages ─────────────────────────────────────────────

@test "packages include fprintd" {
    assert_contains "$packages" 'fprintd'
}

@test "packages include libfprint" {
    assert_contains "$packages" 'libfprint'
}

@test "packages include bolt" {
    assert_contains "$packages" 'bolt'
}

@test "packages include iio-sensor-proxy" {
    assert_contains "$packages" 'iio-sensor-proxy'
}

@test "packages include thermald" {
    assert_contains "$packages" 'thermald'
}

@test "packages include irqbalance" {
    assert_contains "$packages" 'irqbalance'
}

@test "packages include tuned-ppd" {
    assert_contains "$packages" 'tuned-ppd'
}

@test "packages include alsa-sof-firmware" {
    assert_contains "$packages" 'alsa-sof-firmware'
}

@test "packages include fwupd" {
    assert_contains "$packages" 'fwupd'
}

@test "packages include libsmbios" {
    assert_contains "$packages" 'libsmbios'
}

@test "packages include dmidecode" {
    assert_contains "$packages" 'dmidecode'
}

# ── Exclusions ───────────────────────────────────────────────────────────────

@test "power-profiles-daemon is excluded from packages" {
    assert_contains "$packages" '--exclude=power-profiles-daemon'
}

@test "nvidia-gpu-firmware is excluded from packages" {
    assert_contains "$packages" '--exclude=nvidia-gpu-firmware'
}

@test "xorg-x11-drv-nvidia is excluded from packages" {
    assert_contains "$packages" '--exclude=xorg-x11-drv-nvidia'
}

@test "runtime tests check for power-profiles-daemon" {
    assert_contains "$runtime_tests" 'power-profiles-daemon'
}

@test "runtime tests check for nvidia-gpu-firmware" {
    assert_contains "$runtime_tests" 'nvidia-gpu-firmware'
}

# ── ModemManager ─────────────────────────────────────────────────────────────
# Já não é excluído dos pacotes — é instalado mas desativado via preset.

@test "preset disables ModemManager.service" {
    assert_contains "$preset" 'disable ModemManager.service'
}

# ── Thunderbolt/USB4 ────────────────────────────────────────────────────────
# Política de hardening: thunderbolt é omitido do initramfs (superfície DMA).

@test "Thunderbolt is omitted from initramfs" {
    assert_file_exists "${REPO_ROOT}/build_files/etc/dracut.conf.d/99-omit-thunderbolt.conf"
}

@test "thunderbolt omit config drops the thunderbolt driver" {
    assert_contains "${REPO_ROOT}/build_files/etc/dracut.conf.d/99-omit-thunderbolt.conf" 'thunderbolt'
}

# ── Service presets ──────────────────────────────────────────────────────────

@test "preset enables bolt.service" {
    assert_contains "$preset" 'enable bolt.service'
}

@test "preset enables thermald.service" {
    assert_contains "$preset" 'enable thermald.service'
}

@test "preset enables irqbalance.service" {
    assert_contains "$preset" 'enable irqbalance.service'
}

@test "preset enables fwupd.service" {
    assert_contains "$preset" 'enable fwupd.service'
}

# ── Tuned profile ────────────────────────────────────────────────────────────

@test "configure sets tuned active_profile to balanced" {
    assert_contains "$configure" 'echo "balanced" > /etc/tuned/active_profile'
}

@test "runtime tests validate tuned profile" {
    assert_contains "$runtime_tests" 'perfil tuned'
}
