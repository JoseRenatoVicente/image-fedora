#!/bin/bash
set -euo pipefail

trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Exportar variáveis de imagem para sub-scripts (image-info.sh, etc.)
# Podem ser passadas via ARG no Containerfile: --build-arg IMAGE_NAME=minha-imagem
export IMAGE_NAME="${IMAGE_NAME:-fedora}"
export IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Fedora}"
export IMAGE_VENDOR="${IMAGE_VENDOR:-}"
export SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"
# SOURCE_DATE_EPOCH só deve ser exportado quando tem um valor numérico válido
# (CI passa o timestamp do commit). Em builds locais chega vazio via ARG do
# Containerfile; exportá-lo vazio faz o fontconfig (fc-cache) emitir
# "SOURCE_DATE_EPOCH invalid" — vazio ≠ indefinido. Nesse caso, deixamos
# indefinido para as ferramentas usarem o comportamento normal.
if [[ "${SOURCE_DATE_EPOCH:-}" =~ ^[0-9]+$ ]]; then
    export SOURCE_DATE_EPOCH
else
    unset SOURCE_DATE_EPOCH
fi

# shellcheck source=shared/copr-helpers.sh
source /ctx/shared/copr-helpers.sh

# ─── Setup ────────────────────────────────────────────────────────────────────
echo "::group:: Setup"
install -Dm644 /ctx/configs/dnf-performance.conf /etc/dnf/conf.d/performance.conf
# Ensure the ostree dracut module is always included in any initramfs generated
# during this build — including those triggered by dnf package scripts before
# our explicit dracut step.  Without this, initrd-switch-root.service fails
# because ostree-prepare-root.service is absent from the initrd.
echo 'add_dracutmodules+=" ostree "' > /etc/dracut.conf.d/01-ostree-required.conf
dnf5 install -y dnf5-plugins
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

# ─── sudo → run0 (alias) ──────────────────────────────────────────────────────
# Objetivo: usar o run0 do systemd (eleva via polkit, sem setuid) em vez do sudo.
# run0 já vem com o systemd (/usr/bin/run0 → systemd-run).
#
# NOTA: o pacote `sudo` NÃO pode ser removido nesta imagem. plasma-workspace exige
# `kdesu` (kf6-kdesu), que por sua vez exige `sudo` — remover sudo arrasta o
# desktop KDE inteiro (plasma-workspace/plasma-desktop, 16 pacotes, 91 MiB). Por
# isso mantemos o pacote e adicionamos apenas o alias `sudo`→`run0` para shells
# interativos (forma prática de migrar o hábito sem partir o desktop).
echo "::group:: sudo → run0 (alias)"
install -Dm644 /ctx/configs/run0-alias.sh /etc/profile.d/run0-alias.sh
echo "::endgroup::"

# ─── Remove repos rpmfusion ───────────────────────────────────────────────────
# fedora-workstation-repositories traz definições rpmfusion-nonfree (nvidia/steam),
# já desabilitadas (enabled=0) e não usadas nesta imagem. Removê-las elimina o
# rpmfusion da superfície.
rm -f /etc/yum.repos.d/rpmfusion-*.repo

# ─── Install Fedora packages ──────────────────────────────────────────────────
echo "::group:: Install packages"
PACKAGES=(
    # Dev tools
    git curl unzip tar jq make gettext
    # CLI tools
    bat btop fd-find ripgrep fastfetch eza
    neovim
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
# IPSec blacklist opcional — não ativo por defeito (quebraria VPNs).
# O utilizador pode copiar para /etc/modprobe.d/ se não usar VPN.
install -Dm644 /ctx/configs/modprobe-ipsec-blacklist.conf \
    /usr/share/fedora-hardening/modprobe-ipsec-blacklist.conf

install -Dm644 /ctx/configs/bootc-kargs.toml \
    /usr/lib/bootc/kargs.d/10-hardening.toml

# GRUB: hide the boot menu and boot immediately.
# Overrides the 1-second menu in grub-static-pre.cfg (shipped by bootupd).
# The user can still reach the GRUB menu by holding Shift/Escape at power-on.
install -Dm644 /ctx/configs/grub-timeout.cfg \
    /usr/lib/bootupd/grub2-static/configs.d/05_timeout.cfg

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

# O display manager é o plasma-login-manager (plasmalogin), rebrand do SDDM que
# lê /etc/plasmalogin.conf.d/ — NÃO /etc/sddm.conf.d/. Instalar no caminho errado
# faz o tema de login ser silenciosamente ignorado. Temas continuam em
# /usr/share/sddm/themes/.
install -Dm644 /ctx/configs/sddm-theme.conf /etc/plasmalogin.conf.d/10-theme.conf

install -Dm644 /ctx/configs/chrony-nts-policy.pmod \
    /etc/crypto-policies/policies/modules/CHRONY-NTS.pmod

install -Dm644 /ctx/configs/rpm-ostreed.conf /etc/rpm-ostreed.conf

install -Dm644 /ctx/configs/dracut-luks.conf \
    /etc/dracut.conf.d/90-luks-security.conf

install -Dm644 /ctx/configs/copr-vendor.conf \
    /usr/share/dnf/plugins/copr.vendor.conf

install -Dm644 /ctx/configs/flatpak-nuke-fedora.service \
    /usr/lib/systemd/system/flatpak-nuke-fedora.service

install -Dm644 /ctx/configs/flathub-system-setup.service \
    /usr/lib/systemd/system/flathub-system-setup.service

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
    /etc/plasmalogin.conf.d/10-theme.conf

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

# Limpar ficheiros órfãos do skel Garuda Mokka que não devem existir nesta imagem:
# - initial-setup.{desktop,sh}: usa fish shell (não instalado) e referencia configs Garuda
# - environment.d/garuda.conf: define BROWSER=firedragon, EDITOR=/usr/bin/micro etc.
# - starship-mokka.toml: config starship do Garuda (tema movido para starship.toml pelo script)
# - fish/: config do fish shell (não instalado nesta imagem)
# - .local/share/plasma/look-and-feel/Mokka/: o rsync do skel Garuda copia o
#   pacote Mokka completo (incluindo layout.js) para o caminho user-local do skel.
#   Plasma resolve temas user-local ANTES dos system-wide, então o layout.js que
#   removemos de /usr/share/ ressurge em ~/.local/share/ quando o utilizador é
#   criado a partir do skel → loadTemplate("org.garuda.desktop.defaultPanel")
#   falha (template não existe no Fedora) → containment fantasma com plugin="" →
#   "error when loading applet """. Remover a cópia user-local inteira força o
#   Plasma a usar a versão system-wide (já sem layouts/).
#   Os restantes assets Mokka user-local (.local/share/plasma/desktoptheme,
#   color-schemes, wallpapers, konsole, Kvantum) são redundantes com os que
#   install-assets.sh instala em /usr/share/ — removê-los evita duplicação e
#   garante que updates à imagem se reflectem sem conflito user-local.
rm -f /etc/skel/.config/autostart/initial-setup.desktop \
      /etc/skel/.config/autostart/initial-setup.sh \
      /etc/skel/.config/starship-mokka.toml
rm -rf /etc/skel/.config/environment.d \
       /etc/skel/.config/fish \
       /etc/skel/.local/share/plasma/look-and-feel/Mokka \
       /etc/skel/.local/share/plasma/desktoptheme/Mokka \
       /etc/skel/.local/share/color-schemes/Mokka.colors \
       /etc/skel/.local/share/wallpapers/Mokka-tree \
       /etc/skel/.local/share/konsole/Mokka.colorscheme \
       /etc/skel/.local/share/Kvantum/Mokka

install -Dm755 /ctx/skel/setup-user.sh /etc/skel/setup-user.sh
install -Dm755 /ctx/skel/.local/bin/fedora-initial-setup \
    /etc/skel/.local/bin/fedora-initial-setup
install -Dm644 /ctx/skel/.config/systemd/user/fedora-setup.service \
    /etc/skel/.config/systemd/user/fedora-setup.service

# VM compatibility: disable heavy kwin effects in virtual machines.
# Script em /usr/libexec (caminho absoluto): o .desktop NÃO pode referenciar
# $HOME no Exec — o gerador xdg-autostart do systemd escapa o `$` (→ "\$HOME"),
# o exec aponta para um ficheiro inexistente e o serviço de utilizador falha.
# Autostart system-wide em /etc/xdg/autostart → corre para todos os utilizadores
# (o script lê $HOME/.config/kwinrc em runtime, onde HOME já está definido).
install -Dm755 /ctx/skel/.local/bin/kwin-vm-compat.sh \
    /usr/libexec/kwin-vm-compat.sh
install -Dm644 /ctx/skel/.config/autostart/kwin-vm-compat.desktop \
    /etc/xdg/autostart/kwin-vm-compat.desktop

# Panel layout: provides the bottom taskbar without relying on Garuda-specific
# look-and-feel templates (org.garuda.desktop.defaultPanel) that don't exist on Fedora.
install -Dm644 /ctx/skel/.config/plasma-org.kde.plasma.desktop-appletsrc \
    /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc

# Root user KDE config: /root is /var/roothome (mutable, empty at boot).
# tmpfiles.d C entries copy skel config to root on first boot if files don't exist.
install -Dm644 /ctx/configs/tmpfiles-root-kde.conf \
    /usr/lib/tmpfiles.d/fedora-kde-root-theme.conf

# Remove Mokka layout.js (system-wide): the original Garuda script calls
# loadTemplate() for panel templates that don't exist on Fedora and writes to
# appletsrc via ConfigFile, creating key+subgroup collisions → ghost containment
# with empty plugin → "error when loading applet """.  Removing the file entirely
# makes Plasma skip the layout engine and use the skel appletsrc directly.
# NOTA: a cópia user-local (skel/.local/share/plasma/look-and-feel/Mokka/) já foi
# removida acima — sem isso o Plasma encontrava o layout.js no caminho user-local
# (que tem prioridade sobre /usr/share/) e executava-o na mesma.
rm -rf /usr/share/plasma/look-and-feel/Mokka/contents/layouts

# KRunner: float KRunner in the center of the screen (moved here from layout.js
# to avoid ConfigFile writes that conflict with the skel appletsrc).
kwriteconfig6 --file /etc/skel/.config/krunnerrc \
    --group General --key FreeFloating "true"

# Fix Mokka Splash.qml: 'sizes' is not defined — typo in the Garuda package (should be 'size')
# Replace all word-bounded occurrences; 'sizes' appears in multiple lines (width, height, etc.)
sed -i 's/\bsizes\b/size/g' \
    /usr/share/plasma/look-and-feel/Mokka/contents/splash/Splash.qml

# Fix KSplash theme: Mokka defaults reference 'Catppuccin-Mocha-Mauve-splash' which
# is not installed. Use 'Mokka' (the look-and-feel's own splash screen, now fixed above).
sed -i 's/^Theme=Catppuccin-Mocha-Mauve-splash$/Theme=Mokka/' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

# Fix lock screen wallpaper: Mokka defaults reference garuda-mokka/ path which does not
# exist on Fedora. Wallpaper is installed as a KDE package at Mokka-tree/.
sed -i 's|^Image=file:///usr/share/wallpapers/garuda-mokka/Mokka-tree\.jpg$|Image=file:///usr/share/wallpapers/Mokka-tree/|' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

# KSplash skel config
kwriteconfig6 --file /etc/skel/.config/ksplashrc \
    --group KSplash --key Theme "Mokka"

# Disable plasma-setup OOBE (first-run wizard). plasma-setup.service corre
# Before=display-manager.service e lança uma sessão Plasma própria (utilizador
# plasma-setup) para criar o utilizador inicial — redundante aqui: o instalador
# Anaconda já cria o utilizador (Modules.Users habilitado nos ISOs). Deixá-lo
# activo preempta o login normal e gera ruído /run/plasma-setup no journal.
# O flag /etc/plasma-setup-done é o mecanismo oficial (ConditionPathExists) que
# o desliga.
touch /etc/plasma-setup-done

# Disable plasma-welcome OOBE for new users: system-wide default and per-user skel.
# Without this, plasma-welcome runs on first login and plasma-setup tries to overwrite
# kdeglobals/kwinrc — failing with "file already exists" because skel already wrote them.
install -Dm644 /ctx/configs/plasma-welcomerc /etc/xdg/plasma-welcomerc
kwriteconfig6 --file /etc/skel/.config/plasma-welcomerc \
    --group General --key ShowOnStartup "false"
kwriteconfig6 --file /etc/skel/.config/plasma-welcomerc \
    --group General --key LastSeenVersion "99.0"

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

# ── Ecrã de bloqueio (lock screen) ───────────────────────────────────────────
# O Garuda skel instala kscreenlockerrc com Theme=Mokka (inválido: Mokka não tem
# QML de lockscreen) e com wallpaper a apontar para o background do SDDM em vez
# do Mokka-tree. Sobrescrever ambos os valores problemáticos.
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --key Theme --delete 2>/dev/null || true
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --key WallpaperPlugin "org.kde.image"
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --group Wallpaper --group "org.kde.image" --group General \
    --key Image "file:///usr/share/wallpapers/Mokka-tree/"

# ── GTK themes ────────────────────────────────────────────────────────────────
# O Garuda skel tem gtk-theme-name=Catppuccin-Purple-Dark-Catppuccin (não instalado)
# e ícones/fontes errados. Sobrescrever com os nossos valores correctos.
kwriteconfig6 --file /etc/skel/.config/gtk-3.0/settings.ini \
    --group Settings --key gtk-theme-name "catppuccin-mocha-mauve-standard+default"
kwriteconfig6 --file /etc/skel/.config/gtk-3.0/settings.ini \
    --group Settings --key gtk-icon-theme-name "Tela-circle-dracula-dark"
kwriteconfig6 --file /etc/skel/.config/gtk-3.0/settings.ini \
    --group Settings --key gtk-font-name "JetBrains Mono, 10"
kwriteconfig6 --file /etc/skel/.config/gtk-4.0/settings.ini \
    --group Settings --key gtk-theme-name "catppuccin-mocha-mauve-standard+default"
kwriteconfig6 --file /etc/skel/.config/gtk-4.0/settings.ini \
    --group Settings --key gtk-icon-theme-name "Tela-circle-dracula-dark"
kwriteconfig6 --file /etc/skel/.config/gtk-4.0/settings.ini \
    --group Settings --key gtk-font-name "JetBrains Mono, 10"

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
# Auto-updates: manter o sistema instalado actualizado automaticamente
systemctl enable rpm-ostreed-automatic.timer
systemctl enable podman-auto-update.timer
systemctl list-unit-files flatpak-system-update.timer &>/dev/null \
    && systemctl enable flatpak-system-update.timer \
    || echo "INFO: flatpak-system-update.timer não existe nesta base, ignorando"
if systemctl list-unit-files dconf-update.service &>/dev/null; then
    systemctl enable dconf-update.service
else
    echo "INFO: dconf-update.service não existe nesta base, ignorando"
fi
systemctl enable flatpak-nuke-fedora.service
systemctl enable flathub-system-setup.service
systemctl enable input-remapper.service
# Silencia o ruído de autoload do input-remapper (falha benigna por dispositivo
# quando não há preset) — override da regra udev upstream.
install -Dm644 /ctx/configs/udev-input-remapper.rules \
    /etc/udev/rules.d/99-input-remapper.rules
if rpm -q scx-scheds &>/dev/null; then
    systemctl enable scx.service
fi

# Sistemas atómicos: o remote flathub NÃO é baked em /var (estado mutável que não
# recebe updates e que o bootc lint sinaliza). Baixamos a definição estática para
# /usr (imutável, com GPGKey embutida) e flathub-system-setup.service regista o
# remote no boot. A remoção do remote `fedora` é feita pelo flatpak-nuke-fedora.service.
install -d /usr/share/flatpak
curl -L --fail --retry 3 --retry-delay 5 \
    -o /usr/share/flatpak/flathub.flatpakrepo \
    https://flathub.org/repo/flathub.flatpakrepo
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
[[ ${#FOUND_BUILD_DEPS[@]} -gt 0 ]] && dnf5 remove -y --setopt=clean_requirements_on_remove=True "${FOUND_BUILD_DEPS[@]}"
echo "::endgroup::"

# ─── Regenerate initramfs (virtio_gpu para Plymouth em VM) ────────────────────
# A base Kinoite NÃO inclui virtio_gpu no initramfs. Numa VM QEMU isso faz o
# Plymouth arrancar no simpledrm (built-in) e perder o ecrã quando o virtio_gpu
# assume o framebuffer ~1s depois (handoff). Pôr virtio_gpu no initramfs faz dele
# o framebuffer ANTES do Plymouth arrancar (como i915/amdgpu já estão), eliminando
# o handoff. No HW real o Plymouth já funcionava (driver nativo no initramfs).
#
# SEGURANÇA (motivo do aviso histórico): um initramfs sem o módulo ostree larga o
# sistema em emergency mode. O ostree é forçado (01-ostree-required.conf) e
# verificamos abaixo que ficou presente — senão o build falha. `just test-boot`
# valida o boot real.
echo "::group:: Initramfs"
install -Dm644 /ctx/configs/dracut-drm-drivers.conf /etc/dracut.conf.d/02-drm-drivers.conf
KVER=$(ls /usr/lib/modules | sort -V | tail -1)
INITRAMFS="/usr/lib/modules/$KVER/initramfs.img"

# Atualiza o índice de módulos antes do dracut: no meio do build o modules.dep
# pode estar dessincronizado e o dracut não resolve o virtio_gpu via add/force_drivers.
depmod "$KVER" 2>/dev/null || true

# --force-drivers na linha de comando reforça a config (02-drm-drivers.conf).
dracut --force --no-hostonly --force-drivers " virtio_gpu " --kver "$KVER" "$INITRAMFS"
[[ -s "$INITRAMFS" ]] || { echo "FATAL: initramfs vazio após dracut: $INITRAMFS"; exit 1; }

# ostree é CRÍTICO (sem ele → emergency mode) → falha o build se ausente.
INITRD_MODS=$(lsinitrd --mod "$INITRAMFS" 2>/dev/null)
printf '%s\n' "$INITRD_MODS" | grep -qE '^[[:space:]]*(50)?ostree[[:space:]]*$' \
    || { echo "FATAL: módulo ostree ausente no initramfs regenerado!"; exit 1; }
echo "✓ ostree presente no initramfs"
# virtio_gpu (ficheiro virtio-gpu.ko, hífen) é NÃO-crítico: só afeta o Plymouth em
# VM. Se faltar, avisa mas NÃO falha o build (a imagem arranca bem; no HW real o
# Plymouth funciona na mesma).
if lsinitrd "$INITRAMFS" 2>/dev/null | grep -qiE 'virtio.gpu\.ko'; then
    echo "✓ virtio_gpu presente no initramfs"
else
    echo "WARN: virtio_gpu não entrou no initramfs — Plymouth pode não aparecer em VM (HW real ok)"
fi
echo "::endgroup::"

# ─── Cleanup final ────────────────────────────────────────────────────────────
echo "::group:: Cleanup"
dnf5 versionlock clear
dnf5 clean all
rm -rf /var/cache/dnf /var/log/dnf* /var/log/hawkey*
# bootc lint (nonempty-run-tmp): /run e /tmp são runtime-only — não devem conter
# artefactos de build (dnf deixa /run/dnf).
rm -rf /run/* /tmp/* 2>/dev/null || true
# bootc lint (var-tmpfiles): cache de metadados e locks do dnf em /var/lib/dnf
# não precisam de ser baked na imagem (recriados em runtime).
rm -rf /var/lib/dnf/repos /var/lib/dnf/*.lock 2>/dev/null || true
# bootc lint (var-tmpfiles): estado do flatpak em /var é mutável e configurado no
# boot por flathub-system-setup.service — não deve ser baked. flatpak reinicializa
# /var/lib/flatpak em runtime ao registar o remote.
rm -rf /var/lib/flatpak 2>/dev/null || true
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
LOCALE_REMOVED=0
while IFS= read -r -d '' dir; do
    rm -rf "$dir" && ((++LOCALE_REMOVED))
done < <(find /usr/share/locale -mindepth 1 -maxdepth 1 \
    ! -name 'pt_BR' ! -name 'en_US' ! -name 'locale.alias' \
    -print0)
echo "Locales removidos: $LOCALE_REMOVED (mantidos: pt_BR, en_US)"
# Locale por omissão do sistema. Sem /etc/locale.conf, serviços como SDDM/
# plasmalogin-helper correm com LANG=C (não-UTF-8) e o Qt avisa no journal.
# en_US.UTF-8 está sempre disponível no locale-archive; o Anaconda sobrepõe
# conforme a escolha do utilizador na instalação.
echo "LANG=en_US.UTF-8" > /etc/locale.conf
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
