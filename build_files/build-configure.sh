#!/bin/bash
# Layer 2 — configuração, theming, skel, dracut, cleanup
# Cache invalidado quando qualquer ficheiro em build_files/ muda.
# Os pacotes já estão instalados pelo Layer 1 (build-packages.sh).
set -euo pipefail

trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Exportar variáveis de imagem para sub-scripts (image-info.sh, etc.)
export IMAGE_NAME="${IMAGE_NAME:-fedora}"
export IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Fedora}"
export IMAGE_VENDOR="${IMAGE_VENDOR:-}"
export SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"
# SOURCE_DATE_EPOCH só deve ser exportado quando tem um valor numérico válido
if [[ "${SOURCE_DATE_EPOCH:-}" =~ ^[0-9]+$ ]]; then
    export SOURCE_DATE_EPOCH
else
    unset SOURCE_DATE_EPOCH
fi

# shellcheck source=shared/copr-helpers.sh
source /ctx/shared/copr-helpers.sh

# ─── Remove repos rpmfusion ───────────────────────────────────────────────────
rm -f /etc/yum.repos.d/rpmfusion-*.repo

# ─── System configs ───────────────────────────────────────────────────────────
echo "::group:: System configs"

# Mirrored filesystem tree: each file already lives at its final path under
# build_files/etc/ and build_files/usr/; cp -aT overlays them in one shot.
cp -aT /ctx/etc/ /etc/
cp -aT /ctx/usr/ /usr/

# Executables from the mirrored tree need explicit permission bits.
chmod 755 /usr/bin/dnf
chmod 755 /usr/libexec/fedora-flatpak-setup \
          /usr/libexec/fedora-shell-setup \
          /usr/libexec/fedora-dev-setup \
          /usr/libexec/fedora-brew-setup

# Wireplumber: bloquear Steam de limpar defaults de áudio (equiv. ao patch Nobara)
mv /usr/bin/wpctl /usr/bin/wpctl.real
install -Dm755 /ctx/configs/wpctl-steam-wrapper /usr/bin/wpctl

# login.defs: UMASK 027 (ficheiros novos não são world-readable por defeito)
# e YESCRYPT_COST_FACTOR 8 (hashing de password mais resistente a brute-force)
sed -i 's/^UMASK\s\+022/UMASK\t\t027/' /etc/login.defs
sed -i 's/^#\?YESCRYPT_COST_FACTOR.*/YESCRYPT_COST_FACTOR 8/' /etc/login.defs

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
    /usr/lib/bootc/kargs.d/20-performance.toml \
    /usr/lib/tmpfiles.d/thp-tuning.conf \
    /etc/systemd/system/user@.service.d/10-delegate.conf \
    /etc/systemd/system.conf.d/10-nofile-limit.conf \
    /etc/systemd/user.conf.d/10-nofile-limit.conf \
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

# ─── Plasmalogin workaround (from Kinoite) ────────────────────────────────────
echo "::group:: Plasmalogin workaround"

cat > /usr/lib/systemd/system/fedora-kinoite-plasmalogin-workaround.service << 'EOF'
[Unit]
Description=Workaround for missing plasmalogin entries in /etc/shadow & /etc/gshadow
Documentation=https://forge.fedoraproject.org/kde/tickets/issues/684
ConditionPathIsReadWrite=/etc
ConditionPathExists=/run/ostree-booted
ConditionPathExists=!/etc/.fedora-kinoite-plasmalogin-workaround
Before=plasmalogin.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/fedora-kinoite-plasmalogin-workaround

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/libexec/fedora-kinoite-plasmalogin-workaround << 'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "Checking plasmalogin entries in /etc/shadow & /etc/gshadow"

if [[ $(grep -c "plasmalogin" "/etc/shadow") -eq 0 ]]; then
    echo "plasmalogin:!*:::::::" >> "/etc/shadow"
    echo "Added missing plasmalogin entry to /etc/shadow"
else
    echo "Nothing to do for /etc/shadow"
fi

if [[ $(grep -c "plasmalogin" "/etc/gshadow") -eq 0 ]]; then
    echo "plasmalogin:!*::" >> "/etc/gshadow"
    echo "Added missing plasmalogin entry to /etc/gshadow"
else
    echo "Nothing to do for /etc/gshadow"
fi

echo "Writing stamp file: /etc/.fedora-kinoite-plasmalogin-workaround"
touch /etc/.fedora-kinoite-plasmalogin-workaround
SCRIPT

chmod a+x /usr/libexec/fedora-kinoite-plasmalogin-workaround

cat >> /usr/lib/systemd/system-preset/35-security-desktop.preset << 'EOF'

# Plasmalogin workaround (from Kinoite)
enable fedora-kinoite-plasmalogin-workaround.service
EOF

systemctl preset fedora-kinoite-plasmalogin-workaround.service

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

# Shell padrão para novos utilizadores: zsh (evita chsh no primeiro login)
sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd

# First-boot user services
mkdir -p /etc/skel/.config/systemd/user/timers.target.wants

for script in fedora-flatpak-setup fedora-shell-setup fedora-dev-setup fedora-brew-setup; do
    install -Dm644 /ctx/skel/.config/systemd/user/"${script}".service \
        /etc/skel/.config/systemd/user/"${script}".service
    install -Dm644 /ctx/skel/.config/systemd/user/"${script}".timer \
        /etc/skel/.config/systemd/user/"${script}".timer
    ln -sf ../"${script}".timer \
        /etc/skel/.config/systemd/user/timers.target.wants/"${script}".timer
done

install -Dm755 /ctx/skel/.local/bin/kwin-vm-compat.sh \
    /usr/libexec/kwin-vm-compat.sh
install -Dm644 /ctx/skel/.config/autostart/kwin-vm-compat.desktop \
    /etc/xdg/autostart/kwin-vm-compat.desktop

install -Dm644 /ctx/skel/.config/plasma-org.kde.plasma.desktop-appletsrc \
    /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc

rm -rf /usr/share/plasma/look-and-feel/Mokka/contents/layouts

kwriteconfig6 --file /etc/skel/.config/krunnerrc \
    --group General --key FreeFloating "true"

sed -i 's/\bsizes\b/size/g' \
    /usr/share/plasma/look-and-feel/Mokka/contents/splash/Splash.qml

sed -i 's/^Theme=Catppuccin-Mocha-Mauve-splash$/Theme=Mokka/' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

sed -i 's|^Image=file:///usr/share/wallpapers/garuda-mokka/Mokka-tree\.jpg$|Image=file:///usr/share/wallpapers/Mokka-tree/|' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

kwriteconfig6 --file /etc/skel/.config/ksplashrc \
    --group KSplash --key Theme "Mokka"

touch /etc/plasma-setup-done

kwriteconfig6 --file /etc/skel/.config/plasma-welcomerc \
    --group General --key ShowOnStartup "false"
kwriteconfig6 --file /etc/skel/.config/plasma-welcomerc \
    --group General --key LastSeenVersion "99.0"

setfattr -n user.component -v "skel" \
    /usr/libexec/fedora-flatpak-setup \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup
setfattr -n user.update-interval -v "monthly" \
    /usr/libexec/fedora-flatpak-setup \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup

# ── Tema Mokka ────────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/plasmarc \
    --group Theme --key name "Mokka"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key ColorScheme "Mokka"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group KDE --key LookAndFeelPackage "Mokka"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group KDE --key widgetStyle "kvantum-dark"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group Icons --key Theme "Tela-circle-dracula-dark"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key fixed "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key font "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key menuFont "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key toolBarFont "JetBrains Mono,10,-1,5,75,0,0,0,0,0"

kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group Mouse --key cursorTheme "catppuccin-mocha-mauve-cursors"
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group "Libinput" --group "default" --key NaturalScroll "true"
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group "Libinput" --group "default" --key PointerAcceleration "0.45"

# ── KWin ──────────────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key library "org.kde.kwin.aurorae"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key theme "__aurorae__svg__CatppuccinMocha-Classic"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key ButtonsOnLeft ""
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key ButtonsOnRight "IAX"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key blurEnabled "true"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key roundcornersEnabled "true"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key kwin4_effect_roundcornersEnabled "true"

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

# ── Lock screen ───────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --key Theme --delete 2>/dev/null || true
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --key WallpaperPlugin "org.kde.image"
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --group Wallpaper --group "org.kde.image" --group General \
    --key Image "file:///usr/share/wallpapers/Mokka-tree/"

# ── GTK themes ────────────────────────────────────────────────────────────────
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
    --group "AC" --group "SuspendAndShutdown" --key AutoSuspendAction "1"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "AC" --group "SuspendAndShutdown" --key AutoSuspendIdleTimeoutSec "1800"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "Battery" --group "Performance" --key PowerProfile "power-saver"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "Battery" --group "SuspendAndShutdown" --key AutoSuspendAction "1"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "Battery" --group "SuspendAndShutdown" --key AutoSuspendIdleTimeoutSec "1200"
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
if rpm -q scx-scheds &>/dev/null; then
    install -Dm644 /ctx/configs/scx-default.conf /etc/default/scx
    setfattr -n user.component -v "image-config" /etc/default/scx
    systemctl enable scx.service
fi

systemctl enable thermald.service irqbalance.service
systemctl enable systemd-oomd
# bolt e fwupd são D-Bus/udev-activated; o enable não é necessário (nem funciona no container)
systemctl preset power-profiles-daemon.service 2>/dev/null || true

mkdir -p /etc/tuned
echo "balanced" > /etc/tuned/active_profile
echo "auto" > /etc/tuned/profile_mode

if command -v authselect >/dev/null 2>&1; then
    authselect current --raw &>/dev/null || authselect select minimal --force
    authselect enable-feature with-fingerprint || true
    authselect enable-feature with-faillock || true
fi

install -d /usr/share/flatpak
curl -L --fail --retry 3 --retry-delay 5 \
    -o /usr/share/flatpak/flathub.flatpakrepo \
    https://flathub.org/repo/flathub.flatpakrepo
echo "::endgroup::"

# ─── SELinux CIL policies (socket denial + user namespace hardening) ─────────
echo "::group:: SELinux CIL policies"
CIL_FILES=(
    /ctx/selinux/secureblue_socket_utils.cil
    /ctx/selinux/secureblue_deny_ipsec_sockets.cil
    /ctx/selinux/secureblue_deny_obscure_sockets.cil
    /ctx/selinux/secureblue_deny_alg_sockets.cil
    /ctx/selinux/secureblue_deny_packet_radio_sockets.cil
    /ctx/selinux/container-ptrace.cil
    /ctx/selinux/harden_userns.cil
    /ctx/selinux/harden_container_userns.cil
    /ctx/selinux/grant_userns.cil
    /ctx/selinux/userns_deny_unconfined_relabels.cil
)
# Instalados com prioridade 300 (>200 dos pacotes RPM, <400 do admin local)
semodule -v -X 300 -i "${CIL_FILES[@]}"
# SELinux booleans: nega ptrace via MAC (camada adicional ao Yama ptrace_scope=2)
# container_allow_ptrace é definido no container-ptrace.cil acima
setsebool -P deny_ptrace=on container_allow_ptrace=off || \
    echo "WARN: setsebool falhou (SELinux não activo no build container; booleans aplicados no arranque)"
restorecon -FRv /usr 2>/dev/null || true
echo "::endgroup::"

# ─── SUID removal ─────────────────────────────────────────────────────────────
echo "::group:: SUID removal"
# Strip SUID/SGID de todos os binários em /usr excepto sudo (KDE/kdesu precisa)
find /usr -type f -perm /6000 -print0 | while IFS= read -r -d '' binary; do
    case "$binary" in
        /usr/bin/sudo|/usr/bin/su) continue ;;
        *) chmod ug-s "$binary" && echo "Stripped: $binary" ;;
    esac
done
# Remover binários desnecessários com histórico de vulnerabilidades SUID
rm -f /usr/bin/chsh /usr/bin/chfn /usr/bin/pkexec
# Substituir SUID por capabilities mínimas onde necessário
setcap cap_sys_admin=ep /usr/bin/fusermount3 2>/dev/null \
    || echo "WARN: setcap fusermount3 falhou"
setcap cap_dac_read_search,cap_audit_write=ep /usr/sbin/unix_chkpwd 2>/dev/null \
    || echo "WARN: setcap unix_chkpwd falhou"
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
echo "::group:: Initramfs"
# shellcheck disable=SC2012  # nomes de versão de kernel são seguros para ls
KVER=$(ls /usr/lib/modules | sort -V | tail -1)
INITRAMFS="/usr/lib/modules/$KVER/initramfs.img"

depmod "$KVER" 2>/dev/null || true
dracut --force --no-hostonly --force-drivers " virtio_gpu " --kver "$KVER" "$INITRAMFS"
[[ -s "$INITRAMFS" ]] || { echo "FATAL: initramfs vazio após dracut: $INITRAMFS"; exit 1; }

INITRD_MODS=$(lsinitrd --mod "$INITRAMFS" 2>/dev/null)
printf '%s\n' "$INITRD_MODS" | grep -qE '^[[:space:]]*(50)?ostree[[:space:]]*$' \
    || { echo "FATAL: módulo ostree ausente no initramfs regenerado!"; exit 1; }
echo "✓ ostree presente no initramfs"
if lsinitrd "$INITRAMFS" 2>/dev/null | grep -qiE 'virtio.gpu\.ko'; then
    echo "✓ virtio_gpu presente no initramfs"
else
    echo "WARN: virtio_gpu não entrou no initramfs — Plymouth pode não aparecer em VM (HW real ok)"
fi
echo "::endgroup::"

# ─── Cleanup final ────────────────────────────────────────────────────────────
echo "::group:: Cleanup"
dnf5 clean all
rm -rf /var/cache/dnf /var/log/dnf* /var/log/hawkey*
rm -rf /run/* /tmp/* 2>/dev/null || true
rm -rf /var/lib/dnf/repos /var/lib/dnf/*.lock 2>/dev/null || true
rm -rf /var/lib/flatpak 2>/dev/null || true
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
LOCALE_REMOVED=0
while IFS= read -r -d '' dir; do
    rm -rf "$dir" && ((++LOCALE_REMOVED))
done < <(find /usr/share/locale -mindepth 1 -maxdepth 1 \
    ! -name 'pt_BR' ! -name 'en_US' ! -name 'locale.alias' \
    -print0)
echo "Locales removidos: $LOCALE_REMOVED (mantidos: pt_BR, en_US)"
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
