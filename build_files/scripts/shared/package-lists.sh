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

    # NOTA: firmwares wireless e GPU são mantidos. A remoção anterior quebrava
    # WiFi (Realtek/Atheros/MediaTek/Broadcom) e causava stalls gráficos em
    # GPUs AMD/NVIDIA. Custo de tamanho aceitável para funcionamento geral.

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
    # irqbalance: serviço mascarado em 50-services.sh; sem o pacote da base o
    # mascaramento seria peso morto para um binário nunca executado
    irqbalance

    # Outros
    sos fpaste words pinfo lrzsz kmscon

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

    # ── Bloat órfão adicional da base-atomic (~380 MB) ──
    # Confirmado ao vivo via `rpm -q --whatrequires` (nenhum pacote instalado
    # exige estes) e `ldd` (nenhum binário/lib faz link em runtime).
    #
    # clang-libs: órfão puro. llvm-libs (que ele exige) NÃO entra aqui —
    # libvulkan_radeon.so (RADV) faz link direto a libLLVM.so em runtime sem
    # Requires declarado no RPM; removê-lo quebraria Vulkan em GPU AMD.
    clang-libs
    # binutils/libstdc++-devel: sobra da remoção de gcc/gcc-c++ (BUILD_DEPS) —
    # sem compilador instalado, ferramentas/headers ficam inúteis.
    binutils libstdc++-devel
    # qt6-doc-devel/doxygen: sobra do toolchain de docs dos pacotes -devel do
    # KF6 (BUILD_DEPS); nada os exige depois da remoção do toolchain.
    qt6-doc-devel doxygen
    # vulkan-headers/vulkan-loader-devel: headers de desenvolvimento Vulkan;
    # vulkan-tools (runtime, mantido) não precisa deles.
    vulkan-headers vulkan-loader-devel
    # libgs + adobe-mappings-cmap(-deprecated): sobra da stack de impressão já
    # removida (cups-filters etc.). Confirmado: poppler/Okular não dependem de
    # ghostscript para renderizar PDF.
    libgs adobe-mappings-cmap adobe-mappings-cmap-deprecated
    # espeak-ng/flite/lpcnetfreedv: removidos aqui porque no base-atomic ainda
    # não há nada a exigi-los. flite e lpcnetfreedv voltam depois do
    # INSTALL_PACKAGES como hard-deps do ffmpeg-free (libflite.so por soname;
    # codec2 Requires lpcnetfreedv) — ver nota junto a UNWANTED_PACKAGES, não
    # são removidos de novo no Layer 2. espeak-ng não tem esse problema e fica
    # fora da imagem final.
    espeak-ng flite lpcnetfreedv
)

# ── Excludes da transação de install ─────────────────────────────────────────
INSTALL_EXCLUDES=(
    PackageKit
    PackageKit-glib
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
    power-profiles-daemon
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
    # Painel e rede. kdeplasma-addons exclui-se: hard-dep em qt6-qtwebengine (290 MB).
    # O kameleon kded (accent color dinâmico) vem do kdeplasma-addons; sem ele o
    # plasma_accentcolor_service usa AccentColor fixo do skel — kded6rc desativa autoload.
    plasma-pa plasma-nm plasma-nm-openvpn
    # plasma-drkonqi excluído de propósito: coredumps estão desativados em 3
    # camadas (DumpCore=no em system/user.conf.d, limits core 0, Storage=none
    # em coredump.conf.d — ver política NSA/STIG contra exposição de dados
    # sensíveis em cores). Sem coredump, o DrKonqi nunca é invocado; instalar
    # o pacote seria peso morto que contradiz a própria política.
    bluedevil polkit-kde kinfocenter plasma-systemmonitor
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
    # Pesquisa/Overview kwin: org.kde.milou QML module
    plasma-milou
    vulkan-tools mobile-broadband-provider-info NetworkManager-ppp

    # ── Ferramentas do utilizador ─────────────────────────────────────────────
    # Dev tools (git-core já vem na base-atomic; full git entra via git-credential-libsecret)
    curl unzip tar jq make gettext android-tools
    # CLI tools
    bat btop fd-find ripgrep fastfetch eza
    neovim
    inotify-tools xsel numlockx
    util-linux-user zsh fish
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
    # Dicionários / verificação ortográfica
    hunspell hunspell-pt-BR
    # Gaming
    gamemode
    # SCX scheduler: instalado em best-effort separado em build-packages.sh
    # (pode não estar disponível em todos os snapshots de repo Fedora)
    # Sistema
    tuned tuned-ppd
    zram-generator
    # Auditoria (CIS §6.3): auditd + augenrules. Regras em /etc/audit/rules.d/.
    audit

    # Dell/Intel laptop support. irqbalance de propósito fora: o serviço é
    # mascarado em 50-services.sh (scheduling de IRQ manual/scx nesta imagem),
    # e sem o serviço o pacote é só peso morto.
    fprintd fprintd-pam libfprint
    bolt iio-sensor-proxy
    thermald
    alsa-sof-firmware alsa-ucm
    fwupd
    libsmbios dmidecode
    # Containers
    podman-docker podman-compose
    # WinApps / KVM: backend libvirt para integração de apps Windows via RDP
    freerdp libvirt qemu-kvm virt-manager dialog
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
    # systemd-boot (para migração opt-in via sd-boot-migrate, ver
    # /usr/libexec/sd-boot-migrate). "-unsigned": os binários EFI só arrancam
    # sob Secure Boot depois de assinados com a MOK do projeto — ver
    # 65-secureboot-sign.sh. Sem a assinatura, o migrate script recusa-se a
    # instalar (evita meter um bootloader não confiável no boot order).
    systemd-boot-unsigned
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
    # sbsign (assinatura Secure Boot do systemd-boot em 65-secureboot-sign.sh).
    # Só necessário durante o build; removido daqui como os outros build deps.
    sbsigntools
)

# ── Verificação runtime: pacotes que DEVEM estar presentes ───────────────────
# Inclui dependências transitivas (pipewire, wireplumber) que não estão em
# INSTALL_PACKAGES mas têm de acabar instaladas.
REQUIRED_PACKAGES=(
    fastfetch
    ffmpeg
    firewalld
    gamemode
    git-credential-libsecret
    zsh-autosuggestions
    zsh-syntax-highlighting
    zoxide
    android-tools
    kitty
    ksshaskpass
    ksystemlog
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
    systemd-boot-unsigned
    hardened_malloc
    zsh
    fish
    freerdp
    libvirt
    qemu-kvm
    hunspell-pt-BR
    audit
    # KDE pesquisa/Overview (kwin): org.kde.milou QML module
    plasma-milou
    # SCX scheduler: best-effort (ver build-packages.sh); ausência não é falha
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
    # Power stack conflicts / NVIDIA out of scope
    power-profiles-daemon
    xorg-x11-drv-nvidia
    akmod-nvidia
    kmod-nvidia
    nvidia-driver
    # VM guest agents (removidos)
    open-vm-tools-desktop virtualbox-guest-additions
    # ModemManager removido (sem modem celular; serviço mascarado)
    ModemManager
    # irqbalance removido (serviço mascarado; pacote seria peso morto)
    irqbalance
    # plasma-drkonqi removido (coredumps desativados; nunca seria invocado)
    plasma-drkonqi
    # input-remapper substituído por keyd
    input-remapper
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
    # Bloat órfão adicional (~380 MB) — regressão se voltar
    clang-libs
    binutils
    libstdc++-devel
    qt6-doc-devel
    doxygen
    vulkan-headers
    vulkan-loader-devel
    libgs
    espeak-ng
    # NOTA: flite e lpcnetfreedv NÃO estão aqui (ver 70-build-deps.sh). Ambos
    # reaparecem depois do INSTALL_PACKAGES como hard-deps do build ffmpeg-free/
    # libavcodec-free do Fedora — ffmpeg-free liga-se a libflite.so (dependência
    # por soname, invisível a `rpm -q --whatrequires flite`) e codec2 tem
    # hard-Requires em lpcnetfreedv. ffmpeg-free é exigido por kpipewire/
    # qt6-qtmultimedia/ffmpegthumbs, centrais do stack Plasma (screen recording,
    # thumbnails, media). Testado ao vivo: remover qualquer um dos dois arrasta
    # plasma-desktop/plasma-workspace/kwin/dolphin/ffmpeg-free. Mantê-los é o
    # trade-off aceite.
)
