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
    ModemManager

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

    # ── COSMIC Desktop (System76) ─────────────────────────────────────────────
    # Lista explícita do ambiente (NÃO usamos o grupo cosmic-desktop-environment:
    # é o grupo da spin oficial e arrasta firefox/cups/firmware/guest-agents/a11y,
    # exactamente o bloat que esta imagem remove). cosmic-initial-setup (OOBE) e
    # cosmic-player ficam de fora de propósito.
    cosmic-session cosmic-comp cosmic-settings cosmic-settings-daemon
    cosmic-panel cosmic-applets cosmic-launcher cosmic-app-library
    cosmic-bg cosmic-osd cosmic-notifications cosmic-idle cosmic-randr
    cosmic-workspaces cosmic-icon-theme cosmic-wallpapers
    # NOTA: cosmic-config-fedora NÃO é instalado — é um meta de "defaults" do
    # Fedora que arrasta ~300 pacotes (firefox, plasma-breeze, cups, firmware…),
    # exactamente o bloat que removemos. Os nossos defaults vêm do skel.
    # Apps COSMIC-native
    cosmic-files cosmic-term cosmic-edit cosmic-store cosmic-screenshot
    # Greeter (display manager baseado em greetd)
    cosmic-greeter
    # Portais
    xdg-desktop-portal xdg-desktop-portal-cosmic xdg-desktop-portal-gtk
    # GTK status icons (system tray) para apps legadas
    libappindicator-gtk3
    # Display / aceleração
    xorg-x11-server-Xwayland
    mesa-dri-drivers mesa-vulkan-drivers libva-intel-media-driver
    vulkan-tools mobile-broadband-provider-info NetworkManager-ppp
    NetworkManager-openvpn
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
    # systemd-oomd (via systemd-oomd-defaults): OOM killer baseado em PSI/cgroups v2,
    # substitui o earlyoom. Mata por pressão de memória real em vez de % de RAM livre.
    systemd-oomd-defaults
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
    # Git integration (credential helper via libsecret)
    git-credential-libsecret
    # Secret Service / keyring (substitui o pam-kwallet do KDE; necessário para
    # git-credential-libsecret e qualquer app que use libsecret)
    gnome-keyring
    # Hardware monitoring
    lm_sensors nvtop powertop
    # Shell prompt plugins (starship vem via install-assets.sh — não está nos repos)
    zsh-autosuggestions zsh-syntax-highlighting
    # Peripheral support (keyd vem via COPR abaixo — substitui o input-remapper)
    solaar-udev
    # Security keys (U2F / YubiKey)
    pam-u2f pam_yubico pamu2fcfg yubikey-manager
    # Build/asset deps (removidos no passo cleanup do build-configure.sh)
    # rsync: usado por install-assets.sh para copiar árvores de tema
    rsync
)
dnf5 install -y --allowerasing \
    --exclude=PackageKit \
    --exclude=PackageKit-glib \
    --exclude=tracker \
    --exclude=tracker-miners \
    --exclude=localsearch \
    --exclude=tinysparql \
    --exclude=mariadb-server-utils \
    --exclude=qt5-qtbase \
    --exclude=firefox \
    --exclude=orca \
    --exclude=speech-dispatcher \
    --exclude=power-profiles-daemon \
    --exclude=ModemManager \
    --exclude=nvidia-gpu-firmware \
    --exclude=xorg-x11-drv-nvidia \
    --exclude=akmod-nvidia \
    --exclude=kmod-nvidia \
    "${PACKAGES[@]}"

# Rede de segurança: re-remover o bloat que possa ter sido reintroduzido por
# weak-deps/recommends dos pacotes do desktop. Só remove o que existir e sem
# cascata (clean_requirements_on_remove=False) — nenhum destes é dependência
# forte do core COSMIC.
REINTRODUCED=()
for pkg in "${FOUND_PKGS[@]}"; do
    rpm -q "$pkg" &>/dev/null && REINTRODUCED+=("$pkg")
done
if [[ ${#REINTRODUCED[@]} -gt 0 ]]; then
    echo "Re-removendo bloat reintroduzido: ${REINTRODUCED[*]}"
    dnf5 remove -y --setopt=clean_requirements_on_remove=False "${REINTRODUCED[@]}"
fi
echo "::endgroup::"

# ─── COPR packages (isolados) ────────────────────────────────────────────────
echo "::group:: COPR packages"
# COSMIC faz cantos arredondados nativamente — o KDE-Rounded-Corners (KWin) deixa
# de ser necessário e foi removido na migração para COSMIC.
# scx-scheds não está nos repos padrão do Fedora (disponível via COPR sched_ext)
copr_install_isolated "sched_ext/scx" \
    scx-scheds \
    || echo "WARN: scx-scheds não instalado"
# keyd não está nos repos Fedora (substitui o input-remapper) — remapeamento de
# teclas por ficheiro de config, daemon leve sem GUI/Python.
copr_install_isolated "alternateved/keyd" \
    keyd \
    || echo "WARN: keyd não instalado"
echo "::endgroup::"
