#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -euo pipefail

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

echo "=== Pacotes obrigatórios ==="
REQUIRED_PACKAGES=(
    distrobox
    systemd-oomd-defaults
    fastfetch
    ffmpeg
    firewalld
    gamemode
    git-credential-libsecret
    zsh-autosuggestions
    zsh-syntax-highlighting
    kitty
    lm_sensors
    neovim
    nvtop
    pam-u2f
    podman-docker
    tuned
    # Dell/Intel laptop support
    fprintd
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
    zsh
)
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if [[ "$pkg" == "ffmpeg" ]]; then
        # Fedora repos ship 'ffmpeg-free'; RPM Fusion ships 'ffmpeg'. Accept either.
        rpm -q ffmpeg &>/dev/null || rpm -q ffmpeg-free &>/dev/null \
            || fail "Pacote ausente: ffmpeg (nem ffmpeg nem ffmpeg-free instalado)"
    else
        rpm -q "$pkg" > /dev/null 2>&1 || fail "Pacote ausente: $pkg"
    fi
done

echo "=== Pacotes COSMIC essenciais ==="
COSMIC_REQUIRED=(
    cosmic-comp
    cosmic-session
    cosmic-panel
    cosmic-settings
    cosmic-greeter
    cosmic-files
    cosmic-term
)
for pkg in "${COSMIC_REQUIRED[@]}"; do
    rpm -q "$pkg" > /dev/null 2>&1 || fail "Pacote COSMIC ausente: $pkg"
done

echo "=== Pacotes indesejados ==="
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
    ModemManager
    nvidia-gpu-firmware
    xorg-x11-drv-nvidia
    akmod-nvidia
    kmod-nvidia
    nvidia-driver
    # VM guest agents (removidos)
    open-vm-tools-desktop virtualbox-guest-additions
    # KDE/Plasma — removido por completo na migração para COSMIC
    plasma-desktop
    plasma-workspace
    kwin
    plasma-login-manager
    dolphin
    konsole
    kvantum
    kde-connect
    akonadi-server
    mariadb-server
)
for pkg in "${UNWANTED_PACKAGES[@]}"; do
    if rpm -q "$pkg" > /dev/null 2>&1; then
        fail "Pacote indesejado presente: $pkg"
    fi
done
[[ ! -e /etc/yum.repos.d/vscode.repo ]] \
    || fail "Repo VS Code não deve existir na imagem base: /etc/yum.repos.d/vscode.repo"

echo "=== sudo → run0 (alias) ==="
# Nota: o pacote sudo é mantido (alguns CLIs/docs assumem-no). Adicionamos run0 +
# alias interativo; o COSMIC usa polkit para elevação gráfica.
[[ -x /usr/bin/run0 ]] || fail "run0 ausente (deveria vir com o systemd)"
grep -q "alias sudo='run0'" /etc/profile.d/run0-alias.sh \
    || fail "alias sudo→run0 ausente em /etc/profile.d/run0-alias.sh"

echo "=== rpmfusion removido ==="
if compgen -G "/etc/yum.repos.d/rpmfusion-*.repo" > /dev/null; then
    fail "Repos rpmfusion ainda presentes: $(echo /etc/yum.repos.d/rpmfusion-*.repo)"
fi

echo "=== Serviços systemd ==="
REQUIRED_UNITS=(
    podman.socket
    tuned.service
    systemd-oomd.service
    firewalld.service
    chronyd.service
    flatpak-nuke-fedora.service
    flathub-system-setup.service
    cosmic-greeter.service
    thermald.service
    irqbalance.service
    rpm-ostreed-automatic.timer
    podman-auto-update.timer
)
# bolt e fwupd são ativados por D-Bus/udev — não têm WantedBy; presença verificada abaixo
for unit in bolt.service fwupd.service; do
    systemctl is-enabled "$unit" 2>/dev/null | grep -qE "^(enabled|static)$" \
        || fail "Serviço ausente ou mascarado: $unit"
done
for unit in "${REQUIRED_UNITS[@]}"; do
    systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$" \
        || fail "Serviço não habilitado: $unit"
done
for unit in \
    NetworkManager-wait-online.service \
    ModemManager.service \
    plymouth-quit-wait.service \
    avahi-daemon.service \
    avahi-daemon.socket; do
    [[ "$(readlink /etc/systemd/system/${unit} 2>/dev/null)" == "/dev/null" ]] \
        || fail "Serviço devia estar mascarado (boot speed): $unit"
done

echo "=== Dell/Intel laptop support ==="
systemctl list-unit-files fprintd.service &>/dev/null \
    || fail "fprintd.service ausente"
systemctl list-unit-files iio-sensor-proxy.service &>/dev/null \
    || fail "iio-sensor-proxy.service ausente"
systemctl list-unit-files tuned.service &>/dev/null \
    || fail "tuned.service ausente"
if systemctl list-unit-files power-profiles-daemon.service &>/dev/null; then
    fail "power-profiles-daemon não deve estar instalado; tuned-ppd é o provedor escolhido"
fi

echo "=== Fingerprint PAM ==="
if command -v authselect >/dev/null 2>&1; then
    authselect current 2>/dev/null | grep -qi 'fingerprint\|fprint' \
        || grep -Rqs 'pam_fprintd\.so' /etc/pam.d \
        || fail "PAM/authselect sem suporte fingerprint"
else
    grep -Rqs 'pam_fprintd\.so' /etc/pam.d \
        || fail "PAM sem pam_fprintd.so"
fi

echo "=== Intel SOF audio e Thunderbolt ==="
[[ -d /lib/firmware/intel/sof || -d /usr/lib/firmware/intel/sof ]] \
    || fail "Firmware Intel SOF ausente"
[[ -e /usr/lib/udev/rules.d/70-libfprint-2.rules || -e /usr/lib/udev/rules.d/60-libfprint-2.rules ]] \
    || fail "Regras udev do libfprint ausentes"
rpm -q bolt >/dev/null 2>&1 \
    || fail "bolt ausente para Thunderbolt/dock"

echo "=== fwupd e SMBIOS ==="
rpm -q fwupd >/dev/null 2>&1 \
    || fail "fwupd ausente"
rpm -q libsmbios >/dev/null 2>&1 \
    || fail "libsmbios ausente"
rpm -q dmidecode >/dev/null 2>&1 \
    || fail "dmidecode ausente"

echo "=== tuned perfil padrão ==="
grep -q 'balanced' /etc/tuned/active_profile 2>/dev/null \
    || fail "perfil tuned não é balanced; esperado para notebook Dell"

# flatpak-system-update.timer é opcional: não existe em todas as versões da base
if systemctl list-unit-files flatpak-system-update.timer &>/dev/null; then
    systemctl is-enabled flatpak-system-update.timer 2>/dev/null | grep -q "^enabled$" \
        || fail "Serviço não habilitado: flatpak-system-update.timer"
fi
# dconf-update.service é opcional: não existe em todas as versões da base
if systemctl list-unit-files dconf-update.service &>/dev/null; then
    systemctl is-enabled dconf-update.service 2>/dev/null | grep -q "^enabled$" \
        || fail "Serviço não habilitado: dconf-update.service"
fi

echo "=== Ficheiros obrigatórios ==="
REQUIRED_FILES=(
    /etc/sysctl.d/60-security-hardening.conf
    /etc/sysctl.d/99-performance.conf
    /usr/lib/bootc/kargs.d/10-hardening.toml
    /etc/dracut.conf.d/01-ostree-required.conf
    /etc/dracut.conf.d/02-drm-drivers.conf
    /etc/dracut.conf.d/99-omit-firewire.conf
    /etc/dracut.conf.d/98-omit-unused.conf
    /etc/dracut.conf.d/90-luks-security.conf
    /usr/libexec/fedora-flatpak-setup
    /usr/libexec/fedora-shell-setup
    /usr/libexec/fedora-dev-setup
    /usr/libexec/fedora-brew-setup
    /etc/selinux/config
    /etc/chrony.conf
    /etc/rpm-ostreed.conf
    /etc/systemd/zram-generator.conf
    /etc/systemd/system.conf.d/timeout.conf
    /etc/systemd/user.conf.d/timeout.conf
    /etc/security/limits.d/50-memlock.conf
    /etc/dnf/conf.d/no-weak-deps.conf
    /usr/lib/systemd/system/flatpak-nuke-fedora.service
    /usr/lib/systemd/system/flathub-system-setup.service
    /usr/share/flatpak/flathub.flatpakrepo
    /etc/keyd/default.conf
    /etc/systemd/oomd.conf.d/10-oomd.conf
    /etc/locale.conf
    /usr/bin/run0
    /etc/profile.d/run0-alias.sh
    /usr/lib/udev/rules.d/60-io-schedulers.rules
    /usr/lib/udev/rules.d/80-gpu-reset.rules
    /usr/lib/modules-load.d/wine-ntsync.conf
    /usr/share/dnf/plugins/copr.vendor.conf
    /usr/share/fonts/JetBrainsMonoNerdFont
    /usr/share/image-info.json
    /usr/share/wireplumber/wireplumber.conf.d/51-disable-suspension.conf
    /usr/bin/dnf
    /usr/lib/bootupd/grub2-static/configs.d/05_timeout.cfg
    # COSMIC skel: tema Mokka derivado + toolkit + wallpaper
    /etc/skel/.config/cosmic/com.system76.CosmicTheme.Dark/v1/accent
    /etc/skel/.config/cosmic/com.system76.CosmicTk/v1/interface_font
    /etc/skel/.config/cosmic/com.system76.CosmicBackground/v1/all
    /usr/share/backgrounds/mokka/Mokka-tree.jpg
    /usr/share/cosmic-mokka/theme-builder.ron
)
for f in "${REQUIRED_FILES[@]}"; do
    [[ -e "$f" ]] || fail "Ficheiro/directório ausente: $f"
done
# initramfs: determined dynamically from installed kernel version
KVER=$(ls /usr/lib/modules 2>/dev/null | sort -V | tail -1)
if [[ -n "$KVER" ]]; then
    INITRAMFS="/usr/lib/modules/$KVER/initramfs.img"
    [[ -s "$INITRAMFS" ]] || fail "Initramfs ausente ou vazio: $INITRAMFS (bib não consegue gerar disco de arranque)"
    # build.sh verifies the actual initramfs content immediately after dracut.
    # virtio_gpu (ficheiro virtio-gpu.ko) ajuda o Plymouth em VM (evita o handoff
    # simpledrm→virtio_gpu). NÃO-crítico: só avisa, não falha o build (no HW real
    # o Plymouth funciona com o driver nativo; a imagem arranca bem sem isto).
    lsinitrd "$INITRAMFS" 2>/dev/null | grep -qiE 'virtio.gpu\.ko' \
        || echo "INFO: initramfs sem virtio_gpu (Plymouth em VM pode não aparecer; HW real ok)"
fi

echo "=== Boot: GRUB timeout e kargs ==="
GRUB_TIMEOUT_CFG="/usr/lib/bootupd/grub2-static/configs.d/05_timeout.cfg"
grep -q 'set timeout=0' "$GRUB_TIMEOUT_CFG" \
    || fail "GRUB: timeout não é 0 em $GRUB_TIMEOUT_CFG"
grep -q 'timeout_style=hidden' "$GRUB_TIMEOUT_CFG" \
    || fail "GRUB: timeout_style não é hidden"
grep -q '"quiet"' /usr/lib/bootc/kargs.d/10-hardening.toml \
    || fail "kargs: 'quiet' ausente (necessário para boot silencioso)"
grep -q '"rhgb"' /usr/lib/bootc/kargs.d/10-hardening.toml \
    || fail "kargs: 'rhgb' ausente (trigger do Plymouth no Fedora)"
grep -q '"splash"' /usr/lib/bootc/kargs.d/10-hardening.toml \
    || fail "kargs: 'splash' ausente (mantido por compatibilidade; o trigger real do Plymouth no Fedora é 'rhgb')"

echo "=== Hardening ==="
grep -qx 'SELINUX=enforcing' /etc/selinux/config \
    || fail "SELinux não está em modo enforcing"
grep -qE '^DEFAULT' /etc/crypto-policies/config 2>/dev/null \
    || fail "Crypto policy não é DEFAULT (ou DEFAULT:*)"

echo "=== Performance / ZRAM ==="
grep -q 'vm.swappiness = 100' /etc/sysctl.d/99-performance.conf \
    || fail "swappiness não é 100 (ZRAM moderado para notebooks)"
grep -q 'vm.max_map_count' /etc/sysctl.d/99-performance.conf \
    || fail "vm.max_map_count não configurado"
grep -q 'compression-algorithm=zstd' /etc/systemd/zram-generator.conf \
    || fail "ZRAM não configurado com zstd"
grep -q 'zram-size = min(ram / 4, 4096)' /etc/systemd/zram-generator.conf \
    || fail "ZRAM não limitado a min(ram / 4, 4096)"

echo "=== DNF wrapper ==="
grep -q 'rpm-ostree' /usr/bin/dnf \
    || fail "/usr/bin/dnf não é o wrapper imutável"
[[ -x /usr/bin/dnf ]] \
    || fail "/usr/bin/dnf não é executável"

echo "=== COSMIC skel (toolkit + fontes + wallpaper) ==="
COSMIC_SKEL="/etc/skel/.config/cosmic"
# Modo escuro activo
grep -qx 'true' "$COSMIC_SKEL/com.system76.CosmicTheme.Mode/v1/is_dark" 2>/dev/null \
    || fail "COSMIC: modo escuro (is_dark) não definido no skel"
# Fontes JetBrainsMono Nerd Font
grep -q 'JetBrainsMono Nerd Font' "$COSMIC_SKEL/com.system76.CosmicTk/v1/interface_font" 2>/dev/null \
    || fail "COSMIC: interface_font não é JetBrainsMono Nerd Font"
grep -q 'JetBrainsMono Nerd Font Mono' "$COSMIC_SKEL/com.system76.CosmicTk/v1/monospace_font" 2>/dev/null \
    || fail "COSMIC: monospace_font não é JetBrainsMono Nerd Font Mono"
# Propagar tema às apps GTK
grep -qx 'true' "$COSMIC_SKEL/com.system76.CosmicTk/v1/apply_theme_global" 2>/dev/null \
    || fail "COSMIC: apply_theme_global não está activo (apps GTK não seguem o accent)"
# Ícones Tela
ICON_THEME=$(tr -d '"' < "$COSMIC_SKEL/com.system76.CosmicTk/v1/icon_theme" 2>/dev/null)
[[ -n "$ICON_THEME" ]] && { [[ -d "/usr/share/icons/$ICON_THEME" ]] \
    || fail "COSMIC: tema de ícones ausente: $ICON_THEME"; }
# Wallpaper referenciado existe
COSMIC_WALL=$(sed -n 's/.*Path("\([^"]*\)").*/\1/p' \
    "$COSMIC_SKEL/com.system76.CosmicBackground/v1/all" 2>/dev/null | head -1)
[[ -n "$COSMIC_WALL" ]] && { [[ -e "$COSMIC_WALL" ]] \
    || fail "COSMIC: wallpaper referenciado não existe: $COSMIC_WALL"; }
# Painel inferior fixo (estilo KDE/Windows)
grep -qx 'Bottom' "$COSMIC_SKEL/com.system76.CosmicPanel.Panel/v1/anchor" 2>/dev/null \
    || fail "COSMIC: painel não está em baixo (anchor != Bottom)"
grep -qx 'false' "$COSMIC_SKEL/com.system76.CosmicPanel.Panel/v1/anchor_gap" 2>/dev/null \
    || fail "COSMIC: painel não está fixo (anchor_gap != false)"
grep -qx '0' "$COSMIC_SKEL/com.system76.CosmicPanel.Panel/v1/border_radius" 2>/dev/null \
    || fail "COSMIC: painel deve ter border_radius 0"
grep -qx '0' "$COSMIC_SKEL/com.system76.CosmicPanel.Panel/v1/margin" 2>/dev/null \
    || fail "COSMIC: painel deve ter margin 0"
[[ -x /usr/libexec/fedora-cosmic-layout-setup ]] \
    || fail "COSMIC: fedora-cosmic-layout-setup ausente ou não executável"
[[ -f /etc/skel/.config/systemd/user/fedora-cosmic-layout-setup.service ]] \
    || fail "COSMIC: serviço user de layout ausente no skel"
[[ -f /etc/skel/.config/systemd/user/fedora-cosmic-layout-setup.timer ]] \
    || fail "COSMIC: timer user de layout ausente no skel"
[[ -f /usr/lib/systemd/user/fedora-cosmic-layout-setup.service ]] \
    || fail "COSMIC: serviço user global de layout ausente"
[[ -f /usr/lib/systemd/user/fedora-cosmic-layout-setup.timer ]] \
    || fail "COSMIC: timer user global de layout ausente"
[[ -L /etc/systemd/user/timers.target.wants/fedora-cosmic-layout-setup.timer ]] \
    || fail "COSMIC: timer user global de layout não está habilitado"

echo "=== GTK tema ==="
GTK3_CONF="/etc/skel/.config/gtk-3.0/settings.ini"
if [[ -f "$GTK3_CONF" ]]; then
    GTK_THEME=$(sed -n 's/^gtk-theme-name=//p' "$GTK3_CONF" | head -1)
    if [[ -n "$GTK_THEME" ]]; then
        [[ -d "/usr/share/themes/$GTK_THEME" ]] \
            || fail "GTK: tema '$GTK_THEME' referenciado no skel mas não instalado"
    fi
fi

echo "=== Tema COSMIC derivado (Catppuccin Mocha Mauve) ==="
COSMIC_DARK="/etc/skel/.config/cosmic/com.system76.CosmicTheme.Dark/v1"
COSMIC_BUILDER="/etc/skel/.config/cosmic/com.system76.CosmicTheme.Dark.Builder/v1"
# O tema derivado deve existir (gerado por cosmic-theme-gen no build)
[[ -s "$COSMIC_DARK/accent" ]] || fail "COSMIC: tema derivado ausente ($COSMIC_DARK/accent)"
[[ -s "$COSMIC_DARK/background" ]] || fail "COSMIC: tema derivado incompleto (background ausente)"
[[ -s "$COSMIC_BUILDER/accent" ]] || fail "COSMIC: ThemeBuilder ausente ($COSMIC_BUILDER/accent)"
# Accent mauve do Catppuccin Mocha (#cba6f7 ≈ rgb 0.796, 0.651, 0.969)
grep -q '0.79' "$COSMIC_BUILDER/accent" 2>/dev/null \
    || fail "COSMIC: accent do builder não corresponde ao mauve Catppuccin Mocha"
# Theme builder empacotado para import opcional
[[ -f /usr/share/cosmic-mokka/theme-builder.ron ]] \
    || fail "COSMIC: theme-builder.ron empacotado ausente"

echo "=== wpctl Steam wrapper ==="
[[ -x /usr/bin/wpctl.real ]] || fail "wpctl.real ausente (wrapper não instalado)"
[[ -x /usr/bin/wpctl ]] || fail "/usr/bin/wpctl não é executável"
grep -q "steam" /usr/bin/wpctl 2>/dev/null || fail "/usr/bin/wpctl não é o wrapper Steam"

echo "=== scx-scheds (COPR sched_ext/scx) ==="
if rpm -q scx-scheds &>/dev/null; then
    systemctl is-enabled scx.service 2>/dev/null | grep -q "^enabled$" \
        || fail "scx-scheds instalado mas scx.service não habilitado"
else
    echo "INFO: scx-scheds não instalado (COPR indisponível para esta arquitectura)"
fi

echo "=== keyd (COPR alternateved/keyd; substitui input-remapper) ==="
[[ ! -e /usr/bin/input-remapper-service ]] \
    || fail "input-remapper ainda presente (devia ter sido substituído por keyd)"
[[ ! -e /etc/udev/rules.d/99-input-remapper.rules ]] \
    || fail "regra udev do input-remapper ainda presente"
if rpm -q keyd &>/dev/null; then
    systemctl is-enabled keyd.service 2>/dev/null | grep -q "^enabled$" \
        || fail "keyd instalado mas keyd.service não habilitado"
    [[ -f /etc/keyd/default.conf ]] || fail "keyd: /etc/keyd/default.conf ausente"
else
    echo "INFO: keyd não instalado (COPR indisponível para esta arquitectura)"
fi

echo "=== starship (prompt; substitui Oh My Zsh + Powerlevel10k) ==="
if [[ "$(uname -m)" == "x86_64" ]]; then
    [[ -x /usr/bin/starship ]] || fail "starship ausente em /usr/bin (substituto de p10k)"
else
    echo "INFO: starship não verificado (arquitectura $(uname -m) sem binário pinado)"
fi
# A configuração do shell (fedora-shell-setup) já não deve clonar OMZ/p10k.
grep -q 'oh-my-zsh\|powerlevel10k' /usr/libexec/fedora-shell-setup 2>/dev/null \
    && fail "fedora-shell-setup ainda referencia Oh My Zsh/Powerlevel10k"
grep -q 'starship init' /usr/libexec/fedora-shell-setup 2>/dev/null \
    || fail "fedora-shell-setup não inicializa o starship"

echo "=== First-login shell/dev setup contracts ==="
grep -q 'sudo-command-line()' /usr/libexec/fedora-shell-setup 2>/dev/null \
    || fail "fedora-shell-setup sem widget sudo-command-line"
grep -q 'fj()' /usr/libexec/fedora-shell-setup 2>/dev/null \
    || fail "fedora-shell-setup sem helper fj"
grep -q 'fgb()' /usr/libexec/fedora-shell-setup 2>/dev/null \
    || fail "fedora-shell-setup sem helper fgb"
grep -q 'zoxide init zsh' /usr/libexec/fedora-shell-setup 2>/dev/null \
    || fail "fedora-shell-setup não inicializa zoxide condicionalmente"
grep -q 'direnv hook zsh' /usr/libexec/fedora-shell-setup 2>/dev/null \
    || fail "fedora-shell-setup não inicializa direnv condicionalmente"
grep -q '.local/share/fedora-dev-setup' /usr/libexec/fedora-dev-setup 2>/dev/null \
    || fail "fedora-dev-setup não escreve guia user-scoped"
grep -q 'distrobox create' /usr/libexec/fedora-dev-setup 2>/dev/null \
    || fail "fedora-dev-setup não orienta uso de Distrobox"
grep -q 'toolbox create' /usr/libexec/fedora-dev-setup 2>/dev/null \
    || fail "fedora-dev-setup não orienta uso de Toolbox"

echo "=== login.defs hardening ==="
grep -qE '^UMASK[[:space:]]+027' /etc/login.defs \
    || fail "login.defs: UMASK não é 027 (ficheiros novos serão world-readable)"
grep -qE '^YESCRYPT_COST_FACTOR[[:space:]]+8' /etc/login.defs \
    || fail "login.defs: YESCRYPT_COST_FACTOR não é 8 (password hashing fraco)"

echo "=== Authselect faillock ==="
authselect current 2>/dev/null | grep -q 'with-faillock' \
    || grep -rqs 'pam_faillock\.so' /etc/pam.d \
    || fail "PAM/authselect sem faillock activo"

echo "=== SUID removal ==="
[[ ! -f /usr/bin/chsh ]]   || fail "chsh deve ter sido removido (SUID desnecessário)"
[[ ! -f /usr/bin/chfn ]]   || fail "chfn deve ter sido removido (SUID desnecessário)"
[[ ! -f /usr/bin/pkexec ]] || fail "pkexec deve ter sido removido (CVE-2021-4034)"
[[ -u /usr/bin/sudo ]]     || fail "sudo perdeu bit SUID (mantido para uso em CLI)"

echo "=== Container signing ==="
[[ -f /etc/containers/registries.d/quay.io-fedora-ostree-desktops.yaml ]] \
    || fail "Container signing: policy ausente para fedora-ostree-desktops"
[[ -f /etc/containers/registries.d/quay.io-toolbx-images.yaml ]] \
    || fail "Container signing: policy ausente para toolbx-images"

echo "=== SELinux CIL policies ==="
semodule -l 2>/dev/null | grep -q 'secureblue_deny_ipsec_sockets' \
    || fail "SELinux: módulo secureblue_deny_ipsec_sockets não carregado"
semodule -l 2>/dev/null | grep -q 'harden_userns' \
    || fail "SELinux: módulo harden_userns não carregado"
semodule -l 2>/dev/null | grep -q 'container-ptrace' \
    || fail "SELinux: módulo container-ptrace não carregado"

echo "=== sysctl sysrq e ICMP ==="
grep -qE '^kernel\.sysrq\s*=\s*0' /etc/sysctl.d/60-security-hardening.conf \
    || fail "sysctl: kernel.sysrq não é 0"
grep -qE '^net\.ipv4\.icmp_echo_ignore_all\s*=\s*1' /etc/sysctl.d/60-security-hardening.conf \
    || fail "sysctl: net.ipv4.icmp_echo_ignore_all não é 1"

echo "=== modprobe DVB/RC ==="
[[ -f /etc/modprobe.d/no-dvb-rc.conf ]] \
    || fail "modprobe: blacklist DVB/RC ausente"
grep -q 'dvb-core' /etc/modprobe.d/no-dvb-rc.conf \
    || fail "modprobe: dvb-core não está blacklisted"

if [[ $FAILED -eq 1 ]]; then
    echo "::endgroup::"
    exit 1
fi

echo "Todos os testes passaram."
echo "::endgroup::"
