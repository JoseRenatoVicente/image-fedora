#!/usr/bin/env bats
# Container tests — run inside the built image
# Tests: required packages, COSMIC packages, unwanted packages, repos, wrappers

setup() {
    load '../helpers/common'
}

# ── Required packages ───────────────────────────────────────────────────────

@test "systemd-oomd-defaults is installed" {
    rpm -q systemd-oomd-defaults
}

@test "fastfetch is installed" {
    rpm -q fastfetch
}

@test "ffmpeg or ffmpeg-free is installed" {
    rpm -q ffmpeg || rpm -q ffmpeg-free
}

@test "firewalld is installed" {
    rpm -q firewalld
}

@test "gamemode is installed" {
    rpm -q gamemode
}

@test "git-credential-libsecret is installed" {
    rpm -q git-credential-libsecret
}

@test "zsh-autosuggestions is installed" {
    rpm -q zsh-autosuggestions
}

@test "zsh-syntax-highlighting is installed" {
    rpm -q zsh-syntax-highlighting
}

@test "kitty is installed" {
    rpm -q kitty
}

@test "lm_sensors is installed" {
    rpm -q lm_sensors
}

@test "neovim is installed" {
    rpm -q neovim
}

@test "nvtop is installed" {
    rpm -q nvtop
}

@test "pam-u2f is installed" {
    rpm -q pam-u2f
}

@test "podman-docker is installed" {
    rpm -q podman-docker
}

@test "tuned is installed" {
    rpm -q tuned
}

@test "fprintd is installed" {
    rpm -q fprintd
}

@test "libfprint is installed" {
    rpm -q libfprint
}

@test "bolt is installed" {
    rpm -q bolt
}

@test "iio-sensor-proxy is installed" {
    rpm -q iio-sensor-proxy
}

@test "thermald is installed" {
    rpm -q thermald
}

@test "irqbalance is installed" {
    rpm -q irqbalance
}

@test "tuned-ppd is installed" {
    rpm -q tuned-ppd
}

@test "alsa-sof-firmware is installed" {
    rpm -q alsa-sof-firmware
}

@test "alsa-ucm is installed" {
    rpm -q alsa-ucm
}

@test "pipewire is installed" {
    rpm -q pipewire
}

@test "wireplumber is installed" {
    rpm -q wireplumber
}

@test "fwupd is installed" {
    rpm -q fwupd
}

@test "libsmbios is installed" {
    rpm -q libsmbios
}

@test "dmidecode is installed" {
    rpm -q dmidecode
}

@test "yubikey-manager is installed" {
    rpm -q yubikey-manager
}

@test "zsh is installed" {
    rpm -q zsh
}

# ── COSMIC packages ──────────────────────────────────────────────────────────

@test "cosmic-session is installed" {
    rpm -q cosmic-session
}

@test "cosmic-comp is installed" {
    rpm -q cosmic-comp
}

@test "cosmic-panel is installed" {
    rpm -q cosmic-panel
}

@test "cosmic-files is installed" {
    rpm -q cosmic-files
}

@test "cosmic-greeter is installed" {
    rpm -q cosmic-greeter
}

@test "greetd is installed" {
    rpm -q greetd
}

# ── Unwanted packages ───────────────────────────────────────────────────────

@test "code (VS Code) is not installed" {
    run rpm -q code
    [ "$status" -ne 0 ]
}

@test "firefox is not installed" {
    run rpm -q firefox
    [ "$status" -ne 0 ]
}

@test "cups is not installed" {
    run rpm -q cups
    [ "$status" -ne 0 ]
}

@test "hplip is not installed" {
    run rpm -q hplip
    [ "$status" -ne 0 ]
}

@test "gutenprint is not installed" {
    run rpm -q gutenprint
    [ "$status" -ne 0 ]
}

@test "orca is not installed" {
    run rpm -q orca
    [ "$status" -ne 0 ]
}

@test "brltty is not installed" {
    run rpm -q brltty
    [ "$status" -ne 0 ]
}

@test "speech-dispatcher is not installed" {
    run rpm -q speech-dispatcher
    [ "$status" -ne 0 ]
}

@test "power-profiles-daemon is not installed" {
    run rpm -q power-profiles-daemon
    [ "$status" -ne 0 ]
}

@test "ModemManager is not installed" {
    run rpm -q ModemManager
    [ "$status" -ne 0 ]
}

@test "xorg-x11-drv-nvidia is not installed" {
    run rpm -q xorg-x11-drv-nvidia
    [ "$status" -ne 0 ]
}

@test "akmod-nvidia is not installed" {
    run rpm -q akmod-nvidia
    [ "$status" -ne 0 ]
}

@test "kmod-nvidia is not installed" {
    run rpm -q kmod-nvidia
    [ "$status" -ne 0 ]
}

@test "nvidia-driver is not installed" {
    run rpm -q nvidia-driver
    [ "$status" -ne 0 ]
}

@test "open-vm-tools-desktop is not installed" {
    run rpm -q open-vm-tools-desktop
    [ "$status" -ne 0 ]
}

@test "virtualbox-guest-additions is not installed" {
    run rpm -q virtualbox-guest-additions
    [ "$status" -ne 0 ]
}

@test "plasma-desktop is not installed" {
    run rpm -q plasma-desktop
    [ "$status" -ne 0 ]
}

@test "plasma-workspace is not installed" {
    run rpm -q plasma-workspace
    [ "$status" -ne 0 ]
}

@test "kwin is not installed" {
    run rpm -q kwin
    [ "$status" -ne 0 ]
}

@test "dolphin is not installed" {
    run rpm -q dolphin
    [ "$status" -ne 0 ]
}

@test "plasma-login-manager is not installed" {
    run rpm -q plasma-login-manager
    [ "$status" -ne 0 ]
}

@test "sddm is not installed" {
    run rpm -q sddm
    [ "$status" -ne 0 ]
}

@test "kde-connect is not installed" {
    run rpm -q kde-connect
    [ "$status" -ne 0 ]
}

@test "akonadi-server is not installed" {
    run rpm -q akonadi-server
    [ "$status" -ne 0 ]
}

@test "mariadb-server is not installed" {
    run rpm -q mariadb-server
    [ "$status" -ne 0 ]
}

# ── VS Code repo ────────────────────────────────────────────────────────────

@test "VS Code repo does not exist" {
    [ ! -e /etc/yum.repos.d/vscode.repo ]
}

# ── rpmfusion removed ───────────────────────────────────────────────────────

@test "rpmfusion repos are removed" {
    run bash -c 'compgen -G "/etc/yum.repos.d/rpmfusion-*.repo"'
    [ "$status" -ne 0 ]
}

# ── DNF wrapper ──────────────────────────────────────────────────────────────

@test "/usr/bin/dnf is the immutable wrapper" {
    grep -q 'rpm-ostree' /usr/bin/dnf
}

@test "/usr/bin/dnf is executable" {
    [ -x /usr/bin/dnf ]
}

# ── wpctl Steam wrapper ─────────────────────────────────────────────────────

@test "wpctl.real exists" {
    [ -x /usr/bin/wpctl.real ]
}

@test "wpctl is executable" {
    [ -x /usr/bin/wpctl ]
}

@test "wpctl is the Steam wrapper" {
    grep -q "steam" /usr/bin/wpctl
}

# ── starship ─────────────────────────────────────────────────────────────────

@test "starship is installed on x86_64" {
    if [[ "$(uname -m)" != "x86_64" ]]; then
        skip "starship not verified on $(uname -m)"
    fi
    [ -x /usr/bin/starship ]
}

@test "fedora-shell-setup does not reference Oh My Zsh/Powerlevel10k" {
    run grep -q 'oh-my-zsh\|powerlevel10k' /usr/libexec/fedora-shell-setup
    [ "$status" -ne 0 ]
}

@test "fedora-shell-setup initializes starship" {
    grep -q 'starship init' /usr/libexec/fedora-shell-setup
}

# ── Shell setup contracts ───────────────────────────────────────────────────

@test "shell setup has sudo-command-line widget" {
    grep -q 'sudo-command-line()' /usr/libexec/fedora-shell-setup
}

@test "shell setup has fj helper" {
    grep -q 'fj()' /usr/libexec/fedora-shell-setup
}

@test "shell setup has fgb helper" {
    grep -q 'fgb()' /usr/libexec/fedora-shell-setup
}

@test "shell setup initializes zoxide" {
    grep -q 'zoxide init zsh' /usr/libexec/fedora-shell-setup
}

@test "shell setup hooks direnv" {
    grep -q 'direnv hook zsh' /usr/libexec/fedora-shell-setup
}

@test "dev setup writes user-scoped guide" {
    grep -q '.local/share/fedora-dev-setup' /usr/libexec/fedora-dev-setup
}

@test "dev setup guides toolbox usage" {
    grep -q 'toolbox create' /usr/libexec/fedora-dev-setup
}
