#!/usr/bin/env bash
set -euo pipefail

repo_root=$(dirname "$(dirname "$0")")
failed=0

fail() {
    echo "FAIL: $*" >&2
    failed=1
}

assert_contains() {
    local file=$1
    local pattern=$2

    if ! grep -Fq -- "$pattern" "$file"; then
        fail "expected '$pattern' in $file"
    fi
}

assert_not_contains() {
    local file=$1
    local pattern=$2

    if grep -Fq -- "$pattern" "$file"; then
        fail "unexpected '$pattern' in $file"
    fi
}

packages="${repo_root}/build_files/build-packages.sh"
configure="${repo_root}/build_files/build-configure.sh"
runtime_tests="${repo_root}/build_files/shared/tests.sh"
preset="${repo_root}/build_files/configs/systemd-preset-desktop.preset"

for pkg in fprintd libfprint bolt iio-sensor-proxy thermald irqbalance tuned-ppd alsa-sof-firmware fwupd libsmbios dmidecode; do
    assert_contains "$packages" "$pkg"
done

assert_contains "$packages" '--exclude=power-profiles-daemon'
assert_contains "$packages" '--exclude=nvidia-gpu-firmware'
assert_contains "$packages" '--exclude=xorg-x11-drv-nvidia'
assert_contains "$runtime_tests" 'power-profiles-daemon'
assert_contains "$runtime_tests" 'nvidia-gpu-firmware'

assert_contains "$packages" '--exclude=ModemManager'
assert_contains "$runtime_tests" 'ModemManager'
assert_contains "$configure" 'ModemManager.service'
assert_contains "$preset" 'disable ModemManager.service'

if [[ -e "${repo_root}/build_files/configs/dracut-omit-thunderbolt.conf" ]]; then
    fail "Thunderbolt/USB4 must not be omitted from initramfs"
fi
assert_not_contains "$configure" 'dracut-omit-thunderbolt.conf'
assert_not_contains "$runtime_tests" '/etc/dracut.conf.d/99-omit-thunderbolt.conf'

assert_contains "$preset" 'enable bolt.service'
assert_contains "$preset" 'enable thermald.service'
assert_contains "$preset" 'enable irqbalance.service'
assert_contains "$preset" 'enable fwupd.service'
assert_contains "$configure" 'systemctl preset bolt.service thermald.service irqbalance.service tuned.service fwupd.service'
assert_contains "$configure" 'echo "balanced" > /etc/tuned/active_profile'
assert_contains "$runtime_tests" 'perfil tuned'

if [[ $failed -ne 0 ]]; then
    exit 1
fi

echo "ok: Dell/Intel policy checks passed"
