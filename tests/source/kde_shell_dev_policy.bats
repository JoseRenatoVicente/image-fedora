#!/usr/bin/env bats
# Source-level tests: KDE Plasma desktop, shell, and dev environment policy
# shellcheck disable=SC2016  # asserts comparam strings literais com ${...}

setup() {
    load '../helpers/common'
    configure_dir="${REPO_ROOT}/build_files/scripts/configure"
    packages="${REPO_ROOT}/build_files/scripts/shared/package-lists.sh"
    shell_setup="${REPO_ROOT}/build_files/overlay/usr/libexec/fedora-shell-setup"
    dev_setup="${REPO_ROOT}/build_files/overlay/usr/libexec/fedora-dev-setup"
}

# ── KDE theme setup ──────────────────────────────────────────────────────────

@test "configure sets Mokka look-and-feel" {
    assert_tree_contains "$configure_dir" 'Mokka'
}

@test "configure installs SDDM theme" {
    assert_tree_contains "$configure_dir" 'plasmalogin.conf.d'
}

@test "configure sets kwin-vm-compat" {
    assert_tree_contains "$configure_dir" 'kwin-vm-compat'
}

@test "configure installs plasma appletsrc" {
    assert_tree_contains "$configure_dir" 'plasma-org.kde.plasma.desktop-appletsrc'
}

@test "configure sets kvantum widget style" {
    assert_tree_contains "$configure_dir" 'kvantum'
}

@test "configure sets Catppuccin cursor theme" {
    assert_tree_contains "$configure_dir" 'catppuccin-mocha-mauve-cursors'
}

@test "asset install keeps configured Tela icon theme" {
    assert_tree_contains "$configure_dir" 'Tela-circle-dracula-dark'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/install-assets.sh" '/usr/share/icons/Tela-circle-dracula-dark'
}

@test "configure keeps host KDE theme family" {
    assert_tree_contains "$configure_dir" 'LookAndFeelPackage "Mokka"'
    assert_tree_contains "$configure_dir" 'widgetStyle "kvantum-dark"'
    assert_tree_contains "$configure_dir" '__aurorae__svg__CatppuccinMocha-Classic'
}

@test "configure keeps window blur and rounded-corner effects enabled" {
    assert_tree_contains "$configure_dir" '--group Plugins --key blurEnabled "true"'
    assert_tree_contains "$configure_dir" '--group Plugins --key roundcornersEnabled "true"'
    assert_tree_contains "$configure_dir" '--group Plugins --key kwin4_effect_roundcornersEnabled "true"'
    assert_tree_contains "$configure_dir" '--group "org.kde.kdecoration2" --key BorderSize "None"'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" '--group Plugins --key blurEnabled "false"'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" '--group Plugins --key roundcornersEnabled "false"'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" '--group Plugins --key kwin4_effect_roundcornersEnabled "false"'
}

@test "configure does not disable Kvantum Mokka transparency system-wide" {
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" 'translucent_windows=false'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" 'blurring=false'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" 'composite=false'
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
