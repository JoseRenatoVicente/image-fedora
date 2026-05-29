#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

# ── Trap para garantir limpeza de COPRs mesmo em caso de erro ────────────────
COPRS_ENABLED=()
cleanup_coprs() {
  if [[ ${#COPRS_ENABLED[@]} -gt 0 ]]; then
    for copr in "${COPRS_ENABLED[@]}"; do
      dnf5 -y copr disable "$copr" 2>/dev/null || true
    done
  fi
}
trap cleanup_coprs EXIT

# ── Plugin dnf5-plugins (necessário para copr) ───────────────────────────────
log "Garantindo dnf5-plugins"
dnf5 install -y dnf5-plugins

# ── COPRs ─────────────────────────────────────────────────────────────────────
log "Habilitando COPRs"
dnf5 -y copr enable hazel-bunny/ricing
COPRS_ENABLED+=("hazel-bunny/ricing")

dnf5 -y copr enable matinlotfali/KDE-Rounded-Corners
COPRS_ENABLED+=("matinlotfali/KDE-Rounded-Corners")

dnf5 -y copr enable heroic-games-launcher/heroic-games-launcher
COPRS_ENABLED+=("heroic-games-launcher/heroic-games-launcher")

# ── Repositório VS Code (Microsoft) ──────────────────────────────────────────
log "Adicionando repositório VS Code"
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# ── Instalação de Pacotes ─────────────────────────────────────────────────────
log "Instalando pacotes"
dnf5 install -y --skip-unavailable \
  `# Dev tools` \
  git curl wget unzip tar jq \
  gcc-c++ cmake extra-cmake-modules libplasma-devel \
  code \
  `# Multimídia` \
  ffmpeg \
  gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free gstreamer1-plugins-ugly \
  vlc \
  pipewire-codec-aptx \
  `# Gaming` \
  steam \
  lutris \
  heroic-games-launcher \
  wine winetricks \
  gamemode gamescope \
  `# KDE / Tema Mokka` \
  kvantum qt6ct qt5ct \
  spectacle \
  inter-fonts \
  kwin-effects-forceblur kwin-effects-forceblur-x11 \
  kwin-effect-roundcorners kwin-effect-roundcorners-x11 \
  `# Build deps para Panel Colorizer e assets` \
  rsync

# ── Desabilitar COPRs ─────────────────────────────────────────────────────────
log "Desabilitando COPRs"
cleanup_coprs
trap - EXIT

# ── Assets do tema Mokka ──────────────────────────────────────────────────────
log "Instalando assets do tema Mokka"
bash /ctx/install-assets.sh

# ── Panel Colorizer ───────────────────────────────────────────────────────────
log "Instalando Panel Colorizer"
bash /ctx/panel-colorizer.sh

# ── Rebuild cache de fontes ───────────────────────────────────────────────────
log "Rebuild cache de fontes"
fc-cache -f /usr/share/fonts/

# ── Config KDE defaults via kwriteconfig6 ────────────────────────────────────
# Garante que /etc/skel/.config existe (pode ter sido criado pelo install-assets.sh)
mkdir -p /etc/skel/.config

log "Aplicando overrides de config KDE no skel"

# Ícones
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group Icons --key Theme "Tela-circle-dracula"

# Fonte monospace
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key fixed "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

# Fonte geral
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key font "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

# Fonte menu
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key menuFont "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

# Fonte toolbar
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key toolBarFont "JetBrains Mono,10,-1,5,75,0,0,0,0,0"

# Cursor
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
  --group Mouse --key cursorTheme "catppuccin-mocha-mauve-cursors"

# KWin: desabilita blur padrão, habilita forceblur e rounded corners
kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key blurEnabled "false"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key forceblurEnabled "true"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key kwin4_effect_forceblurEnabled "true"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key roundcornersEnabled "true"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key kwin4_effect_roundcornersEnabled "true"

# ── Serviços do sistema ───────────────────────────────────────────────────────
log "Habilitando serviços"
systemctl enable podman.socket

log "Build concluído."
