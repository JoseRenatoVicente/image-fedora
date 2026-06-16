#!/usr/bin/env bats
# Container tests — run inside the built image
# Tests: systemd services, presets, masked units, optional units

setup() {
    load '../helpers/common'
}

# ── Required enabled units ───────────────────────────────────────────────────

@test "podman.socket is enabled" {
    systemctl is-enabled podman.socket 2>/dev/null | grep -q "^enabled$"
}

@test "tuned.service is enabled" {
    systemctl is-enabled tuned.service 2>/dev/null | grep -q "^enabled$"
}

@test "systemd-oomd.service is enabled" {
    systemctl is-enabled systemd-oomd.service 2>/dev/null | grep -q "^enabled$"
}

@test "firewalld.service is enabled" {
    systemctl is-enabled firewalld.service 2>/dev/null | grep -q "^enabled$"
}

@test "chronyd.service is enabled" {
    systemctl is-enabled chronyd.service 2>/dev/null | grep -q "^enabled$"
}

@test "flatpak-nuke-fedora.service is enabled" {
    systemctl is-enabled flatpak-nuke-fedora.service 2>/dev/null | grep -q "^enabled$"
}

@test "flathub-system-setup.service is enabled" {
    systemctl is-enabled flathub-system-setup.service 2>/dev/null | grep -q "^enabled$"
}

@test "plasmalogin.service is enabled" {
    systemctl is-enabled plasmalogin.service 2>/dev/null | grep -q "^enabled$"
}

@test "thermald.service is enabled" {
    systemctl is-enabled thermald.service 2>/dev/null | grep -q "^enabled$"
}

@test "irqbalance.service is enabled" {
    systemctl is-enabled irqbalance.service 2>/dev/null | grep -q "^enabled$"
}

@test "rpm-ostreed-automatic.timer is enabled" {
    systemctl is-enabled rpm-ostreed-automatic.timer 2>/dev/null | grep -q "^enabled$"
}

@test "podman-auto-update.timer is enabled" {
    systemctl is-enabled podman-auto-update.timer 2>/dev/null | grep -q "^enabled$"
}

# ── bolt and fwupd (D-Bus activated: enabled or static) ─────────────────────

@test "bolt.service is enabled or static" {
    systemctl is-enabled bolt.service 2>/dev/null | grep -qE "^(enabled|static)$"
}

@test "fwupd.service is enabled or static" {
    systemctl is-enabled fwupd.service 2>/dev/null | grep -qE "^(enabled|static)$"
}

# ── Masked services (boot speed) ────────────────────────────────────────────

@test "NetworkManager-wait-online.service is masked" {
    [[ "$(readlink /etc/systemd/system/NetworkManager-wait-online.service 2>/dev/null)" == "/dev/null" ]]
}

@test "ModemManager.service is masked" {
    [[ "$(readlink /etc/systemd/system/ModemManager.service 2>/dev/null)" == "/dev/null" ]]
}

@test "plymouth-quit-wait.service is masked" {
    [[ "$(readlink /etc/systemd/system/plymouth-quit-wait.service 2>/dev/null)" == "/dev/null" ]]
}

@test "avahi-daemon.service is masked" {
    [[ "$(readlink /etc/systemd/system/avahi-daemon.service 2>/dev/null)" == "/dev/null" ]]
}

@test "avahi-daemon.socket is masked" {
    [[ "$(readlink /etc/systemd/system/avahi-daemon.socket 2>/dev/null)" == "/dev/null" ]]
}

# ── Dell/Intel laptop support ───────────────────────────────────────────────

@test "fprintd.service unit file exists" {
    systemctl list-unit-files fprintd.service | grep -q fprintd.service
}

@test "iio-sensor-proxy.service unit file exists" {
    systemctl list-unit-files iio-sensor-proxy.service | grep -q iio-sensor-proxy.service
}

@test "tuned.service unit file exists" {
    systemctl list-unit-files tuned.service | grep -q tuned.service
}

@test "power-profiles-daemon.service is not installed" {
    run bash -c "systemctl list-unit-files power-profiles-daemon.service | grep -q power-profiles-daemon.service"
    [ "$status" -ne 0 ]
}

# ── Optional services ───────────────────────────────────────────────────────

@test "flatpak-system-update.timer is enabled if present" {
    if ! systemctl list-unit-files flatpak-system-update.timer | grep -q flatpak-system-update.timer; then
        skip "flatpak-system-update.timer not available on this base"
    fi
    systemctl is-enabled flatpak-system-update.timer 2>/dev/null | grep -q "^enabled$"
}

@test "dconf-update.service is enabled if present" {
    if ! systemctl list-unit-files dconf-update.service | grep -q dconf-update.service; then
        skip "dconf-update.service not available on this base"
    fi
    systemctl is-enabled dconf-update.service 2>/dev/null | grep -q "^enabled$"
}

# ── scx-scheds ───────────────────────────────────────────────────────────────

@test "scx.service is enabled if scx-scheds installed" {
    if ! rpm -q scx-scheds &>/dev/null; then
        skip "scx-scheds not installed"
    fi
    systemctl is-enabled scx.service 2>/dev/null | grep -q "^enabled$"
}

@test "scx scheduler is configured if scx-scheds installed" {
    if ! rpm -q scx-scheds &>/dev/null; then
        skip "scx-scheds not installed"
    fi
    [ -e /etc/default/scx ]
    grep -qE '^SCX_SCHEDULER=scx_' /etc/default/scx
}

# ── keyd ─────────────────────────────────────────────────────────────────────

@test "input-remapper is not present" {
    [ ! -e /usr/bin/input-remapper-service ]
}

@test "input-remapper udev rules are removed" {
    [ ! -e /etc/udev/rules.d/99-input-remapper.rules ]
}

@test "keyd.service is enabled if keyd installed" {
    if ! rpm -q keyd &>/dev/null; then
        skip "keyd not installed"
    fi
    systemctl is-enabled keyd.service 2>/dev/null | grep -q "^enabled$"
}

@test "keyd config exists if keyd installed" {
    if ! rpm -q keyd &>/dev/null; then
        skip "keyd not installed"
    fi
    [ -f /etc/keyd/default.conf ]
}
