#!/bin/bash
# Layer 1 — pacotes dnf + COPR
# Ficheiros necessários: /ctx-pkgs/{build-packages.sh,shared/copr-helpers.sh,configs/dnf-performance.conf}
# Cache invalidado apenas quando a lista de pacotes ou os helpers mudam.
set -euo pipefail

trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# shellcheck source=shared/copr-helpers.sh
source /ctx-pkgs/shared/copr-helpers.sh

# ─── Setup ────────────────────────────────────────────────────────────────────
echo "::group:: Setup"
install -Dm644 /ctx-pkgs/configs/dnf-performance.conf /etc/dnf/conf.d/performance.conf
# Garante que o módulo ostree fica em TODOS os initramfs gerados durante o build,
# incluindo os disparados por scripts de pacotes — sem isto o initrd-switch-root
# falha porque ostree-prepare-root.service está ausente do initrd.
echo 'add_dracutmodules+=" ostree "' > /etc/dracut.conf.d/01-ostree-required.conf
echo "::endgroup::"

# ─── Remove base-atomic bloat ─────────────────────────────────────────────────
echo "::group:: Remove base-atomic bloat"

# Substituir glibc-all-langpacks por langpacks mínimos (pt_BR + en_US).
# Deve ser feito ANTES da remoção em massa porque glibc exige pelo menos um
# glibc-langpack — remover glibc-all-langpacks sem alternativa falha o resolver.
dnf5 install -y --allowerasing glibc-langpack-pt glibc-langpack-en
dnf5 remove -y glibc-all-langpacks

REMOVE_PKGS=(
    # Impressoras (~124 MB)
    cups cups-browsed cups-filters hplip
    gutenprint gutenprint-cups bluez-cups
    system-config-printer-udev
    c2esp dymo-cups-drivers printer-driver-brlaser ptouch-driver splix
    mpage paps

    # Acessibilidade (~121 MB)
    orca brltty speech-dispatcher

    # Firmware não-Intel (~224 MB)
    nvidia-gpu-firmware amd-gpu-firmware amd-ucode-firmware
    atheros-firmware mt7xxx-firmware realtek-firmware
    brcmfmac-firmware libertas-firmware tiwilink-firmware
    nxpwireless-firmware b43-fwcutter b43-openfwwf
    qcom-wwan-firmware

    # Fontes desnecessárias
    default-fonts-cjk-mono default-fonts-cjk-sans default-fonts-cjk-serif
    cldr-emoji-annotation

    # IBus / input methods asiáticos (~160 MB)
    ibus-anthy ibus-chewing ibus-hangul
    ibus-libpinyin ibus-m17n ibus-typing-booster

    # Firefox (vem na base-atomic, não é usado — substituído por flatpak)
    firefox firefox-langpacks

    # VM guest agents / virtualização (~50 MB)
    open-vm-tools-desktop spice-vdagent spice-webdavd
    hyperv-daemons qemu-guest-agent virtualbox-guest-additions

    # Serviços de rede não utilizados
    nfs-utils cifs-utils samba-client
    sssd-common sssd-kcm

    # Outros
    hunspell sos fpaste words pinfo lrzsz kmscon
)
FOUND_PKGS=()
for pkg in "${REMOVE_PKGS[@]}"; do
    rpm -q "$pkg" &>/dev/null && FOUND_PKGS+=("$pkg")
done
if [[ ${#FOUND_PKGS[@]} -gt 0 ]]; then
    dnf5 remove -y --setopt=clean_requirements_on_remove=False "${FOUND_PKGS[@]}"
    echo "Removidos ${#FOUND_PKGS[@]} pacotes: ${FOUND_PKGS[*]}"
else
    echo "Nenhum pacote de bloat encontrado."
fi
echo "::endgroup::"

# ─── Install Fedora packages ──────────────────────────────────────────────────
echo "::group:: Install packages"
PACKAGES=(
    # dnf5-plugins (necessário para copr_install_isolated abaixo)
    dnf5-plugins

    # ── KDE Plasma (mínimo) ───────────────────────────────────────────────────
    # Core desktop
    plasma-desktop plasma-workspace kwin kscreenlocker kscreen
    plasma-login-manager kde-settings-plasmalogin kcm-plasmalogin
    # Painel e widgets
    kdeplasma-addons plasma-pa plasma-nm plasma-nm-openvpn
    bluedevil polkit-kde plasma-drkonqi kinfocenter plasma-systemmonitor
    # Integração
    kde-gtk-config flatpak-kcm kio-admin pam-kwallet pinentry-qt
    libappindicator-gtk3
    # File manager e utilitários
    dolphin kio-gdrive konsole kwrite spectacle ark kdialog
    ffmpegthumbs kdegraphics-thumbnailers audiocd-kio kamera
    # Display
    xorg-x11-server-Xwayland xwaylandvideobridge
    mesa-dri-drivers mesa-vulkan-drivers libva-intel-media-driver
    # Portais
    xdg-desktop-portal xdg-desktop-portal-kde
    # Temas fallback
    plasma-breeze breeze-icon-theme aurorae
    # Extras Kinoite
    plasma-keyboard
    vulkan-tools mobile-broadband-provider-info NetworkManager-ppp
    plymouth-system-theme

    # ── Ferramentas do utilizador ─────────────────────────────────────────────
    # Dev tools (git-core já vem na base-atomic; full git entra via git-credential-libsecret)
    curl unzip tar jq make gettext
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

    # Dell/Intel laptop support
    fprintd libfprint
    bolt iio-sensor-proxy irqbalance
    thermald
    alsa-sof-firmware alsa-ucm
    fwupd
    libsmbios dmidecode
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
    # Build deps (removidos no passo cleanup do build-configure.sh)
    gcc-c++ cmake extra-cmake-modules libplasma-devel
    kf6-kcoreaddons-devel kf6-kirigami-devel kf6-kpackage-devel kf6-kwindowsystem-devel
    rsync libsass sassc
)
dnf5 install -y --allowerasing \
    --exclude=PackageKit \
    --exclude=PackageKit-glib \
    --exclude=plasma-discover-offline-updates \
    --exclude=plasma-discover-packagekit \
    --exclude=plasma-pk-updates \
    --exclude=tracker \
    --exclude=tracker-miners \
    --exclude=localsearch \
    --exclude=tinysparql \
    --exclude=plasma-x11 \
    --exclude=plasma-workspace-x11 \
    --exclude=mariadb-server-utils \
    --exclude=qt5-qtbase \
    --exclude=kde-connect \
    --exclude=firefox \
    --exclude=orca \
    --exclude=speech-dispatcher \
    --exclude=plasma-discover \
    --exclude=power-profiles-daemon \
    --exclude=nvidia-gpu-firmware \
    --exclude=xorg-x11-drv-nvidia \
    --exclude=akmod-nvidia \
    --exclude=kmod-nvidia \
    "${PACKAGES[@]}"
echo "::endgroup::"

# ─── COPR packages (isolados) ────────────────────────────────────────────────
echo "::group:: COPR packages"
# kwin-effect-roundcorners não está nos repos Fedora
copr_install_isolated "matinlotfali/KDE-Rounded-Corners" \
    kwin-effect-roundcorners kwin-effect-roundcorners-x11 \
    || echo "WARN: kwin-effect-roundcorners não instalado"
# scx-scheds não está nos repos padrão do Fedora (disponível via COPR sched_ext)
copr_install_isolated "sched_ext/scx" \
    scx-scheds \
    || echo "WARN: scx-scheds não instalado"
echo "::endgroup::"
