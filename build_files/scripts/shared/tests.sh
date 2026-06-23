#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -euo pipefail

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

# Listas de pacotes (REQUIRED_PACKAGES, KDE_REQUIRED, UNWANTED_PACKAGES) vêm da
# fonte única partilhada com o build — evita drift entre instalar e verificar.
# shellcheck source=package-lists.sh
source "$(dirname "$0")/package-lists.sh"

echo "=== Pacotes obrigatórios ==="
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if [[ "$pkg" == "ffmpeg" ]]; then
        # Fedora repos ship 'ffmpeg-free'; RPM Fusion ships 'ffmpeg'. Accept either.
        rpm -q ffmpeg &>/dev/null || rpm -q ffmpeg-free &>/dev/null \
            || fail "Pacote ausente: ffmpeg (nem ffmpeg nem ffmpeg-free instalado)"
    else
        rpm -q "$pkg" > /dev/null 2>&1 || fail "Pacote ausente: $pkg"
    fi
done

echo "=== Pacotes KDE essenciais ==="
for pkg in "${KDE_REQUIRED[@]}"; do
    rpm -q "$pkg" > /dev/null 2>&1 || fail "Pacote KDE ausente: $pkg"
done

echo "=== Pacotes indesejados ==="
for pkg in "${UNWANTED_PACKAGES[@]}"; do
    if rpm -q "$pkg" > /dev/null 2>&1; then
        fail "Pacote indesejado presente: $pkg"
    fi
done
[[ ! -e /etc/yum.repos.d/vscode.repo ]] \
    || fail "Repo VS Code não deve existir na imagem base: /etc/yum.repos.d/vscode.repo"

echo "=== sudo → run0 (alias) ==="
# Nota: o pacote sudo NÃO é removido — plasma-workspace exige kdesu→sudo. Apenas
# adicionamos run0 + alias interativo.
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
    earlyoom.service
    firewalld.service
    chronyd.service
    flatpak-nuke-fedora.service
    flathub-system-setup.service
    fedora-kinoite-plasmalogin-workaround.service
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
# keyd é best-effort (não está nos repos Fedora; instalado via COPR quando disponível).
# A config /etc/keyd/default.conf vem sempre via overlay; o serviço só é exigido se
# o pacote estiver instalado.
if rpm -q keyd &>/dev/null; then
    systemctl is-enabled keyd.service 2>/dev/null | grep -q "^enabled$" \
        || fail "keyd instalado mas keyd.service não habilitado"
else
    echo "INFO: keyd não instalado (COPR indisponível); apenas a config é garantida"
fi

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
    /etc/dracut.conf.d/99-omit-thunderbolt.conf
    /etc/dracut.conf.d/90-luks-security.conf
    /usr/libexec/fedora-flatpak-setup
    /usr/libexec/fedora-shell-setup
    /usr/libexec/fedora-dev-setup
    /usr/libexec/fedora-brew-setup
    /etc/selinux/config
    /etc/chrony.conf
    /etc/rpm-ostreed.conf
    /etc/plasmalogin.conf.d/10-theme.conf
    /etc/xdg/plasma-welcomerc
    /etc/systemd/zram-generator.conf
    /etc/systemd/system.conf.d/timeout.conf
    /etc/systemd/user.conf.d/timeout.conf
    /etc/security/limits.d/50-memlock.conf
    /etc/dnf/conf.d/no-weak-deps.conf
    /usr/lib/systemd/system/flatpak-nuke-fedora.service
    /usr/lib/systemd/system/flathub-system-setup.service
    /usr/share/flatpak/flathub.flatpakrepo
    /etc/plasma-setup-done
    /etc/keyd/default.conf
    /etc/locale.conf
    /etc/vconsole.conf
    /etc/timezone
    /usr/bin/run0
    /etc/profile.d/run0-alias.sh
    /usr/lib/udev/rules.d/60-io-schedulers.rules
    /usr/lib/udev/rules.d/80-gpu-reset.rules
    /usr/lib/modules-load.d/wine-ntsync.conf
    /usr/share/dnf/plugins/copr.vendor.conf
    /usr/share/fonts/JetBrainsMonoNerdFont
    /usr/share/image-info.json
    /usr/share/qt6/qtlogging.ini
    /usr/share/wireplumber/wireplumber.conf.d/51-disable-suspension.conf
    /usr/bin/dnf
    /usr/lib/tmpfiles.d/fedora-kde-root-theme.conf
    /usr/lib/bootupd/grub2-static/configs.d/05_timeout.cfg
)
for f in "${REQUIRED_FILES[@]}"; do
    [[ -e "$f" ]] || fail "Ficheiro/directório ausente: $f"
done
# initramfs: determined dynamically from installed kernel version
# shellcheck disable=SC2012  # nomes de versão de kernel são seguros para ls
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
    || fail "kargs: 'splash' ausente (necessário para Plymouth)"

echo "=== Plymouth theme ==="
PLYMOUTHD_CONF="/etc/plymouth/plymouthd.conf"
[[ -f "$PLYMOUTHD_CONF" ]] \
    || fail "Plymouth: $PLYMOUTHD_CONF ausente"
grep -qE '^Theme=spinner$' "$PLYMOUTHD_CONF" \
    || fail "Plymouth: tema não é 'spinner' em $PLYMOUTHD_CONF"

echo "=== Locale, teclado e timezone ==="
grep -qx 'LANG=pt_BR.UTF-8' /etc/locale.conf \
    || fail "locale.conf: LANG não é pt_BR.UTF-8"
grep -qx 'KEYMAP=br-abnt2' /etc/vconsole.conf \
    || fail "vconsole.conf: KEYMAP não é br-abnt2"
grep -qx 'America/Sao_Paulo' /etc/timezone \
    || fail "/etc/timezone: não é America/Sao_Paulo"
[[ -L /etc/localtime ]] \
    || fail "/etc/localtime não é symlink (timezone não configurado)"
readlink /etc/localtime | grep -q 'America/Sao_Paulo' \
    || fail "/etc/localtime não aponta para America/Sao_Paulo"

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

echo "=== Plasma: plugins do skel ==="
APPLETSRC="/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [[ -f "$APPLETSRC" ]]; then
    # Apanha plugins VAZIOS — causa do "error when loading applet """
    # Valida plugins referenciados no skel contra os diretórios de pacote Plasma.
    # Alguns built-ins não vivem em plasmoids/ (ex.: org.kde.panel), mas os applets
    # e containments declarados explicitamente aqui devem existir onde aplicável.
    while IFS= read -r plugin; do
        [[ -z "$plugin" ]] && fail "Plugin vazio em appletsrc (causa de 'error when loading applet \"\"')" && continue
        case "$plugin" in
            org.kde.panel|org.kde.plasma.digitalclock|org.kde.plasma.kickoff|org.kde.plasma.marginsseparator|org.kde.plasma.pager|org.kde.plasma.showdesktop|org.kde.plasma.systemtray|org.kde.plasma.taskmanager)
                continue
                ;;
            org.kde.plasma.desktop)
                fail "Plugin inválido no skel: org.kde.plasma.desktop (Plasma 6 usa org.kde.plasma.folder)"
                continue
                ;;
        esac
        # Plugin de terceiros: deve ter directório em plasmoids/
        [[ -d "/usr/share/plasma/plasmoids/$plugin" ]] ||
            [[ -d "/usr/share/kpackage/genericqml/$plugin" ]] ||
            fail "Plugin referenciado no skel não encontrado em plasmoids/kpackage: $plugin"
    done < <(grep "^plugin=" "$APPLETSRC" | sed 's/^plugin=//')
    # Systemtray: extraItems= / knownItems= com string vazia são parseados como
    # lista com um elemento "" → systemtray tenta carregar applet com plugin="" →
    # "error when loading applet """. Estas chaves devem estar AUSENTES (auto-descoberta)
    # ou conter IDs reais separados por vírgula.
    for key in extraItems knownItems; do
        if grep -qE "^${key}=\$" "$APPLETSRC" 2>/dev/null; then
            fail "Systemtray: ${key}= é string vazia no appletsrc (causa 'error when loading applet'; remover a chave)"
        fi
    done
    # O skel deve manter o systray mínimo. Deixar o Plasma 6 gerar os sub-applets
    # evita migração/criação parcial no arranque, que produz "File name empty!" e
    # "error when loading applet \"\"" mesmo sem plugin vazio persistido.
    grep -q 'SystrayContainmentId' "$APPLETSRC" && \
        fail "Systemtray: SystrayContainmentId legado presente; usar applets aninhados do Plasma 6"
    grep -q '^plugin=org\.kde\.plasma\.private\.systemtray$' "$APPLETSRC" && \
        fail "Systemtray: containment legado org.kde.plasma.private.systemtray presente; usar applets aninhados do Plasma 6"
    grep -q '^\[Containments\]\[2\]\[Applets\]\[7\]\[Applets\]\[[0-9][0-9]*\]$' "$APPLETSRC" && \
        fail "Systemtray: skel pré-popula sub-applets; deixar Plasma gerar em runtime"
else
    fail "appletsrc de skel ausente: $APPLETSRC"
fi

echo "=== Login (plasmalogin) tema ==="
# O DM é o plasma-login-manager (plasmalogin): greeter QML próprio, não usa temas SDDM.
# Aparência configurada via:
#   1. /etc/xdg/kdeglobals — LookAndFeelPackage=Mokka (lido por startplasma-login-wayland)
#   2. /etc/plasmalogin.conf.d/10-theme.conf — WallpaperPluginId + Image (greeter wallpaper)
PLASMALOGIN_CONF="/etc/plasmalogin.conf.d/10-theme.conf"
PLASMALOGIN_KDEGLOBALS="/etc/xdg/kdeglobals"
[[ -f "$PLASMALOGIN_CONF" ]] || fail "Login: ficheiro de config ausente: $PLASMALOGIN_CONF"
grep -q '^WallpaperPluginId=org.kde.image$' "$PLASMALOGIN_CONF" \
    || fail "plasmalogin: WallpaperPluginId não é org.kde.image"
grep -q '^Image=file:///usr/share/wallpapers/Mokka-tree/' "$PLASMALOGIN_CONF" \
    || fail "plasmalogin: wallpaper Mokka-tree não configurado"
[[ -f "$PLASMALOGIN_KDEGLOBALS" ]] || fail "Login: kdeglobals ausente: $PLASMALOGIN_KDEGLOBALS"
grep -q '^LookAndFeelPackage=Mokka$' "$PLASMALOGIN_KDEGLOBALS" \
    || fail "Login: LookAndFeelPackage não é Mokka em $PLASMALOGIN_KDEGLOBALS"

echo "=== Lock screen ==="
LOCK_CFG="/etc/skel/.config/kscreenlockerrc"
if [[ -f "$LOCK_CFG" ]]; then
    grep -q '^Theme=Mokka' "$LOCK_CFG" \
        && fail "kscreenlockerrc: Theme=Mokka inválido (Mokka não tem QML de lockscreen)"
    LOCK_WALL=$(sed -n '/^\[Greeter\]\[Wallpaper\]\[org.kde.image\]\[General\]$/,/^\[/{s/^Image=//p}' \
        "$LOCK_CFG" 2>/dev/null | head -1)
    if [[ -n "$LOCK_WALL" ]]; then
        LOCK_WALL_PATH="${LOCK_WALL#file://}"
        [[ -e "$LOCK_WALL_PATH" ]] || fail "Lock screen: wallpaper não existe: $LOCK_WALL_PATH"
    fi
fi

echo "=== GTK tema ==="
GTK3_CONF="/etc/skel/.config/gtk-3.0/settings.ini"
if [[ -f "$GTK3_CONF" ]]; then
    GTK_THEME=$(sed -n 's/^gtk-theme-name=//p' "$GTK3_CONF" | head -1)
    if [[ -n "$GTK_THEME" ]]; then
        [[ -d "/usr/share/themes/$GTK_THEME" ]] \
            || fail "GTK: tema '$GTK_THEME' referenciado no skel mas não instalado"
    fi
fi

echo "=== Tema Mokka ==="
MOKKA_DIR="/usr/share/plasma/look-and-feel/Mokka"
[[ -d "$MOKKA_DIR" ]] || fail "Mokka: look-and-feel ausente: $MOKKA_DIR"

SPLASH_QML="$MOKKA_DIR/contents/splash/Splash.qml"
[[ -f "$SPLASH_QML" ]] || fail "Mokka: Splash.qml ausente"
grep -wq 'sizes' "$SPLASH_QML" && fail "Mokka Splash.qml: variável 'sizes' não corrigida (patch não aplicado)"

MOKKA_DEFAULTS="$MOKKA_DIR/contents/defaults"
[[ -f "$MOKKA_DEFAULTS" ]] || fail "Mokka: ficheiro defaults ausente"
grep -q 'Catppuccin-Mocha-Mauve-splash' "$MOKKA_DEFAULTS" && \
    fail "Mokka defaults: KSplash ainda referencia 'Catppuccin-Mocha-Mauve-splash' (patch não aplicado)"
grep -q 'garuda-mokka' "$MOKKA_DEFAULTS" && \
    fail "Mokka defaults: ainda referencia path 'garuda-mokka' (wallpaper lock screen não corrigido)"

# layout.js deve ter sido removido — a sua existência activa o pipeline de layout
# do Plasma, que pode criar containments fantasma com plugin vazio.
LAYOUT_DIR="$MOKKA_DIR/contents/layouts"
[[ -d "$LAYOUT_DIR" ]] && \
    fail "Mokka: directório layouts/ ainda existe (deve ser removido para evitar ghost containments)"

# layout.js user-local (skel): o rsync do Garuda copia o pacote Mokka completo
# para /etc/skel/.local/share/. Plasma resolve caminhos user-local ANTES dos
# system-wide, então um layout.js em ~/.local/share/ anula a remoção de
# /usr/share/. O build deve limpar esta cópia.
SKEL_LOCAL_MOKKA="/etc/skel/.local/share/plasma/look-and-feel/Mokka"
[[ -d "$SKEL_LOCAL_MOKKA" ]] && \
    fail "Mokka: skel user-local look-and-feel existe ($SKEL_LOCAL_MOKKA) — deve ser removido (overrides system-wide)"

# Assets Mokka redundantes no skel: instalados system-wide por install-assets.sh,
# não devem existir também em user-local (duplicação + conflito em updates).
for skel_dup in \
    "/etc/skel/.local/share/plasma/desktoptheme/Mokka" \
    "/etc/skel/.local/share/color-schemes/Mokka.colors" \
    "/etc/skel/.local/share/wallpapers/Mokka-tree" \
    "/etc/skel/.local/share/konsole/Mokka.colorscheme" \
    "/etc/skel/.local/share/Kvantum/Mokka"; do
    [[ -e "$skel_dup" ]] && \
        fail "Mokka: asset user-local duplicado no skel: $skel_dup (já instalado em /usr/share/)"
done

[[ -f "/usr/share/color-schemes/Mokka.colors" ]] || fail "Mokka: color scheme ausente"
[[ -d "/usr/share/plasma/desktoptheme/Mokka" ]]  || fail "Mokka: desktop theme ausente"

APPLETSRC_WALL=$(grep '^Image=' /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | head -1 | sed 's|^Image=file://||')
if [[ -n "$APPLETSRC_WALL" ]]; then
    [[ -e "$APPLETSRC_WALL" ]] || fail "Mokka: wallpaper referenciado no skel não existe: $APPLETSRC_WALL"
fi

ICON_THEME=$(sed -n '/^\[Icons\]/,/^\[/{s/^Theme=//p}' /etc/skel/.config/kdeglobals 2>/dev/null | head -1)
[[ -n "$ICON_THEME" ]] && { [[ -d "/usr/share/icons/$ICON_THEME" ]] || fail "Mokka: tema de ícones ausente: $ICON_THEME"; }

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
[[ -u /usr/bin/sudo ]]     || fail "sudo perdeu bit SUID (necessário para KDE/kdesu)"

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
