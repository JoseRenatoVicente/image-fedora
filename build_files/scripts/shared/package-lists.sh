# shellcheck shell=bash
# package-lists.sh — Fonte única de verdade para as listas de pacotes.
# Sourced (não executado) por:
#   • build-packages.sh           — instalação/remoção (Layer 1)
#   • configure/70-build-deps.sh  — remoção das build deps (Layer 2)
#   • shared/tests.sh             — verificação de presença/ausência
#   • tests/source/package_sync.bats — verificação de consistência das listas
# Sem shebang nem +x. Só define arrays; nenhum efeito colateral.
# shellcheck disable=SC2034  # arrays consumidos por quem faz source
#
# NOTA: este ficheiro faz parte da chave de cache do Layer 1 — ver Containerfile
# (stage ctx-pkgs). Alterá-lo re-corre o dnf install, como deve ser.

# ── Bloat da base-atomic a remover ───────────────────────────────────────────
REMOVE_PACKAGES=(
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
    # ModemManager: sem modem celular neste hardware — removido (serviço também mascarado)
    ModemManager

    # Outros
    hunspell sos fpaste words pinfo lrzsz kmscon

    # ── Bloat órfão da base-atomic (confirmado: nada requer) ~650 MB ──
    # qt6-qtwebengine: 290 MB (Chromium embutido, nenhum app daqui exige).
    # python3-botocore: SDK AWS (sem uso). nodejs*: Node é via nvm em runtime.
    # openblas-openmp: backend BLAS órfão. buildah: usamos podman (distrobox
    # não precisa). NÃO incluir skopeo — é exigido por bootc + rpm-ostree.
    qt6-qtwebengine
    python3-botocore
    nodejs nodejs22-libs nodejs22-docs nodejs22-full-i18n npm
    openblas-openmp
    buildah

    # ── Fontes/IME desnecessários em pt_BR (~240 MB) ──
    # Fontes CJK (chinês/japonês/coreano) + serif latino (não usado na UI) e
    # dados de IME órfãos (já removemos os ibus-* correspondentes).
    google-noto-sans-cjk-vf-fonts google-noto-serif-cjk-vf-fonts
    google-noto-sans-mono-cjk-vf-fonts google-noto-serif-fonts
    libpinyin-data anthy-unicode

    # ── ibus + Unicode DB (~197 MB) ──
    # ibus é exigido só por ibus-setup (removido junto). KDE/Plasma não precisa
    # de ibus para digitação Latin (XKB). Perde-se IME CJK / emoji-via-ibus —
    # irrelevante em pt_BR. unicode-ucd é órfão (nada o requer).
    ibus ibus-setup ibus-libs ibus-gtk2 ibus-gtk3 ibus-gtk4 ibus-data
    unicode-ucd
)

# ── Excludes da transação de install ─────────────────────────────────────────
INSTALL_EXCLUDES=(
    PackageKit
    PackageKit-glib
    plasma-discover-offline-updates
    plasma-discover-packagekit
    plasma-pk-updates
    tracker
    tracker-miners
    localsearch
    tinysparql
    plasma-x11
    plasma-workspace-x11
    mariadb-server-utils
    qt5-qtbase
    kde-connect
    firefox
    orca
    speech-dispatcher
    plasma-discover
    power-profiles-daemon
    nvidia-gpu-firmware
    xorg-x11-drv-nvidia
    akmod-nvidia
    kmod-nvidia
)

# ── Pacotes Fedora a instalar ────────────────────────────────────────────────
INSTALL_PACKAGES=(
    # dnf5-plugins (necessário para copr_install_isolated)
    dnf5-plugins

    # ── KDE Plasma (mínimo) ───────────────────────────────────────────────────
    # Core desktop
    plasma-desktop plasma-workspace kwin kscreenlocker kscreen
    plasma-login-manager kde-settings-plasmalogin kcm-plasmalogin
    # Painel e rede. Evitar kdeplasma-addons: puxa qt6-qtwebengine.
    plasma-pa plasma-nm plasma-nm-openvpn
    bluedevil polkit-kde plasma-drkonqi kinfocenter plasma-systemmonitor
    # Integração
    kde-gtk-config flatpak-kcm kio-admin pam-kwallet pinentry-qt
    libappindicator-gtk3
    # File manager e utilitários
    dolphin konsole kwrite ark kdialog
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

    # ── Ferramentas do utilizador ─────────────────────────────────────────────
    # Dev tools (git-core já vem na base-atomic; full git entra via git-credential-libsecret)
    curl unzip tar jq make gettext
    # CLI tools
    bat btop fd-find ripgrep fastfetch eza
    neovim
    inotify-tools xsel numlockx
    util-linux-user zsh
    # Zsh: plugins via RPM (sistema), prompt via starship; zoxide/direnv/fzf
    zsh-autosuggestions zsh-syntax-highlighting
    zoxide fzf direnv
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
    # Auditoria (CIS §6.3): auditd + augenrules. Regras em /etc/audit/rules.d/.
    audit

    # Dell/Intel laptop support
    fprintd fprintd-pam libfprint
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
    solaar-udev
    # Security keys (U2F / YubiKey)
    pam-u2f pam_yubico pamu2fcfg yubikey-manager
    # USB device authorization (defesa BadUSB). Serviço NÃO é habilitado por
    # padrão: política vazia bloquearia teclado/rato no boot. Para ativar:
    #   sudo usbguard generate-policy > /etc/usbguard/rules.conf
    #   sudo systemctl enable --now usbguard.service
    usbguard
    # FDE: LUKS2 + TPM2 + Secure Boot. cryptsetup já costuma vir na base, mas
    # explicitamos. tpm2-tools p/ inspeção de PCRs; mokutil p/ verificar estado
    # do Secure Boot. systemd-cryptenroll já vem com o systemd. Enroll real é
    # pós-install: ver /usr/bin/tpm2-luks-enroll.
    cryptsetup tpm2-tools mokutil
)

# ── Build deps (instaladas no Layer 1, removidas no Layer 2 70-build-deps.sh) ─
# Lista única partilhada entre a instalação e a remoção. cpp/gcc são deps de
# gcc-c++ mas são listados explicitamente para remoção garantida.
BUILD_DEPS=(
    gcc-c++ cpp gcc
    cmake extra-cmake-modules
    libplasma-devel
    kf6-kcoreaddons-devel kf6-kirigami-devel kf6-kpackage-devel kf6-kwindowsystem-devel
    libsass sassc
    rsync
)

# ── Verificação runtime: pacotes que DEVEM estar presentes ───────────────────
# Inclui dependências transitivas (pipewire, wireplumber) que não estão em
# INSTALL_PACKAGES mas têm de acabar instaladas.
REQUIRED_PACKAGES=(
    distrobox
    earlyoom
    fastfetch
    ffmpeg
    firewalld
    gamemode
    git-credential-libsecret
    zsh-autosuggestions
    zsh-syntax-highlighting
    zoxide
    kitty
    ksshaskpass
    ksystemlog
    kwin-effect-roundcorners
    lm_sensors
    neovim
    nvtop
    pam-u2f
    plasma-firewall
    podman-docker
    tuned
    # Dell/Intel laptop support
    fprintd
    fprintd-pam
    libfprint
    bolt
    iio-sensor-proxy
    thermald
    irqbalance
    tuned-ppd
    alsa-sof-firmware
    alsa-ucm
    pipewire
    wireplumber
    fwupd
    libsmbios
    dmidecode
    yubikey-manager
    usbguard
    cryptsetup
    tpm2-tools
    mokutil
    zsh
    audit
)

# ── Verificação runtime: pacotes KDE essenciais ──────────────────────────────
KDE_REQUIRED=(
    plasma-desktop
    plasma-workspace
    kwin
    plasma-login-manager
    dolphin
    konsole
)

# ── Verificação runtime: pacotes que DEVEM estar ausentes ────────────────────
UNWANTED_PACKAGES=(
    code
    firefox
    # Impressoras (removidas da base-atomic)
    cups hplip gutenprint
    # Acessibilidade (removida)
    orca brltty speech-dispatcher
    # Firmware não-Intel (removido)
    amd-gpu-firmware
    # Power stack conflicts / NVIDIA out of scope
    power-profiles-daemon
    nvidia-gpu-firmware
    xorg-x11-drv-nvidia
    akmod-nvidia
    kmod-nvidia
    nvidia-driver
    # VM guest agents (removidos)
    open-vm-tools-desktop virtualbox-guest-additions
    # ModemManager removido (sem modem celular; serviço mascarado)
    ModemManager
    # input-remapper substituído por keyd
    input-remapper
    # KDE bloat que não deve estar presente
    plasma-discover
    plasma-workspace-wallpapers
    kde-connect
    akonadi-server
    mariadb-server
    # Bloat órfão removido por tamanho (~650 MB) — regressão se voltar
    qt6-qtwebengine
    python3-botocore
    nodejs22-libs
    openblas-openmp
    buildah
    ibus
    unicode-ucd
)
