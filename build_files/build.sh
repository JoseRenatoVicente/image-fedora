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

# ── RPM Fusion (free + nonfree) ───────────────────────────────────────────────
log "Habilitando RPM Fusion"
dnf5 install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

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

# ── Remover pacotes indesejados (apenas pacotes presentes no Kinoite) ─────────
log "Removendo pacotes indesejados"
REMOVE_PKGS=(
  # KDE bloat
  kmahjongg kpat kmines kolourpaint
  krdc krfb kmouth kmousetool
  konversation kaddressbook korganizer kmail kontact
  akregator elisa-player dragon kamoso
  # Outros
  mediawriter ptyxis firefox
)
FOUND_PKGS=()
for pkg in "${REMOVE_PKGS[@]}"; do
  if rpm -q "$pkg" &>/dev/null; then
    FOUND_PKGS+=("$pkg")
  fi
done
if [[ ${#FOUND_PKGS[@]} -gt 0 ]]; then
  dnf5 remove -y "${FOUND_PKGS[@]}"
  log "Removidos: ${FOUND_PKGS[*]}"
else
  log "Nenhum pacote indesejado encontrado para remover"
fi

# ── Instalação de Pacotes ─────────────────────────────────────────────────────
log "Instalando pacotes"
dnf5 install -y --allowerasing \
  `# Dev tools` \
  git curl unzip tar jq make gettext \
  code \
  `# CLI tools` \
  bat btop fd-find ripgrep \
  neovim luarocks tree-sitter-cli \
  python3-pip python3-virtualenv \
  inotify-tools xsel numlockx \
  util-linux-user zsh \
  `# Terminal` \
  kitty \
  `# Arquivos e fonts` \
  file-roller glibc-gconv-extra \
  `# Multimídia (codecs essenciais)` \
  ffmpeg \
  gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugin-openh264 \
  pipewire-codec-aptx \
  `# Gaming (Steam, Lutris, Heroic via Flatpak no setup-user.sh)` \
  gamemode \
  `# Backups e sistema` \
  dracut-fips \
  earlyoom \
  tuned tuned-ppd \
  `# Containers` \
  podman-docker \
  `# KDE / Tema Mokka` \
  kvantum qt6ct \
  flameshot \
  `# Build deps para Panel Colorizer e assets (removidos após uso)` \
  gcc-c++ cmake extra-cmake-modules libplasma-devel \
  kf6-kcoreaddons-devel kf6-kirigami-devel kf6-kpackage-devel kf6-kwindowsystem-devel \
  rsync libsass sassc

# ── kwin-effect-roundcorners (passo separado para evitar skip silencioso) ─────
log "Instalando kwin-effect-roundcorners do COPR"
dnf5 install -y kwin-effect-roundcorners kwin-effect-roundcorners-x11 \
  || echo "WARN: kwin-effect-roundcorners não instalado"

# ── Desabilitar COPRs ─────────────────────────────────────────────────────────
log "Desabilitando COPRs"
cleanup_coprs
trap - EXIT

# ── Claude Code (Anthropic) ───────────────────────────────────────────────────
log "Instalando Claude Code via script oficial"
NONINTERACTIVE=1 curl -fsSL https://claude.ai/install.sh | bash
if command -v claude &>/dev/null; then
  ok "Claude Code instalado com sucesso"
else
  echo "WARN: Claude Code pode não estar no PATH, verifique a instalação" >&2
fi

# ── DNF performance ───────────────────────────────────────────────────────────
log "Configurando DNF performance"
mkdir -p /etc/dnf/conf.d
cp /ctx/configs/dnf-performance.conf /etc/dnf/conf.d/performance.conf

# ── Crypto policy obrigatória ─────────────────────────────────────────────────
log "Configurando crypto policy"
update-crypto-policies --set FUTURE

# ── Configs de sistema ────────────────────────────────────────────────────────
log "Aplicando configurações de sistema"

# SELinux
install -Dm644 /ctx/configs/selinux-enforcing.conf \
  /etc/selinux/config

# Sysctl - hardening
install -Dm644 /ctx/configs/sysctl-hardening.conf \
  /etc/sysctl.d/60-security-hardening.conf
install -Dm644 /ctx/configs/sysctl-ptrace.conf \
  /etc/sysctl.d/61-ptrace-scope.conf
install -Dm644 /ctx/configs/sysctl-performance.conf \
  /etc/sysctl.d/99-performance.conf

# Modprobe - hardening
install -Dm644 /ctx/configs/modprobe-hardening.conf \
  /etc/modprobe.d/security-hardening.conf
install -Dm644 /ctx/configs/modprobe-framebuffer-blacklist.conf \
  /etc/modprobe.d/blacklist-framebuffer.conf

# Kernel boot parameters (bootc kargs)
install -Dm644 /ctx/configs/bootc-kargs.toml \
  /usr/lib/bootc/kargs.d/10-hardening.toml

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
install -Dm644 /ctx/configs/resolved-disable-llmnr.conf \
  /etc/systemd/resolved.conf.d/10-disable-llmnr.conf

# Chrony com NTS (Network Time Security)
install -Dm644 /ctx/configs/chrony-nts.conf \
  /etc/chrony.conf

# Firewalld - zona sem serviços expostos
install -Dm644 /ctx/configs/firewalld-workstation.xml \
  /etc/firewalld/zones/FedoraWorkstation.xml

# Password policy e account lockout
install -Dm644 /ctx/configs/pwquality.conf \
  /etc/security/pwquality.conf
install -Dm644 /ctx/configs/faillock.conf \
  /etc/security/faillock.conf

# NetworkManager hardening (IPv6 privacy)
install -Dm644 /ctx/configs/networkmanager-hardening.conf \
  /usr/lib/NetworkManager/conf.d/40-hardening.conf

# Dracut - omitir firewire/thunderbolt do initramfs
install -Dm644 /ctx/configs/dracut-omit-firewire.conf \
  /etc/dracut.conf.d/99-omit-firewire.conf
install -Dm644 /ctx/configs/dracut-omit-thunderbolt.conf \
  /etc/dracut.conf.d/99-omit-thunderbolt.conf

# Udev rules - desabilitar binfmt_misc
install -Dm644 /ctx/configs/udev-hardening.rules \
  /usr/lib/udev/rules.d/99-hardening.rules

# Validações obrigatórias de hardening
grep -qx 'SELINUX=enforcing' /etc/selinux/config
grep -qx 'FUTURE' /etc/crypto-policies/config
rpm -q dracut-fips >/dev/null
grep -Fq '"fips=1"' /usr/lib/bootc/kargs.d/10-hardening.toml

# Systemd preset - desabilitar serviços desnecessários
install -Dm644 /ctx/configs/systemd-preset-desktop.preset \
  /usr/lib/systemd/system-preset/35-security-desktop.preset

# KDE: prevenir Xwayland eavesdropping
install -Dm644 /ctx/configs/kwinrc-xwayland.conf \
  /etc/xdg/kwinrc

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

# ── Remoção de dependências de build ──────────────────────────────────────────
log "Removendo dependências de build"
BUILD_DEPS=(
  # Compiladores e headers
  gcc-c++ cpp gcc
  cmake extra-cmake-modules
  libplasma-devel
  kf6-kcoreaddons-devel kf6-kirigami-devel kf6-kpackage-devel kf6-kwindowsystem-devel
  libsass sassc
  # Ferramentas usadas apenas no build
  make gettext rsync unzip
)
FOUND_BUILD_DEPS=()
for pkg in "${BUILD_DEPS[@]}"; do
  if rpm -q "$pkg" &>/dev/null; then
    FOUND_BUILD_DEPS+=("$pkg")
  fi
done
if [[ ${#FOUND_BUILD_DEPS[@]} -gt 0 ]]; then
  dnf5 remove -y "${FOUND_BUILD_DEPS[@]}"
fi

# ── Limpeza final ─────────────────────────────────────────────────────────────
log "Limpeza final do image"
dnf5 clean all
# Remover caches e arquivos temporários
rm -rf /var/cache/dnf /var/log/dnf* /var/log/hawkey*
# Remover docs/man pages desnecessários (economia ~50-100MB)
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
# Remover locales não usados (manter apenas pt_BR e en_US)
find /usr/share/locale -mindepth 1 -maxdepth 1 \
  ! -name 'pt_BR' ! -name 'en_US' ! -name 'locale.alias' \
  -exec rm -rf {} + 2>/dev/null || true

# ── Skel: setup-user.sh ───────────────────────────────────────────────────────
log "Instalando setup-user.sh no skel"
install -Dm755 /ctx/skel/setup-user.sh /etc/skel/setup-user.sh

# ── Skel: Initial setup wrapper + systemd service ────────────────────────────
log "Instalando fedora-initial-setup wrapper e systemd service"
install -Dm755 /ctx/skel/.local/bin/fedora-initial-setup /etc/skel/.local/bin/fedora-initial-setup
install -Dm644 /ctx/skel/.config/systemd/user/fedora-setup.service /etc/skel/.config/systemd/user/fedora-setup.service

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
  --group Plugins --key blurEnabled "true"

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
log "Habilitando serviços"
systemctl enable podman.socket
systemctl enable tuned
systemctl enable earlyoom
systemctl enable firewalld
systemctl enable chronyd

# ── Flatpak: substituir remote Fedora por Flathub ─────────────────────────────
log "Configurando Flatpak remotes"
flatpak remote-add --system --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo || true
flatpak remote-delete --system --force fedora 2>/dev/null || true

log "Build concluído."
