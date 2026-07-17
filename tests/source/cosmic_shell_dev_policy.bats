#!/usr/bin/env bats
# Source-level tests: COSMIC desktop, shell, and dev environment policy
# shellcheck disable=SC2016  # asserts comparam strings literais com ${...}

setup() {
    load '../helpers/common'
    configure_dir="${REPO_ROOT}/build_files/scripts/configure"
    packages="${REPO_ROOT}/build_files/scripts/shared/package-lists.sh"
    shell_setup="${REPO_ROOT}/build_files/overlay/usr/libexec/fedora-shell-setup"
    dev_setup="${REPO_ROOT}/build_files/overlay/usr/libexec/fedora-dev-setup"
    install_assets="${REPO_ROOT}/build_files/scripts/install-assets.sh"
}

# ── COSMIC theme setup ───────────────────────────────────────────────────────

@test "install-assets installs the Catppuccin COSMIC theme" {
    assert_contains "$install_assets" '_install_catppuccin_cosmic'
    assert_contains "$install_assets" 'CosmicTheme.Dark.Builder'
}

@test "cosmic-theme-derive.py decomposes Builder and Theme system-wide defaults" {
    local derive="${REPO_ROOT}/build_files/assets/cosmic-theme-derive.py"
    assert_contains "$derive" 'BUILDER_DIR = "/usr/share/cosmic/com.system76.CosmicTheme.Dark.Builder/v1"'
    assert_contains "$derive" 'THEME_DIR = "/usr/share/cosmic/com.system76.CosmicTheme.Dark/v1"'
}

@test "assets manifest pins catppuccin/cosmic-desktop by commit" {
    assert_contains "${REPO_ROOT}/build_files/assets/assets-manifest.sh" 'CATPPUCCIN_COSMIC_COMMIT='
    assert_contains "${REPO_ROOT}/build_files/assets/assets-manifest.sh" 'catppuccin-mocha-mauve+round.ron'
}

@test "configure sets Catppuccin cursor theme" {
    assert_tree_contains "$configure_dir" 'catppuccin-mocha-mauve-cursors'
}

@test "asset install keeps configured Tela icon theme" {
    assert_tree_contains "$configure_dir" 'Tela-circle-dracula-dark'
    assert_not_contains "$install_assets" '/usr/share/icons/Tela-circle-dracula-dark'
}

@test "40-skel-cosmic sets default shell to zsh" {
    local skel_configure="${REPO_ROOT}/build_files/scripts/configure/40-skel-cosmic.sh"
    assert_contains "$skel_configure" 's|^SHELL=.*|SHELL=/bin/zsh|'
}

@test "GTK skel still points at an installed Catppuccin theme" {
    local gtk3="${REPO_ROOT}/build_files/overlay/etc/skel/.config/gtk-3.0/settings.ini"
    assert_contains "$gtk3" 'gtk-theme-name='
}

# ── Regressão: KDE não deve reaparecer ───────────────────────────────────────

@test "panel-colorizer.sh does not exist" {
    assert_file_not_exists "${REPO_ROOT}/build_files/scripts/panel-colorizer.sh"
}

@test "40-skel-kde.sh does not exist" {
    assert_file_not_exists "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh"
}

@test "20-plasmalogin.sh does not exist" {
    assert_file_not_exists "${REPO_ROOT}/build_files/scripts/configure/20-plasmalogin.sh"
}

# ── COSMIC packages present ──────────────────────────────────────────────────

@test "cosmic-session is in COSMIC_REQUIRED" {
    assert_contains "$packages" 'cosmic-session'
}

@test "cosmic-comp is in COSMIC_REQUIRED" {
    assert_contains "$packages" 'cosmic-comp'
}

@test "cosmic-greeter is in COSMIC_REQUIRED" {
    assert_contains "$packages" 'cosmic-greeter'
}

# ── KDE packages absent from INSTALL_PACKAGES (present only as UNWANTED_PACKAGES
#    regression guards — see package_sync.bats for that consistency check) ────

@test "plasma-desktop is not in INSTALL_PACKAGES" {
    run bash -c "source '$packages'; [[ \" \${INSTALL_PACKAGES[*]} \" =~ [[:space:]]plasma-desktop([[:space:]]|\$) ]]"
    [ "$status" -ne 0 ]
}

@test "kwin is not in INSTALL_PACKAGES" {
    run bash -c "source '$packages'; [[ \" \${INSTALL_PACKAGES[*]} \" =~ [[:space:]]kwin([[:space:]]|\$) ]]"
    [ "$status" -ne 0 ]
}

@test "dolphin is not in INSTALL_PACKAGES" {
    run bash -c "source '$packages'; [[ \" \${INSTALL_PACKAGES[*]} \" =~ [[:space:]]dolphin([[:space:]]|\$) ]]"
    [ "$status" -ne 0 ]
}

# ── Shell setup (starship + zoxide + direnv + NVM) ───────────────────────────

@test "shell setup initializes starship prompt" {
    assert_contains "$shell_setup" 'starship init zsh'
}

@test "shell setup does not use Oh My Zsh/Powerlevel10k" {
    assert_not_contains "$shell_setup" 'oh-my-zsh'
    assert_not_contains "$shell_setup" 'powerlevel10k'
}

@test "shell setup sources zsh-autosuggestions" {
    assert_contains "$shell_setup" 'zsh-autosuggestions'
}

@test "shell setup sources zsh-syntax-highlighting" {
    assert_contains "$shell_setup" 'zsh-syntax-highlighting'
}

@test "shell setup initializes zoxide" {
    assert_contains "$shell_setup" 'zoxide init zsh'
}

@test "shell setup hooks direnv" {
    assert_contains "$shell_setup" 'direnv hook zsh'
}

@test "shell setup configures NVM" {
    assert_contains "$shell_setup" 'NVM_DIR'
}

@test "shell setup aliases docker to podman" {
    assert_contains "$shell_setup" "alias docker='podman'"
}

# ── Dev setup (NVM/Node, pnpm, opencode, lazydocker) ─────────────────────────

@test "dev setup installs Node.js LTS via nvm" {
    assert_contains "$dev_setup" 'nvm install --lts'
}

@test "dev setup does not call nvm use with an unresolved LTS alias" {
    assert_not_contains "$dev_setup" 'nvm use --lts'
    assert_contains "$dev_setup" "nvm alias default 'lts/*'"
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
    run bash -c "source '$packages'; [[ ! \" \\${INSTALL_PACKAGES[*]} \" =~ [[:space:]]nodejs([[:space:]]|$) ]]"
    [ "$status" -eq 0 ]
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
