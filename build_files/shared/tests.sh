#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eou pipefail

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

echo "=== Pacotes obrigatórios ==="
REQUIRED_PACKAGES=(
    code
    distrobox
    earlyoom
    fastfetch
    ffmpeg
    firewalld
    gamemode
    git-credential-libsecret
    input-remapper
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
    yubikey-manager
    zsh
)
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    rpm -q "$pkg" > /dev/null 2>&1 || fail "Pacote ausente: $pkg"
done

echo "=== Pacotes indesejados ==="
UNWANTED_PACKAGES=(
    firefox
    kmahjongg
    kpat
    kmines
    mediawriter
    ptyxis
)
for pkg in "${UNWANTED_PACKAGES[@]}"; do
    if rpm -q "$pkg" > /dev/null 2>&1; then
        fail "Pacote indesejado presente: $pkg"
    fi
done

echo "=== Serviços systemd ==="
REQUIRED_UNITS=(
    podman.socket
    tuned.service
    earlyoom.service
    firewalld.service
    chronyd.service
    flatpak-nuke-fedora.service
    input-remapper.service
)
for unit in "${REQUIRED_UNITS[@]}"; do
    systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$" \
        || fail "Serviço não habilitado: $unit"
done
# dconf-update.service é opcional: não existe em todas as versões do Kinoite
if systemctl list-unit-files dconf-update.service &>/dev/null; then
    systemctl is-enabled dconf-update.service 2>/dev/null | grep -q "^enabled$" \
        || fail "Serviço não habilitado: dconf-update.service"
fi

echo "=== Ficheiros obrigatórios ==="
REQUIRED_FILES=(
    /etc/sysctl.d/60-security-hardening.conf
    /etc/sysctl.d/99-performance.conf
    /usr/lib/bootc/kargs.d/10-hardening.toml
    /etc/dracut.conf.d/99-omit-firewire.conf
    /etc/dracut.conf.d/99-omit-thunderbolt.conf
    /etc/dracut.conf.d/90-luks-security.conf
    /etc/skel/setup-user.sh
    /etc/skel/.local/bin/fedora-initial-setup
    /etc/selinux/config
    /etc/chrony.conf
    /etc/rpm-ostreed.conf
    /etc/sddm.conf.d/10-theme.conf
    /etc/xdg/plasma-welcomerc
    /etc/systemd/zram-generator.conf
    /etc/systemd/system.conf.d/timeout.conf
    /etc/systemd/user.conf.d/timeout.conf
    /etc/security/limits.d/50-memlock.conf
    /etc/dnf/conf.d/no-weak-deps.conf
    /usr/lib/systemd/system/flatpak-nuke-fedora.service
    /usr/lib/udev/rules.d/60-io-schedulers.rules
    /usr/lib/udev/rules.d/80-gpu-reset.rules
    /usr/lib/modules-load.d/wine-ntsync.conf
    /usr/share/dnf/plugins/copr.vendor.conf
    /usr/share/fonts/JetBrainsMonoNerdFont
    /usr/share/image-info.json
    /usr/share/qt6/qtlogging.ini
    /usr/share/wireplumber/wireplumber.conf.d/51-disable-suspension.conf
    /usr/bin/dnf
)
for f in "${REQUIRED_FILES[@]}"; do
    [[ -e "$f" ]] || fail "Ficheiro/directório ausente: $f"
done

echo "=== Hardening ==="
grep -qx 'SELINUX=enforcing' /etc/selinux/config \
    || fail "SELinux não está em modo enforcing"
grep -qE '^FUTURE' /etc/crypto-policies/config 2>/dev/null \
    || fail "Crypto policy não é FUTURE (ou FUTURE:*)"

echo "=== Performance / ZRAM ==="
grep -q 'vm.swappiness = 180' /etc/sysctl.d/99-performance.conf \
    || fail "swappiness não é 180 (requerido com ZRAM)"
grep -q 'vm.max_map_count' /etc/sysctl.d/99-performance.conf \
    || fail "vm.max_map_count não configurado"
grep -q 'compression-algorithm=zstd' /etc/systemd/zram-generator.conf \
    || fail "ZRAM não configurado com zstd"

echo "=== DNF wrapper ==="
grep -q 'rpm-ostree' /usr/bin/dnf \
    || fail "/usr/bin/dnf não é o wrapper imutável"
[[ -x /usr/bin/dnf ]] \
    || fail "/usr/bin/dnf não é executável"

echo "=== Plasma: plugins do skel ==="
APPLETSRC="/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [[ -f "$APPLETSRC" ]]; then
    # Apanha plugins VAZIOS — causa do "error when loading applet """
    # Plugins built-in do KDE (org.kde.*) não têm directório em plasmoids/ mas são válidos.
    # Só verificamos a existência de plugins de terceiros (sem prefixo org.kde.).
    while IFS= read -r plugin; do
        [[ -z "$plugin" ]] && fail "Plugin vazio em appletsrc (causa de 'error when loading applet \"\"')" && continue
        # Plugin built-in do KDE — sem directório, mas válido
        [[ "$plugin" == org.kde.* ]] && continue
        # Plugin de terceiros: deve ter directório em plasmoids/
        [[ -d "/usr/share/plasma/plasmoids/$plugin" ]] ||
            [[ -d "/usr/share/kpackage/genericqml/$plugin" ]] ||
            fail "Plugin de terceiros não encontrado em plasmoids/: $plugin"
    done < <(grep "^plugin=" "$APPLETSRC" | sed 's/^plugin=//')
else
    fail "appletsrc de skel ausente: $APPLETSRC"
fi

echo "=== Plasma: Panel Colorizer (se instalado) ==="
PC_DIR="/usr/share/plasma/plasmoids/luisbocanegra.panelcolorizer"
if [[ -d "$PC_DIR" ]]; then
    PC_META="$PC_DIR/metadata.json"
    if [[ -f "$PC_META" ]]; then
        PLUGIN_ID=$(python3 -c "import json; d=json.load(open('$PC_META')); print(d.get('KPlugin',{}).get('Id',''))" 2>/dev/null || echo "")
        [[ -n "$PLUGIN_ID" ]] || fail "Panel Colorizer: metadata.json sem plugin ID"
    else
        fail "Panel Colorizer instalado mas sem metadata.json"
    fi
fi

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

echo "=== Consistência de versão KDE ==="
KDE_VER="$(rpm -q --qf '%{VERSION}' plasma-desktop 2>/dev/null || echo '')"
KWIN_VER="$(rpm -q --qf '%{VERSION}' kwin 2>/dev/null || echo '')"
if [[ -n "$KDE_VER" && -n "$KWIN_VER" && "$KDE_VER" != "$KWIN_VER" ]]; then
    fail "Mismatch de versão KDE: plasma-desktop=${KDE_VER} kwin=${KWIN_VER}"
fi

if [[ $FAILED -eq 1 ]]; then
    echo "::endgroup::"
    exit 1
fi

echo "Todos os testes passaram."
echo "::endgroup::"
