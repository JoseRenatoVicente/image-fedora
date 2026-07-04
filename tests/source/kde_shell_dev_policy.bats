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

@test "skel keeps Breeze widget style with KvDark fallback" {
    local kdeglobals="${REPO_ROOT}/build_files/overlay/etc/skel/.config/kdeglobals"
    local kvantum="${REPO_ROOT}/build_files/overlay/etc/skel/.config/Kvantum/kvantum.kvconfig"
    assert_contains "$kdeglobals" 'widgetStyle=Breeze'
    assert_contains "$kvantum" 'theme=KvDark'
}

@test "configure sets Catppuccin cursor theme" {
    assert_tree_contains "$configure_dir" 'catppuccin-mocha-mauve-cursors'
}

@test "asset install keeps configured Tela icon theme" {
    assert_tree_contains "$configure_dir" 'Tela-circle-dracula-dark'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/install-assets.sh" '/usr/share/icons/Tela-circle-dracula-dark'
}

@test "configure restores local skel after upstream Mokka import" {
    local skel_configure="${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh"
    assert_contains "$skel_configure" '/ctx/overlay/etc/skel/.config/kdeglobals'
    assert_contains "$skel_configure" '/ctx/overlay/etc/skel/.config/kwinrc'
    assert_contains "$skel_configure" '/ctx/overlay/etc/skel/.config/breezerc'
    assert_contains "$skel_configure" '/ctx/overlay/etc/skel/.config/Kvantum/kvantum.kvconfig'
    assert_contains "$skel_configure" '/ctx/overlay/etc/skel/.config/kscreenlockerrc'
    assert_contains "$skel_configure" '/ctx/overlay/etc/skel/.config/gtk-3.0/settings.ini'
    assert_contains "$skel_configure" '/ctx/overlay/etc/skel/.config/gtk-4.0/settings.ini'
}

@test "configure keeps host KDE theme family" {
    local kdeglobals="${REPO_ROOT}/build_files/overlay/etc/skel/.config/kdeglobals"
    assert_contains "$kdeglobals" 'LookAndFeelPackage=Mokka'
    assert_contains "$kdeglobals" 'widgetStyle=Breeze'
}

@test "skel keeps opaque decoration with buttons on the right" {
    local kwinrc="${REPO_ROOT}/build_files/overlay/etc/skel/.config/kwinrc"
    local breezerc="${REPO_ROOT}/build_files/overlay/etc/skel/.config/breezerc"
    assert_contains "$kwinrc" 'blurEnabled=false'
    assert_contains "$kwinrc" 'roundcornersEnabled=false'
    assert_contains "$kwinrc" 'kwin4_effect_roundcornersEnabled=false'
    assert_contains "$kwinrc" 'shapeCornersEnabled=false'
    assert_contains "$kwinrc" 'shapecornersEnabled=false'
    assert_contains "$kwinrc" 'OutlineThickness=0'
    assert_contains "$kwinrc" 'SecondOutlineThickness=0'
    assert_contains "$kwinrc" 'BorderSize=None'
    assert_contains "$kwinrc" 'ButtonsOnLeft='
    assert_contains "$kwinrc" 'ButtonsOnRight=IAX'
    assert_contains "$kwinrc" 'library=org.kde.breeze'
    assert_contains "$kwinrc" 'theme=Breeze'
    assert_contains "$breezerc" 'OutlineEnabled=false'
    assert_contains "$breezerc" 'OutlineIntensity=OutlineOff'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" '--group Plugins --key blurEnabled "false"'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" '--group Plugins --key roundcornersEnabled "false"'
    assert_not_contains "${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh" '--group Plugins --key kwin4_effect_roundcornersEnabled "false"'
}

@test "configure disables Mokka adaptive transparency" {
    local skel_configure="${REPO_ROOT}/build_files/scripts/configure/40-skel-kde.sh"
    assert_contains "$skel_configure" '--group AdaptiveTransparency --key enabled "false"'
    assert_contains "$skel_configure" '--group BlurBehindEffect --key enabled "true"'
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
