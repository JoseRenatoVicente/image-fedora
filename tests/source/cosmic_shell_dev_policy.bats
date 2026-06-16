#!/usr/bin/env bats
# Source-level tests: COSMIC desktop, shell, and dev environment policy

setup() {
    load '../helpers/common'
    configure="${REPO_ROOT}/build_files/configure/03-skel.sh"
    packages="${REPO_ROOT}/build_files/build-packages.sh"
    runtime_tests="${REPO_ROOT}/build_files/shared/tests.sh"
    shell_setup="${REPO_ROOT}/build_files/configs/fedora-shell-setup"
    dev_setup="${REPO_ROOT}/build_files/configs/fedora-dev-setup"
    cosmic_layout="${REPO_ROOT}/build_files/configs/fedora-cosmic-layout-setup"
}

# ── COSMIC layout ────────────────────────────────────────────────────────────

@test "configure references fedora-cosmic-layout-setup" {
    assert_contains "$configure" 'fedora-cosmic-layout-setup'
}

@test "configure installs cosmic-layout-setup systemd service" {
    assert_contains "$configure" '/usr/lib/systemd/user/fedora-cosmic-layout-setup.service'
}

@test "configure enables cosmic-layout-setup timer" {
    assert_contains "$configure" '/etc/systemd/user/timers.target.wants/fedora-cosmic-layout-setup.timer'
}

@test "runtime tests check for cosmic-layout-setup" {
    assert_contains "$runtime_tests" 'fedora-cosmic-layout-setup'
}

@test "cosmic layout script has layout_version" {
    assert_contains "$cosmic_layout" 'layout_version='
}

@test "cosmic layout script references version file" {
    assert_contains "$cosmic_layout" 'fedora-cosmic-layout.version'
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
