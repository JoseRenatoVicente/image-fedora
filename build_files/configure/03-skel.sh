# 03-skel.sh — Skel + first-boot services and COSMIC skel defaults.
# Sourced by build-configure.sh (not executed directly).

# ─── Skel + first-boot services ───────────────────────────────────────────────
echo "::group:: Skel + first-boot services"
mkdir -p /etc/skel/.config

rm -f /etc/skel/.config/autostart/initial-setup.desktop \
      /etc/skel/.config/autostart/initial-setup.sh

# Shell padrão para novos utilizadores: zsh (evita chsh no primeiro login)
sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd

# First-boot user services
mkdir -p /etc/skel/.config/systemd/user/timers.target.wants

# Lib comum dos scripts de primeiro-boot (safe_run + git_clone_pinned).
# Centraliza a verificação de integridade de descargas externas.
install -Dm644 /ctx/configs/fedora-setup-common.sh \
    /usr/libexec/fedora-setup-common.sh

for script in fedora-flatpak-setup fedora-shell-setup fedora-dev-setup fedora-brew-setup fedora-cosmic-layout-setup; do
    install -Dm755 /ctx/configs/"${script}" /usr/libexec/"${script}"
    install -Dm644 /ctx/skel/.config/systemd/user/"${script}".service \
        /etc/skel/.config/systemd/user/"${script}".service
    install -Dm644 /ctx/skel/.config/systemd/user/"${script}".timer \
        /etc/skel/.config/systemd/user/"${script}".timer
    ln -sf ../"${script}".timer \
        /etc/skel/.config/systemd/user/timers.target.wants/"${script}".timer
done

install -Dm644 /ctx/skel/.config/systemd/user/fedora-cosmic-layout-setup.service \
    /usr/lib/systemd/user/fedora-cosmic-layout-setup.service
install -Dm644 /ctx/skel/.config/systemd/user/fedora-cosmic-layout-setup.timer \
    /usr/lib/systemd/user/fedora-cosmic-layout-setup.timer
mkdir -p /etc/systemd/user/timers.target.wants
ln -sf /usr/lib/systemd/user/fedora-cosmic-layout-setup.timer \
    /etc/systemd/user/timers.target.wants/fedora-cosmic-layout-setup.timer

install -Dm644 /ctx/configs/tmpfiles-homebrew.conf \
    /usr/lib/tmpfiles.d/homebrew.conf

setfattr -n user.component -v "skel" \
    /usr/libexec/fedora-setup-common.sh \
    /usr/libexec/fedora-flatpak-setup \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup \
    /usr/libexec/fedora-cosmic-layout-setup
setfattr -n user.update-interval -v "monthly" \
    /usr/libexec/fedora-setup-common.sh \
    /usr/libexec/fedora-flatpak-setup \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup \
    /usr/libexec/fedora-cosmic-layout-setup
echo "::endgroup::"

# ─── COSMIC defaults (skel) — tema Mokka (Catppuccin Mocha Mauve) ─────────────
# Cada chave do cosmic-config é um ficheiro RON separado em
# /etc/skel/.config/cosmic/<componente>/v1/<chave>.
echo "::group:: COSMIC skel"
COSMIC_SKEL="/etc/skel/.config/cosmic"

cosmic_cfg() {
    local comp="$1" key="$2" dir
    dir="${COSMIC_SKEL}/${comp}/v1"
    mkdir -p "$dir"
    cat > "${dir}/${key}"
}

# Modo escuro
cosmic_cfg com.system76.CosmicTheme.Mode is_dark <<< "true"

# Toolkit: fontes JetBrainsMono Nerd Font, ícones Tela, propagar accent às apps GTK
cosmic_cfg com.system76.CosmicTk apply_theme_global <<< "true"
cosmic_cfg com.system76.CosmicTk icon_theme <<< '"Tela-circle-dracula-dark"'
cosmic_cfg com.system76.CosmicTk interface_font <<'RON'
(
    family: "JetBrainsMono Nerd Font",
    weight: Normal,
    stretch: Normal,
    style: Normal,
)
RON
cosmic_cfg com.system76.CosmicTk monospace_font <<'RON'
(
    family: "JetBrainsMono Nerd Font Mono",
    weight: Normal,
    stretch: Normal,
    style: Normal,
)
RON

# Wallpaper Mokka-tree
cosmic_cfg com.system76.CosmicBackground same-on-all <<< "true"
cosmic_cfg com.system76.CosmicBackground all <<'RON'
(
    output: "all",
    source: Path("/usr/share/backgrounds/mokka/Mokka-tree.jpg"),
    filter_by_theme: true,
    rotation_frequency: 300,
    filter_method: Lanczos,
    scaling_mode: Zoom,
    sampling_method: Alphanumeric,
)
RON

# Painel inferior fixo (estilo KDE/Windows)
cosmic_cfg com.system76.CosmicPanel.Panel anchor <<< "Bottom"
cosmic_cfg com.system76.CosmicPanel.Panel anchor_gap <<< "false"
cosmic_cfg com.system76.CosmicPanel.Panel border_radius <<< "0"
cosmic_cfg com.system76.CosmicPanel.Panel margin <<< "0"
cosmic_cfg com.system76.CosmicPanel.Panel opacity <<< "1.0"

# Terminal: fonte monoespaçada + leve transparência (esquema de cores Catppuccin
# Mocha fica empacotado em /usr/share/cosmic-mokka/ para import opcional)
cosmic_cfg com.system76.CosmicTerm font_name <<< '"JetBrainsMono Nerd Font Mono"'
cosmic_cfg com.system76.CosmicTerm font_size <<< "14"
cosmic_cfg com.system76.CosmicTerm opacity <<< "95"

# Atalhos personalizados (estilo Windows):
#   Super+Shift+S → captura de ecrã (abre o cosmic-screenshot com seleção de região)
# Nota: o COSMIC não tem histórico de área de transferência nativo (Super+V exige
# um applet de terceiros — ver README).
cosmic_cfg com.system76.CosmicSettings.Shortcuts custom <<'RON'
{
    (modifiers: [Super, Shift], key: "s"): System(Screenshot),
}
RON
echo "::endgroup::"
