#!/usr/bin/env bats
# Source-level tests: KDE Plasma desktop, shell, and dev environment policy
# shellcheck disable=SC2016  # asserts comparam strings literais com ${...}

setup() {
    load '../helpers/common'
    configure="${REPO_ROOT}/build_files/build-configure.sh"
    packages="${REPO_ROOT}/build_files/build-packages.sh"
    shell_setup="${REPO_ROOT}/build_files/usr/libexec/fedora-shell-setup"
    dev_setup="${REPO_ROOT}/build_files/usr/libexec/fedora-dev-setup"
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

# ── Shell setup (Oh My Zsh + Powerlevel10k + NVM) ────────────────────────────

@test "shell setup installs Oh My Zsh" {
    assert_contains "$shell_setup" 'ohmyzsh/ohmyzsh'
}

@test "shell setup installs Powerlevel10k theme" {
    assert_contains "$shell_setup" 'powerlevel10k'
}

@test "shell setup installs zsh-autosuggestions" {
    assert_contains "$shell_setup" 'zsh-autosuggestions'
}

@test "shell setup installs zsh-syntax-highlighting" {
    assert_contains "$shell_setup" 'zsh-syntax-highlighting'
}

@test "shell setup installs zsh-completions" {
    assert_contains "$shell_setup" 'zsh-completions'
}

@test "shell setup configures NVM" {
    assert_contains "$shell_setup" 'NVM_DIR'
}

@test "shell setup aliases docker to podman" {
    assert_contains "$shell_setup" "alias docker='podman'"
}

@test "shell setup verifies downloads by sha256 before running" {
    assert_contains "$shell_setup" 'sha256sum'
}

# ── Dev setup (NVM/Node, pnpm, opencode, lazydocker) ─────────────────────────

@test "dev setup installs Node.js LTS via nvm" {
    assert_contains "$dev_setup" 'nvm install --lts'
}

@test "dev setup installs pnpm globally" {
    assert_contains "$dev_setup" 'npm install -g pnpm'
}

@test "dev setup installs opencode" {
    assert_contains "$dev_setup" 'opencode-ai@${OPENCODE_NPM_VERSION}'
}

@test "dev setup installs lazydocker" {
    assert_contains "$dev_setup" 'lazydocker'
}

@test "dev setup verifies downloads by sha256 before running" {
    assert_contains "$dev_setup" 'sha256sum'
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
