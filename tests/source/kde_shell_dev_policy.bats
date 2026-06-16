#!/usr/bin/env bats
# Source-level tests: KDE Plasma desktop, shell, and dev environment policy

setup() {
    load '../helpers/common'
    configure="${REPO_ROOT}/build_files/build-configure.sh"
    packages="${REPO_ROOT}/build_files/build-packages.sh"
    runtime_tests="${REPO_ROOT}/build_files/shared/tests.sh"
    shell_setup="${REPO_ROOT}/build_files/configs/fedora-shell-setup"
    dev_setup="${REPO_ROOT}/build_files/configs/fedora-dev-setup"
}

# ── KDE theme setup ──────────────────────────────────────────────────────────

@test "configure sets Mokka look-and-feel" {
    assert_contains "$configure" 'Mokka'
}

@test "configure installs SDDM theme" {
    assert_contains "$configure" 'plasmalogin.conf.d'
}

@test "configure sets kwin-vm-compat" {
    assert_contains "$configure" 'kwin-vm-compat'
}

@test "configure installs plasma appletsrc" {
    assert_contains "$configure" 'plasma-org.kde.plasma.desktop-appletsrc'
}

@test "configure sets kvantum widget style" {
    assert_contains "$configure" 'kvantum'
}

@test "configure sets Catppuccin cursor theme" {
    assert_contains "$configure" 'catppuccin-mocha-mauve-cursors'
}

# ── KDE packages present ─────────────────────────────────────────────────────

@test "plasma-desktop is in packages" {
    assert_contains "$packages" 'plasma-desktop'
}

@test "kwin is in packages" {
    assert_contains "$packages" 'kwin'
}

@test "konsole is in packages" {
    assert_contains "$packages" 'konsole'
}

@test "dolphin is in packages" {
    assert_contains "$packages" 'dolphin'
}

# ── COSMIC packages absent ───────────────────────────────────────────────────

@test "cosmic-session is not in packages" {
    assert_not_contains "$packages" 'cosmic-session'
}

@test "cosmic-comp is not in packages" {
    assert_not_contains "$packages" 'cosmic-comp'
}

@test "cosmic-greeter is not in packages" {
    assert_not_contains "$packages" 'cosmic-greeter'
}

# ── Shell setup (starship, zoxide, direnv) ───────────────────────────────────

@test "shell setup has marker block" {
    assert_contains "$shell_setup" 'MARKER="# >>> fedora-shell-setup >>>"'
}

@test "shell setup initializes starship" {
    assert_contains "$shell_setup" 'starship init zsh'
}

@test "shell setup initializes zoxide" {
    assert_contains "$shell_setup" 'zoxide init zsh'
}

@test "shell setup hooks direnv" {
    assert_contains "$shell_setup" 'direnv hook zsh'
}

@test "shell setup has sudo-command-line widget" {
    assert_contains "$shell_setup" 'sudo-command-line()'
}

@test "shell setup has fj helper" {
    assert_contains "$shell_setup" 'fj()'
}

@test "shell setup has fgb helper" {
    assert_contains "$shell_setup" 'fgb()'
}

@test "shell setup enables zsh-autosuggestions" {
    assert_contains "$shell_setup" 'zsh-autosuggestions'
}

@test "shell setup enables zsh-syntax-highlighting" {
    assert_contains "$shell_setup" 'zsh-syntax-highlighting'
}

@test "shell setup does not use oh-my-zsh" {
    assert_not_contains "$shell_setup" 'oh-my-zsh'
}

@test "shell setup does not use powerlevel10k" {
    assert_not_contains "$shell_setup" 'powerlevel10k'
}

# ── Dev setup (distrobox, toolbox) ───────────────────────────────────────────

@test "dev setup creates distrobox" {
    assert_contains "$dev_setup" 'distrobox create'
}

@test "dev setup creates toolbox" {
    assert_contains "$dev_setup" 'toolbox create'
}

@test "dev setup writes user-scoped guide" {
    assert_contains "$dev_setup" '.local/share/fedora-dev-setup'
}

@test "dev setup installs opencode" {
    assert_contains "$dev_setup" 'opencode-ai@${OPENCODE_NPM_VERSION}'
}

# ── Heavy packages excluded from base ───────────────────────────────────────

@test "terraform not in base packages" {
    run grep -Eq '^[[:space:]]*terraform([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

@test "kubectl not in base packages" {
    run grep -Eq '^[[:space:]]*kubectl([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

@test "helm not in base packages" {
    run grep -Eq '^[[:space:]]*helm([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

@test "k9s not in base packages" {
    run grep -Eq '^[[:space:]]*k9s([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

@test "nodejs not in base packages" {
    run grep -Eq '^[[:space:]]*nodejs([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

@test "golang not in base packages" {
    run grep -Eq '^[[:space:]]*golang([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

@test "rust not in base packages" {
    run grep -Eq '^[[:space:]]*rust([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

@test "cargo not in base packages" {
    run grep -Eq '^[[:space:]]*cargo([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

@test "java-latest-openjdk not in base packages" {
    run grep -Eq '^[[:space:]]*java-latest-openjdk([[:space:]]|$)' "$packages"
    [ "$status" -ne 0 ]
}

# ── Justfile validate-source references BATS ─────────────────────────────────

@test "Justfile validate-source runs bats tests" {
    assert_contains "${REPO_ROOT}/just/testing.just" 'bats tests/source/'
}
