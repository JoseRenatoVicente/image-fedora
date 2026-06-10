#!/bin/bash
set -euo pipefail

trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Exportar variáveis de imagem para sub-scripts (image-info.sh, etc.)
# Podem ser passadas via ARG no Containerfile: --build-arg IMAGE_NAME=minha-imagem
export IMAGE_NAME="${IMAGE_NAME:-fedora}"
export IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Fedora}"
export IMAGE_VENDOR="${IMAGE_VENDOR:-}"
export SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"

# shellcheck source=shared/copr-helpers.sh
source /ctx/shared/copr-helpers.sh

# ─── Setup ────────────────────────────────────────────────────────────────────
echo "::group:: Setup"
install -Dm644 /ctx/configs/dnf-performance.conf /etc/dnf/conf.d/performance.conf
dnf5 install -y dnf5-plugins
echo "::endgroup::"

# ─── RPM Fusion ───────────────────────────────────────────────────────────────
echo "::group:: RPM Fusion"
dnf5 install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
echo "::endgroup::"

# ─── Versionlock KDE/Qt ───────────────────────────────────────────────────────
# Previne partial upgrade do Plasma durante o build (causaria black screen).
# Deve correr ANTES de qualquer dnf install que possa actualizar qt6/plasma.
echo "::group:: Versionlock KDE/Qt"
dnf5 versionlock add "qt6-*" "plasma-desktop"
echo "::endgroup::"

# ─── Remove bloat ─────────────────────────────────────────────────────────────
echo "::group:: Remove bloat"
REMOVE_PKGS=(
    kmahjongg kpat kmines kolourpaint
    krdc krfb kmouth kmousetool
    konversation kaddressbook korganizer kmail kontact
    akregator elisa-player dragon kamoso
    mediawriter ptyxis firefox
)
FOUND_PKGS=()
for pkg in "${REMOVE_PKGS[@]}"; do
    rpm -q "$pkg" &>/dev/null && FOUND_PKGS+=("$pkg")
done
if [[ ${#FOUND_PKGS[@]} -gt 0 ]]; then
    dnf5 remove -y "${FOUND_PKGS[@]}"
    echo "Removidos: ${FOUND_PKGS[*]}"
else
    echo "Nenhum pacote de bloat encontrado."
fi
echo "::endgroup::"

# ─── Install Fedora packages ──────────────────────────────────────────────────
echo "::group:: Install packages"
PACKAGES=(
    # Dev tools
    git curl unzip tar jq make gettext
    # CLI tools
    bat btop fd-find ripgrep fastfetch
    neovim luarocks tree-sitter-cli
    python3-pip python3-virtualenv
    inotify-tools xsel numlockx
    util-linux-user zsh
    # Terminal
    kitty
    # Ficheiros e fonts
    file-roller glibc-gconv-extra
    # Multimédia
    ffmpeg
    gstreamer1-plugins-base gstreamer1-plugins-good
    gstreamer1-plugin-openh264
    pipewire-codec-aptx
    # Gaming
    gamemode
    # Sistema
    earlyoom
    tuned tuned-ppd
    zram-generator
    # Containers
    distrobox podman-docker podman-compose
    # KDE / temas
    kvantum qt6ct
    flameshot
    # KDE integrations
    git-credential-libsecret ksshaskpass ksystemlog plasma-firewall
    # Hardware monitoring
    lm_sensors nvtop powertop
    # Peripheral support
    input-remapper solaar-udev
    # Security keys (U2F / YubiKey)
    pam-u2f pam_yubico pamu2fcfg yubikey-manager
    # Build deps (removidos no passo cleanup)
    gcc-c++ cmake extra-cmake-modules libplasma-devel
    kf6-kcoreaddons-devel kf6-kirigami-devel kf6-kpackage-devel kf6-kwindowsystem-devel
    rsync libsass sassc
)
dnf5 install -y --allowerasing "${PACKAGES[@]}"

# Desabilitar RPM Fusion imediatamente após instalar os pacotes
for repo in rpmfusion-free rpmfusion-free-updates rpmfusion-nonfree rpmfusion-nonfree-updates; do
    [[ -f "/etc/yum.repos.d/${repo}.repo" ]] && \
        sed -i 's@enabled=1@enabled=0@g' "/etc/yum.repos.d/${repo}.repo"
done
echo "::endgroup::"

# ─── VS Code (isolado) ────────────────────────────────────────────────────────
echo "::group:: VS Code"
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=0
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
# Instalar com --enablerepo: o repo fica desabilitado na imagem final
dnf5 install -y --enablerepo=code code
echo "::endgroup::"

# ─── COPR packages (isolados) ────────────────────────────────────────────────
echo "::group:: COPR packages"
# kwin-effect-roundcorners não está nos repos Fedora
copr_install_isolated "matinlotfali/KDE-Rounded-Corners" \
    kwin-effect-roundcorners kwin-effect-roundcorners-x11 \
    || echo "WARN: kwin-effect-roundcorners não instalado"
# scx-scheds não está nos repos padrão do Kinoite (disponível via COPR sched_ext)
copr_install_isolated "sched_ext/scx" \
    scx-scheds \
    || echo "WARN: scx-scheds não instalado"
echo "::endgroup::"

# ─── System configs ───────────────────────────────────────────────────────────
echo "::group:: System configs"

install -Dm644 /ctx/configs/selinux-enforcing.conf /etc/selinux/config

install -Dm644 /ctx/configs/sysctl-hardening.conf \
    /etc/sysctl.d/60-security-hardening.conf
install -Dm644 /ctx/configs/sysctl-ptrace.conf \
    /etc/sysctl.d/61-ptrace-scope.conf
install -Dm644 /ctx/configs/sysctl-performance.conf \
    /etc/sysctl.d/99-performance.conf

install -Dm644 /ctx/configs/modprobe-hardening.conf \
    /etc/modprobe.d/security-hardening.conf
install -Dm644 /ctx/configs/modprobe-framebuffer-blacklist.conf \
    /etc/modprobe.d/blacklist-framebuffer.conf

install -Dm644 /ctx/configs/bootc-kargs.toml \
    /usr/lib/bootc/kargs.d/10-hardening.toml

install -Dm644 /ctx/configs/limits-coredump.conf \
    /etc/security/limits.d/60-disable-coredump.conf
install -Dm644 /ctx/configs/systemd-coredump-system.conf \
    /etc/systemd/system.conf.d/60-disable-coredump.conf
install -Dm644 /ctx/configs/systemd-coredump-user.conf \
    /etc/systemd/user.conf.d/60-disable-coredump.conf

install -Dm644 /ctx/configs/resolved-dns.conf \
    /etc/systemd/resolved.conf.d/60-security-dns.conf
install -Dm644 /ctx/configs/resolved-disable-llmnr.conf \
    /etc/systemd/resolved.conf.d/10-disable-llmnr.conf

install -Dm644 /ctx/configs/chrony-nts.conf /etc/chrony.conf

install -Dm644 /ctx/configs/firewalld-workstation.xml \
    /etc/firewalld/zones/FedoraWorkstation.xml

install -Dm644 /ctx/configs/pwquality.conf /etc/security/pwquality.conf
install -Dm644 /ctx/configs/faillock.conf /etc/security/faillock.conf

install -Dm644 /ctx/configs/networkmanager-hardening.conf \
    /usr/lib/NetworkManager/conf.d/40-hardening.conf

install -Dm644 /ctx/configs/dracut-omit-firewire.conf \
    /etc/dracut.conf.d/99-omit-firewire.conf
install -Dm644 /ctx/configs/dracut-omit-thunderbolt.conf \
    /etc/dracut.conf.d/99-omit-thunderbolt.conf

install -Dm644 /ctx/configs/udev-hardening.rules \
    /usr/lib/udev/rules.d/99-hardening.rules

install -Dm644 /ctx/configs/systemd-preset-desktop.preset \
    /usr/lib/systemd/system-preset/35-security-desktop.preset

install -Dm644 /ctx/configs/kwinrc-xwayland.conf /etc/xdg/kwinrc

install -Dm644 /ctx/configs/journald-size.conf \
    /etc/systemd/journald.conf.d/size-limit.conf

install -Dm644 /ctx/configs/fstrim-fix.conf \
    /etc/systemd/system/fstrim.service.d/quiet-unsupported.conf

install -Dm644 /ctx/configs/earlyoom-override.conf \
    /etc/systemd/system/earlyoom.service.d/override.conf

install -Dm644 /ctx/configs/sddm-theme.conf /etc/sddm.conf.d/10-theme.conf

install -Dm644 /ctx/configs/chrony-nts-policy.pmod \
    /etc/crypto-policies/policies/modules/CHRONY-NTS.pmod

install -Dm644 /ctx/configs/rpm-ostreed.conf /etc/rpm-ostreed.conf

install -Dm644 /ctx/configs/dracut-luks.conf \
    /etc/dracut.conf.d/90-luks-security.conf

install -Dm644 /ctx/configs/copr-vendor.conf \
    /usr/share/dnf/plugins/copr.vendor.conf

install -Dm644 /ctx/configs/flatpak-nuke-fedora.service \
    /usr/lib/systemd/system/flatpak-nuke-fedora.service

# ── Bazzite-derived configs ───────────────────────────────────────────────────
install -Dm644 /ctx/configs/zram-generator.conf \
    /etc/systemd/zram-generator.conf

install -Dm644 /ctx/configs/udev-io-schedulers.rules \
    /usr/lib/udev/rules.d/60-io-schedulers.rules

install -Dm644 /ctx/configs/wireplumber-no-suspend.conf \
    /usr/share/wireplumber/wireplumber.conf.d/51-disable-suspension.conf

# Wireplumber: bloquear Steam de limpar defaults de áudio (equiv. ao patch Nobara)
mv /usr/bin/wpctl /usr/bin/wpctl.real
install -Dm755 /ctx/configs/wpctl-steam-wrapper /usr/bin/wpctl

install -Dm644 /ctx/configs/systemd-timeout.conf \
    /etc/systemd/system.conf.d/timeout.conf
install -Dm644 /ctx/configs/systemd-timeout.conf \
    /etc/systemd/user.conf.d/timeout.conf

install -Dm644 /ctx/configs/qtlogging.ini \
    /usr/share/qt6/qtlogging.ini

install -Dm644 /ctx/configs/udev-gpu-reset.rules \
    /usr/lib/udev/rules.d/80-gpu-reset.rules

install -Dm755 /ctx/configs/dnf-wrapper /usr/bin/dnf

install -Dm644 /ctx/configs/dnf-no-weak-deps.conf \
    /etc/dnf/conf.d/no-weak-deps.conf

install -Dm644 /ctx/configs/modules-ntsync.conf \
    /usr/lib/modules-load.d/wine-ntsync.conf

install -Dm644 /ctx/configs/limits-memlock.conf \
    /etc/security/limits.d/50-memlock.conf

# Anotar ficheiros de hardening com metadados de componente
setfattr -n user.component -v "security-hardening" \
    /etc/sysctl.d/60-security-hardening.conf \
    /etc/sysctl.d/61-ptrace-scope.conf \
    /etc/modprobe.d/security-hardening.conf \
    /etc/modprobe.d/blacklist-framebuffer.conf \
    /usr/lib/bootc/kargs.d/10-hardening.toml \
    /usr/lib/udev/rules.d/99-hardening.rules

setfattr -n user.component -v "image-config" \
    /etc/sysctl.d/99-performance.conf \
    /etc/systemd/resolved.conf.d/60-security-dns.conf \
    /etc/systemd/resolved.conf.d/10-disable-llmnr.conf \
    /etc/chrony.conf \
    /etc/security/pwquality.conf \
    /etc/security/faillock.conf \
    /usr/lib/NetworkManager/conf.d/40-hardening.conf \
    /usr/lib/systemd/system-preset/35-security-desktop.preset \
    /etc/xdg/kwinrc \
    /etc/systemd/journald.conf.d/size-limit.conf \
    /etc/sddm.conf.d/10-theme.conf

echo "::endgroup::"

# ─── Theming ──────────────────────────────────────────────────────────────────
echo "::group:: Theming"
bash /ctx/install-assets.sh
bash /ctx/panel-colorizer.sh
fc-cache -f /usr/share/fonts/
setfattr -n user.component -v "themes" /usr/share/fonts/JetBrainsMonoNerdFont
setfattr -n user.update-interval -v "yearly" /usr/share/fonts/JetBrainsMonoNerdFont
echo "::endgroup::"

# ─── Skel + KDE defaults ──────────────────────────────────────────────────────
echo "::group:: Skel + KDE defaults"
mkdir -p /etc/skel/.config

install -Dm755 /ctx/skel/setup-user.sh /etc/skel/setup-user.sh
install -Dm755 /ctx/skel/.local/bin/fedora-initial-setup \
    /etc/skel/.local/bin/fedora-initial-setup
install -Dm644 /ctx/skel/.config/systemd/user/fedora-setup.service \
    /etc/skel/.config/systemd/user/fedora-setup.service

# VM compatibility: disable heavy kwin effects in virtual machines
install -Dm755 /ctx/skel/.local/bin/kwin-vm-compat.sh \
    /etc/skel/.local/bin/kwin-vm-compat.sh
install -Dm644 /ctx/skel/.config/autostart/kwin-vm-compat.desktop \
    /etc/skel/.config/autostart/kwin-vm-compat.desktop

# Panel layout: provides the bottom taskbar without relying on Garuda-specific
# look-and-feel templates (org.garuda.desktop.defaultPanel) that don't exist on Fedora.
install -Dm644 /ctx/skel/.config/plasma-org.kde.plasma.desktop-appletsrc \
    /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc

# Patch Mokka layout.js: remove Garuda-specific loadTemplate calls and a2n.blur.
# Without this, if Plasma runs the script on look-and-feel change, it creates
# containments with empty plugin IDs → "error when loading applet """.
install -Dm644 /ctx/configs/mokka-layout.js \
    /usr/share/plasma/look-and-feel/Mokka/contents/layouts/org.kde.plasma.desktop-layout.js

# Fix Mokka Splash.qml: 'sizes' is not defined — typo in the Garuda package (should be 'size')
# Replace all word-bounded occurrences; 'sizes' appears in multiple lines (width, height, etc.)
sed -i 's/\bsizes\b/size/g' \
    /usr/share/plasma/look-and-feel/Mokka/contents/splash/Splash.qml

# Fix KSplash theme: Mokka defaults reference 'Catppuccin-Mocha-Mauve-splash' which
# is not installed. Use 'Mokka' (the look-and-feel's own splash screen, now fixed above).
sed -i 's/^Theme=Catppuccin-Mocha-Mauve-splash$/Theme=Mokka/' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

# KSplash skel config
kwriteconfig6 --file /etc/skel/.config/ksplashrc \
    --group KSplash --key Theme "Mokka"

# Disable plasma-welcome OOBE for new users: system-wide default and per-user skel.
# Without this, plasma-welcome runs on first login and plasma-setup tries to overwrite
# kdeglobals/kwinrc — failing with "file already exists" because skel already wrote them.
install -Dm644 /ctx/configs/plasma-welcomerc /etc/xdg/plasma-welcomerc
kwriteconfig6 --file /etc/skel/.config/plasma-welcomerc \
    --group General --key ShowOnStartup "false"

setfattr -n user.component -v "skel" \
    /etc/skel/setup-user.sh \
    /etc/skel/.local/bin/fedora-initial-setup
setfattr -n user.update-interval -v "monthly" \
    /etc/skel/setup-user.sh \
    /etc/skel/.local/bin/fedora-initial-setup

# ── Tema Mokka: visual theme ──────────────────────────────────────────────────
# Plasma desktop shell theme (afecta painel, widgets, popup menus)
kwriteconfig6 --file /etc/skel/.config/plasmarc \
    --group Theme --key name "Mokka"

# Color scheme + look-and-feel package
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key ColorScheme "Mokka"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group KDE --key LookAndFeelPackage "Mokka"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group KDE --key widgetStyle "kvantum-dark"

# Ícones: variante -dark para fundo escuro (tray/painel com ícones claros)
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group Icons --key Theme "Tela-circle-dracula-dark"

# Fontes customizadas (JetBrains Mono em vez da Inter do Garuda)
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key fixed "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key font "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key menuFont "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key toolBarFont "JetBrains Mono,10,-1,5,75,0,0,0,0,0"

# Cursor
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group Mouse --key cursorTheme "catppuccin-mocha-mauve-cursors"
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group "Libinput" --group "default" --key NaturalScroll "true"
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group "Libinput" --group "default" --key PointerAcceleration "0.45"

# ── KWin ──────────────────────────────────────────────────────────────────────
# Decoração Aurorae (requer catppuccin-kde instalado via install-assets.sh)
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key library "org.kde.kwin.aurorae"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key theme "__aurorae__svg__CatppuccinMocha-Classic"

# Botões à direita (estilo Windows, diferente do padrão Garuda que é à esquerda)
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key ButtonsOnLeft ""
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key ButtonsOnRight "IAX"

# Efeitos visuais (desabilitados em VMs pelo kwin-vm-compat.sh; ativos em metal)
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key blurEnabled "true"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key roundcornersEnabled "true"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key kwin4_effect_roundcornersEnabled "true"

# Night Color
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

# ── Power management ──────────────────────────────────────────────────────────
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

echo "::endgroup::"

# ─── Serviços + Flatpak ───────────────────────────────────────────────────────
echo "::group:: Services + Flatpak"
systemctl enable podman.socket
systemctl enable tuned
systemctl enable earlyoom
systemctl enable firewalld
systemctl enable chronyd
systemctl enable bluetooth.service bluetooth.target
if systemctl list-unit-files dconf-update.service &>/dev/null; then
    systemctl enable dconf-update.service
else
    echo "INFO: dconf-update.service não existe nesta base, ignorando"
fi
systemctl enable flatpak-nuke-fedora.service
systemctl enable input-remapper.service
if rpm -q scx-scheds &>/dev/null; then
    systemctl enable scx.service
fi

flatpak remote-add --system --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo || true
flatpak remote-delete --system --force fedora 2>/dev/null || true
echo "::endgroup::"

# ─── Remove build deps ────────────────────────────────────────────────────────
echo "::group:: Remove build deps"
BUILD_DEPS=(
    gcc-c++ cpp gcc
    cmake extra-cmake-modules
    libplasma-devel
    kf6-kcoreaddons-devel kf6-kirigami-devel kf6-kpackage-devel kf6-kwindowsystem-devel
    libsass sassc
    rsync
)
FOUND_BUILD_DEPS=()
for pkg in "${BUILD_DEPS[@]}"; do
    rpm -q "$pkg" &>/dev/null && FOUND_BUILD_DEPS+=("$pkg")
done
[[ ${#FOUND_BUILD_DEPS[@]} -gt 0 ]] && dnf5 remove -y "${FOUND_BUILD_DEPS[@]}"
echo "::endgroup::"

# ─── Cleanup final ────────────────────────────────────────────────────────────
echo "::group:: Cleanup"
dnf5 versionlock clear
dnf5 clean all
rm -rf /var/cache/dnf /var/log/dnf* /var/log/hawkey*
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
find /usr/share/locale -mindepth 1 -maxdepth 1 \
    ! -name 'pt_BR' ! -name 'en_US' ! -name 'locale.alias' \
    -exec rm -rf {} + 2>/dev/null || true
echo "::endgroup::"

# ─── Validate repos ───────────────────────────────────────────────────────────
/ctx/shared/validate-repos.sh

# ─── Image info + os-release ─────────────────────────────────────────────────
/ctx/shared/image-info.sh

# ─── Crypto policy (LAST: RSA-2048 rejeitado por FUTURE, bloqueia downloads) ─
echo "::group:: Crypto policy"
update-crypto-policies --set FUTURE:CHRONY-NTS
echo "::endgroup::"

# ─── Tests (após crypto policy para validar FUTURE) ──────────────────────────
/ctx/shared/tests.sh
