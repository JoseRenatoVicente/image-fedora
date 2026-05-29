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
dnf5 -y copr enable hazel-bunny/ricing || true
COPRS_ENABLED+=("hazel-bunny/ricing")

dnf5 -y copr enable matinlotfali/KDE-Rounded-Corners || true
COPRS_ENABLED+=("matinlotfali/KDE-Rounded-Corners")

# heroic-games-launcher COPR não suporta Fedora 44+; instalado via Flatpak no setup-user.sh

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

# ── Repositório Google Chrome ─────────────────────────────────────────────────
log "Adicionando repositório Google Chrome"
cat > /etc/yum.repos.d/google-chrome.repo << 'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
rpm --import https://dl.google.com/linux/linux_signing_key.pub

# ── Remover pacotes indesejados ───────────────────────────────────────────────
log "Removendo pacotes indesejados"
dnf5 remove -y --skip-unavailable \
  mediawriter \
  ptyxis \
  libreoffice-core \
  gnome-terminal \
  gnome-tour \
  gnome-weather \
  cheese \
  rhythmbox \
  simple-scan \
  snapshot \
  || true

# ── Instalação de Pacotes ─────────────────────────────────────────────────────
log "Instalando pacotes"
dnf5 install -y --skip-unavailable \
  `# Dev tools` \
  git curl wget unzip tar jq make gettext \
  gcc-c++ cmake extra-cmake-modules libplasma-devel \
  code \
  `# CLI tools` \
  bat btop fd-find gdu ripgrep \
  neovim luarocks tree-sitter-cli \
  python3-pip python3-virtualenv \
  protobuf protobuf-compiler \
  inotify-tools xsel numlockx \
  util-linux-user zsh \
  `# Terminal` \
  kitty \
  `# Arquivos e fonts` \
  file-roller inter-fonts glibc-gconv-extra \
  `# Browsers` \
  google-chrome-stable \
  `# Multimídia` \
  ffmpeg \
  gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free gstreamer1-plugins-ugly \
  gstreamer1-plugin-openh264 gstreamer1-plugin-libav \
  lame \
  vlc \
  pipewire-codec-aptx \
  `# Gaming` \
  steam \
  lutris \
  wine winetricks \
  gamemode gamescope \
  `# Backups e sistema` \
  timeshift \
  earlyoom \
  tuned tuned-ppd \
  sqlite \
  `# KDE / Tema Mokka` \
  kvantum qt6ct qt5ct \
  spectacle \
  flameshot \
  papirus-icon-theme \
  kwin-effects-forceblur kwin-effects-forceblur-x11 \
  kwin-effect-roundcorners kwin-effect-roundcorners-x11 \
  `# Build deps para Panel Colorizer e assets` \
  rsync libsass sassc

# ── Desabilitar COPRs ─────────────────────────────────────────────────────────
log "Desabilitando COPRs"
cleanup_coprs
trap - EXIT

# ── DNF performance ───────────────────────────────────────────────────────────
log "Configurando DNF performance"
mkdir -p /etc/dnf/conf.d
cp /ctx/configs/dnf-performance.conf /etc/dnf/conf.d/performance.conf

# ── Configs de sistema ────────────────────────────────────────────────────────
log "Aplicando configurações de sistema"

# Sysctl
install -Dm644 /ctx/configs/sysctl-hardening.conf \
  /etc/sysctl.d/60-security-hardening.conf
install -Dm644 /ctx/configs/sysctl-performance.conf \
  /etc/sysctl.d/99-performance.conf

# Modprobe
install -Dm644 /ctx/configs/modprobe-hardening.conf \
  /etc/modprobe.d/security-hardening.conf

# Core dumps
install -Dm644 /ctx/configs/limits-coredump.conf \
  /etc/security/limits.d/60-disable-coredump.conf
install -Dm644 /ctx/configs/systemd-coredump-system.conf \
  /etc/systemd/system.conf.d/60-disable-coredump.conf
install -Dm644 /ctx/configs/systemd-coredump-user.conf \
  /etc/systemd/user.conf.d/60-disable-coredump.conf

# DNS-over-TLS + DNSSEC
install -Dm644 /ctx/configs/resolved-dns.conf \
  /etc/systemd/resolved.conf.d/60-security-dns.conf

# Journal
install -Dm644 /ctx/configs/journald-size.conf \
  /etc/systemd/journald.conf.d/size-limit.conf

# fstrim fix
install -Dm644 /ctx/configs/fstrim-fix.conf \
  /etc/systemd/system/fstrim.service.d/quiet-unsupported.conf

# earlyoom override
install -Dm644 /ctx/configs/earlyoom-override.conf \
  /etc/systemd/system/earlyoom.service.d/override.conf

# SDDM theme
install -Dm644 /ctx/configs/sddm-theme.conf \
  /etc/sddm.conf.d/10-theme.conf

# ── Assets do tema Mokka ──────────────────────────────────────────────────────
log "Instalando assets do tema Mokka"
bash /ctx/install-assets.sh

# ── Panel Colorizer ───────────────────────────────────────────────────────────
log "Instalando Panel Colorizer"
bash /ctx/panel-colorizer.sh

# ── Rebuild cache de fontes ───────────────────────────────────────────────────
log "Rebuild cache de fontes"
fc-cache -f /usr/share/fonts/

# ── Skel: setup-user.sh ───────────────────────────────────────────────────────
log "Instalando setup-user.sh no skel"
install -Dm755 /ctx/skel/setup-user.sh /etc/skel/setup-user.sh

# ── Config KDE defaults via kwriteconfig6 ────────────────────────────────────
mkdir -p /etc/skel/.config

log "Aplicando overrides de config KDE no skel"

# ── Ícones e fontes ───────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group Icons --key Theme "Tela-circle-dracula"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key fixed "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key font "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key menuFont "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key toolBarFont "JetBrains Mono,10,-1,5,75,0,0,0,0,0"

# ── Cursor ────────────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
  --group Mouse --key cursorTheme "catppuccin-mocha-mauve-cursors"

# ── Touchpad ──────────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
  --group "Libinput" --group "default" --key NaturalScroll "true"

kwriteconfig6 --file /etc/skel/.config/kcminputrc \
  --group "Libinput" --group "default" --key PointerAcceleration "0.45"

# ── KWin: blur / efeitos ──────────────────────────────────────────────────────
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

# ── KWin: botões de janela à direita (estilo Windows) ─────────────────────────
kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group "org.kde.kdecoration2" --key ButtonsOnLeft ""

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group "org.kde.kdecoration2" --key ButtonsOnRight "IAX"

# ── KWin: Night Color 3500K 18h–7h ────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group NightColor --key Active "true"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group NightColor --key NightTemperature "3500"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group NightColor --key DayTemperature "6500"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group NightColor --key Mode "Time"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group NightColor --key MorningBeginFixed "0700"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group NightColor --key EveningBeginFixed "1800"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group NightColor --key TransitionTime "30"

# ── Power management (laptop) ─────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
  --group "AC" --group "Performance" --key PowerProfile "performance"

kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
  --group "AC" --group "SuspendAndShutdown" --key AutoSuspendAction "0"

kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
  --group "Battery" --group "Performance" --key PowerProfile "power-saver"

kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
  --group "Battery" --group "SuspendAndShutdown" --key AutoSuspendAction "1"

kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
  --group "Battery" --group "SuspendAndShutdown" --key AutoSuspendIdleTimeoutSec "600"

kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
  --group "LowBattery" --group "Performance" --key PowerProfile "power-saver"

kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
  --group "LowBattery" --group "SuspendAndShutdown" --key AutoSuspendAction "1"

kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
  --group "LowBattery" --group "SuspendAndShutdown" --key AutoSuspendIdleTimeoutSec "300"

# ── Serviços do sistema ───────────────────────────────────────────────────────
log "Habilitando e mascarando serviços"
systemctl enable podman.socket
systemctl enable tuned
systemctl enable earlyoom
systemctl mask passim || true

log "Build concluído."
