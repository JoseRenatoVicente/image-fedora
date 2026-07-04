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
    firewalld.service
    chronyd.service
    flatpak-nuke-fedora.service
    flathub-system-setup.service
    fedora-kinoite-plasmalogin-workaround.service
    thermald.service
    rpm-ostreed-automatic.timer
    podman-auto-update.timer
)
# bolt e fwupd são ativados por D-Bus/udev — não têm WantedBy; presença verificada abaixo
for unit in bolt.service fwupd.service; do
    systemctl is-enabled "$unit" 2>/dev/null | grep -qE "^(enabled|static)$" \
        || fail "Serviço ausente ou mascarado: $unit"
done
for unit in "${REQUIRED_UNITS[@]}"; do
    echo "  verificando: $unit"
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
    /etc/dracut.conf.d/03-storage-drivers.conf
    /etc/dracut.conf.d/99-omit-firewire.conf
    /etc/dracut.conf.d/99-omit-thunderbolt.conf
    /etc/dracut.conf.d/90-luks-security.conf
    /etc/dracut.conf.d/10-boot-performance.conf
    /etc/systemd/system/tuned.service.d/deferred.conf
    /etc/systemd/system/tuned-ppd.service.d/no-block-multiuser.conf
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
    /etc/udisks2/mount_options.conf
    /etc/tmpfiles.d/99-proc-hardening.conf
    # CIS extras (Tier 1+2)
    /etc/issue
    /etc/issue.net
    /etc/motd
    /etc/sudoers.d/10-cis-hardening
    /etc/fstab
    /etc/audit/rules.d/60-cis-hardening.rules
    /etc/tmpfiles.d/audit-log-dir.conf
    /etc/tmpfiles.d/home.conf
    /etc/security/pwhistory.conf
    /etc/xdg/kdedrc
    /usr/lib/bootc/kargs.d/30-audit.toml
    # STIG Tier A
    /etc/xdg/kscreenlockerrc
    /etc/profile.d/tmout.sh
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
grep -q 'vm.swappiness = 180' /etc/sysctl.d/99-performance.conf \
    || fail "swappiness não é 180 (ZRAM agressivo, estilo Bazzite)"
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
grep -q 'Catppuccin-Mocha-Mauve-Cursors' "$MOKKA_DEFAULTS" && \
    fail "Mokka defaults: cursorTheme ainda referencia 'Catppuccin-Mocha-Mauve-Cursors' (patch não aplicado; quebra cursor no greeter)"

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
MOKKA_PLASMARC="/usr/share/plasma/desktoptheme/Mokka/plasmarc"
grep -q '^enabled=false$' <(sed -n '/^\[AdaptiveTransparency\]/,/^\[/{p}' "$MOKKA_PLASMARC" 2>/dev/null) \
    || fail "Mokka: AdaptiveTransparency não está desativado em $MOKKA_PLASMARC"
grep -q '^enabled=true$' <(sed -n '/^\[BlurBehindEffect\]/,/^\[/{p}' "$MOKKA_PLASMARC" 2>/dev/null) \
    || fail "Mokka: BlurBehindEffect não está alinhado ao host em $MOKKA_PLASMARC"

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

echo "=== scx-scheds / scx_loader (best-effort) ==="
if rpm -q scx-scheds &>/dev/null; then
    echo "OK: scx-scheds instalado"
    if rpm -q scx-tools &>/dev/null; then
        systemctl is-enabled scx_loader.service 2>/dev/null | grep -q "^enabled$" \
            || fail "scx-tools instalado mas scx_loader.service não habilitado"
    else
        echo "INFO: scx-tools ausente; scx_loader.service não habilitado"
    fi
else
    echo "INFO: scx-scheds não disponível nos repos nesta build; scheduler SCX inactivo"
fi

echo "=== AMD CPB boost (oneshot condicional) ==="
[[ -f /usr/lib/systemd/system/amd-cpb-boost.service ]] \
    || fail "amd-cpb-boost.service ausente"
grep -q '^ConditionPathExists=/sys/devices/system/cpu/amd_pstate/cpb_boost$' \
    /usr/lib/systemd/system/amd-cpb-boost.service \
    || fail "amd-cpb-boost.service sem ConditionPathExists (geraria ruído em Intel)"
systemctl is-enabled amd-cpb-boost.service 2>/dev/null | grep -q "^enabled$" \
    || fail "amd-cpb-boost.service não habilitado"

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

echo "=== Root account lockout ==="
passwd -S root 2>/dev/null | grep -q ' L ' \
    || fail "root: password não está bloqueada (passwd -l root não aplicado)"
grep -E '^root:' /etc/passwd | cut -d: -f7 | grep -q 'nologin' \
    || fail "root: shell não é nologin (usermod -s /usr/sbin/nologin root não aplicado)"

echo "=== SUID removal ==="
[[ ! -f /usr/bin/chsh ]]   || fail "chsh deve ter sido removido (SUID desnecessário)"
[[ ! -f /usr/bin/chfn ]]   || fail "chfn deve ter sido removido (SUID desnecessário)"
[[ -x /usr/bin/pkexec ]]    || fail "pkexec deve existir para fluxos polkit/liveinst"
[[ -u /usr/bin/pkexec ]]    || fail "pkexec deve manter SUID para elevar via polkit/liveinst"
[[ -u /usr/bin/sudo ]]     || fail "sudo perdeu bit SUID (necessário para KDE/kdesu)"
mapfile -d '' _hmalloc_libs < <(find /usr/lib /usr/lib64 -type f -name 'libhardened_malloc*.so' -print0 2>/dev/null || true)
((${#_hmalloc_libs[@]} > 0)) || fail "hardened_malloc: bibliotecas não encontradas"
for _hmalloc_lib in "${_hmalloc_libs[@]}"; do
    [[ -u "$_hmalloc_lib" ]] || fail "hardened_malloc: $_hmalloc_lib perdeu SUID para preload em binários privilegiados"
done

echo "=== Container signing ==="
[[ -f /etc/containers/registries.d/quay.io-fedora-ostree-desktops.yaml ]] \
    || fail "Container signing: policy ausente para fedora-ostree-desktops"
[[ -f /etc/containers/registries.d/quay.io-toolbx-images.yaml ]] \
    || fail "Container signing: policy ausente para toolbx-images"

echo "=== SELinux CIL policies ==="
SELINUX_PAYLOAD_DIR="/usr/share/selinux/image-fedora"
[[ -f "$SELINUX_PAYLOAD_DIR/secureblue_socket_utils.cil" ]] \
    || fail "SELinux: payload secureblue_socket_utils.cil ausente"
[[ -f "$SELINUX_PAYLOAD_DIR/secureblue_deny_ipsec_sockets.cil" ]] \
    || fail "SELinux: payload secureblue_deny_ipsec_sockets.cil ausente"
[[ -f "$SELINUX_PAYLOAD_DIR/container-ptrace.cil" ]] \
    || fail "SELinux: payload container-ptrace.cil ausente"
[[ -x /usr/libexec/image-fedora-selinux-setup ]] \
    || fail "SELinux: helper boot-time /usr/libexec/image-fedora-selinux-setup ausente"
grep -q 'semodule -X 300 -i' /usr/libexec/image-fedora-selinux-setup \
    || fail "SELinux: helper não instala CIL via semodule"
grep -q 'setsebool deny_ptrace=on' /usr/libexec/image-fedora-selinux-setup \
    || fail "SELinux: helper não aplica deny_ptrace"
grep -q 'setsebool container_allow_ptrace=off' /usr/libexec/image-fedora-selinux-setup \
    || fail "SELinux: helper não aplica container_allow_ptrace"
# harden_userns / harden_container_userns foram REMOVIDOS de propósito: o deny
# de user_namespace quebrava navegadores flatpak (bwrap/unconfined_t) e
# rootless podman/distrobox (container_runtime_t). Garantimos que NÃO voltam.
find "$SELINUX_PAYLOAD_DIR" -type f -name '*harden_userns*.cil' | grep -q . \
    && fail "SELinux: harden_userns NÃO deve estar carregado (quebra flatpak/podman userns)"
find "$SELINUX_PAYLOAD_DIR" -type f -name '*harden_container_userns*.cil' | grep -q . \
    && fail "SELinux: harden_container_userns NÃO deve estar carregado (quebra podman/distrobox)"

echo "=== sysctl sysrq e ICMP ==="
grep -qE '^kernel\.sysrq\s*=\s*0' /etc/sysctl.d/60-security-hardening.conf \
    || fail "sysctl: kernel.sysrq não é 0"
grep -qE '^net\.ipv4\.icmp_echo_ignore_all\s*=\s*1' /etc/sysctl.d/60-security-hardening.conf \
    || fail "sysctl: net.ipv4.icmp_echo_ignore_all não é 1"
grep -qE '^dev\.tty\.legacy_tiocsti\s*=\s*0' /etc/sysctl.d/60-security-hardening.conf \
    || fail "sysctl: dev.tty.legacy_tiocsti não é 0 (TIOCSTI)"
grep -qE '^net\.ipv4\.tcp_synack_retries\s*=\s*2' /etc/sysctl.d/60-security-hardening.conf \
    || fail "sysctl: net.ipv4.tcp_synack_retries não é 2"
grep -qE '^net\.ipv4\.tcp_challenge_ack_limit\s*=' /etc/sysctl.d/60-security-hardening.conf \
    || fail "sysctl: net.ipv4.tcp_challenge_ack_limit ausente (CVE-2016-5696)"

echo "=== modprobe DVB/RC ==="
[[ -f /etc/modprobe.d/no-dvb-rc.conf ]] \
    || fail "modprobe: blacklist DVB/RC ausente"
grep -q 'dvb-core' /etc/modprobe.d/no-dvb-rc.conf \
    || fail "modprobe: dvb-core não está blacklisted"

echo "=== modprobe AF_ALG ==="
for _mod in af_alg algif_hash algif_skcipher algif_rng algif_aead; do
    grep -qE "^install ${_mod} /bin/false" /etc/modprobe.d/security-hardening.conf \
        || fail "modprobe: ${_mod} não está desativado (AF_ALG)"
done

echo "=== sshd hardening drop-in ==="
[[ -f /etc/ssh/sshd_config.d/60-hardening.conf ]] \
    || fail "ssh: drop-in de hardening ausente"
grep -qE '^PermitRootLogin no' /etc/ssh/sshd_config.d/60-hardening.conf \
    || fail "ssh: PermitRootLogin no ausente no drop-in"

echo "=== kargs extra (cipherblue-derived) ==="
# page_poison=1 removido por overhead; mantêm-se defesas de heap/branch/stack.
for _karg in 'spec_rstack_overflow=safe-ret' 'slab_nomerge' 'ftrace=off'; do
    grep -qF "\"${_karg}\"" /usr/lib/bootc/kargs.d/10-hardening.toml \
        || fail "kargs: '${_karg}' ausente"
done

echo "=== udisks2 mount hardening ==="
grep -qE '^defaults=.*noexec' /etc/udisks2/mount_options.conf \
    || fail "udisks2: noexec ausente nos defaults de mount"
grep -qE '^allow=nosuid,nodev,noexec' /etc/udisks2/mount_options.conf \
    || fail "udisks2: allow= não restringe a nosuid,nodev,noexec"

echo "=== Serviços mascarados ==="
for masked_svc in irqbalance.service lm_sensors.service; do
    [[ "$(readlink /etc/systemd/system/${masked_svc} 2>/dev/null)" == "/dev/null" ]] \
        || fail "${masked_svc} deve estar mascarado (inútil com lockdown=integrity / sem sensores configurados)"
done

echo "=== bluetooth dir mode ==="
stat -c '%a' /etc/bluetooth 2>/dev/null | grep -q '^555$' \
    || fail "/etc/bluetooth: modo deve ser 555 (bluetoothd ConfigurationDirectoryMode=0555)"

echo "=== NetworkManager privacidade ==="
grep -qE '^hostname-mode=none' /usr/lib/NetworkManager/conf.d/40-hardening.conf \
    || fail "NM: hostname-mode=none ausente"
grep -qE '^ipv4\.dhcp-send-hostname=0' /usr/lib/NetworkManager/conf.d/40-hardening.conf \
    || fail "NM: dhcp-send-hostname não desativado"
grep -qE '^enabled=false' /usr/lib/NetworkManager/conf.d/40-hardening.conf \
    || fail "NM: connectivity check não desativado"

echo "=== usbguard presente mas desabilitado ==="
rpm -q usbguard &>/dev/null \
    || fail "usbguard: pacote não instalado"
if systemctl list-unit-files usbguard.service &>/dev/null; then
    systemctl is-enabled usbguard.service 2>/dev/null | grep -q '^enabled$' \
        && fail "usbguard.service NÃO deve estar habilitado (trava USB sem política)"
fi

echo "=== FDE: LUKS2 + TPM2 + Secure Boot ==="
for _pkg in cryptsetup tpm2-tools mokutil hardened_malloc; do
    rpm -q "$_pkg" &>/dev/null || fail "FDE/hardening: pacote ausente: $_pkg"
done
# libhardened_malloc: presente em /etc/ld.so.preload com permissões correctas
[[ -f /etc/ld.so.preload ]] \
    || fail "hardened_malloc: /etc/ld.so.preload ausente"
grep -q 'libhardened_malloc.so' /etc/ld.so.preload \
    || fail "hardened_malloc: libhardened_malloc.so não está em /etc/ld.so.preload"
[[ "$(stat -c %a /etc/ld.so.preload)" == "600" ]] \
    || fail "hardened_malloc: /etc/ld.so.preload deve ter permissões 600 (tem $(stat -c %a /etc/ld.so.preload))"
# systemd-cryptenroll vem com o systemd
command -v systemd-cryptenroll &>/dev/null \
    || fail "FDE: systemd-cryptenroll ausente"
# Módulos dracut de LUKS/TPM2 declarados na config
grep -qE '(^|[[:space:]])crypt([[:space:]]|")' /etc/dracut.conf.d/90-luks-security.conf \
    || fail "FDE: módulo dracut 'crypt' ausente em 90-luks-security.conf"
grep -q 'tpm2-tss' /etc/dracut.conf.d/90-luks-security.conf \
    || fail "FDE: módulo dracut 'tpm2-tss' ausente em 90-luks-security.conf"
# Helpers de enrollment presentes e executáveis
[[ -x /usr/bin/tpm2-luks-enroll ]] \
    || fail "FDE: /usr/bin/tpm2-luks-enroll ausente ou não executável"
[[ -x /usr/bin/tpm2-first-enroll ]] \
    || fail "FDE: /usr/bin/tpm2-first-enroll ausente ou não executável"
# Serviço de primeiro arranque habilitado (activa TPM2 antes do greetd)
systemctl is-enabled tpm2-first-enroll.service 2>/dev/null | grep -q '^enabled$' \
    || fail "FDE: tpm2-first-enroll.service não está habilitado"

echo "=== CIS Tier 1+2: banners, sudo, mounts, auditd, pwhistory ==="
# Banners de aviso (CIS 1.7 / STIG 211020/255025): aviso de uso autorizado +
# consentimento de monitorização, sem leak de info de OS (\\m \\r \\s \\v).
for banner in /etc/issue /etc/issue.net; do
    grep -q 'authorized users only' "$banner" \
        || fail "Banner $banner sem aviso de uso autorizado (CIS 1.7 / STIG 211020)"
    grep -qi 'monitored' "$banner" \
        || fail "Banner $banner sem aviso de monitorização (STIG 211020)"
    grep -qE '\\[mrsv]' "$banner" \
        && fail "Banner $banner vaza info de OS via escapes \\m/\\r/\\s/\\v (CIS 1.7)"
done

# sudo hardening (CIS 5.2)
SUDO_CIS="/etc/sudoers.d/10-cis-hardening"
PERM=$(stat -c '%a' "$SUDO_CIS" 2>/dev/null || echo '')
[[ "$PERM" == "440" ]] || fail "sudoers.d/10-cis-hardening: permissões não são 0440 (são ${PERM:-?}) — seria ignorado pelo sudo"
grep -qE '^Defaults[[:space:]]+use_pty' "$SUDO_CIS"  || fail "sudo: use_pty ausente (CIS 5.2.2)"
grep -qE '^Defaults[[:space:]]+logfile' "$SUDO_CIS"  || fail "sudo: logfile ausente (CIS 5.2.3)"
visudo -cf "$SUDO_CIS" &>/dev/null                   || fail "sudo: 10-cis-hardening não passa no visudo -c"

# /dev/shm hardening (CIS 1.1.2.3) — via /etc/fstab (systemd recusa .mount para API filesystems)
DEVSHM_FSTAB="/etc/fstab"
grep -qE '^tmpfs[[:space:]]+/dev/shm.*nosuid' "$DEVSHM_FSTAB" || fail "fstab: /dev/shm sem nosuid (CIS 1.1.2.3)"
grep -qE '^tmpfs[[:space:]]+/dev/shm.*nodev'  "$DEVSHM_FSTAB" || fail "fstab: /dev/shm sem nodev (CIS 1.1.2.3)"
grep -qE '^tmpfs[[:space:]]+/dev/shm.*noexec' "$DEVSHM_FSTAB" || fail "fstab: /dev/shm sem noexec (CIS 1.1.2.3)"

# kded6 módulos problemáticos desabilitados (kdedrc)
KDEDRC="/etc/xdg/kdedrc"
grep -qE '^\[Module-wpad-detector\]'  "$KDEDRC" || fail "kdedrc: seção [Module-wpad-detector] ausente"
grep -qE '^autoload=false' <(grep -A2 '\[Module-wpad-detector\]' "$KDEDRC") \
    || fail "kdedrc: wpad-detector autoload=false ausente"

# tmpfiles OSTree: home.conf override usa caminhos reais (/var/home, /var/srv)
HOMECF="/etc/tmpfiles.d/home.conf"
grep -qE '^[Qq][[:space:]]+/var/home' "$HOMECF" || fail "tmpfiles home.conf: entrada /var/home ausente"
grep -qE '^q[[:space:]]+/var/srv'     "$HOMECF" || fail "tmpfiles home.conf: entrada /var/srv ausente"

# /etc/group deve ter grupos padrão do sistema (audio, disk, kvm, video, tty)
for grp in audio disk kvm video tty render input; do
    grep -q "^${grp}:" /etc/group || fail "/etc/group: grupo '${grp}' ausente (udev/tmpfiles falhariam no boot)"
done

# auditd (CIS 6.3): pacote + kargs + regras + diretório de log
rpm -q audit &>/dev/null || fail "auditd: pacote audit ausente"
grep -qF '"audit=1"' /usr/lib/bootc/kargs.d/30-audit.toml \
    || fail "kargs: audit=1 ausente (CIS 6.3.1)"
grep -qF '"audit_backlog_limit=8192"' /usr/lib/bootc/kargs.d/30-audit.toml \
    || fail "kargs: audit_backlog_limit ausente (CIS 6.3.1)"
AUDIT_RULES="/etc/audit/rules.d/60-cis-hardening.rules"
grep -qE '^-w /etc/passwd -p wa -k identity' "$AUDIT_RULES" \
    || fail "audit: regra identity (/etc/passwd) ausente"
grep -qE '^-a always,exit .* -k time-change' "$AUDIT_RULES" \
    || fail "audit: regra time-change ausente"
# As regras só podem referenciar binários presentes — chsh/chfn foram removidos
# e NÃO devem ser auditados (geraria erro de load no boot).
for removed in chsh chfn; do
    grep -qE "path=/usr/bin/${removed}\b" "$AUDIT_RULES" \
        && fail "audit: regra referencia binário removido (/usr/bin/${removed}) — erro de load no boot"
done
if systemctl list-unit-files auditd.service &>/dev/null; then
    systemctl is-enabled auditd.service 2>/dev/null | grep -q '^enabled$' \
        || fail "auditd.service não habilitado"
fi

# pwhistory (CIS 5.3.3.4): config presente (ativação no stack é best-effort)
grep -qE '^remember[[:space:]]*=[[:space:]]*5' /etc/security/pwhistory.conf \
    || fail "pwhistory: remember=5 ausente (CIS 5.3.3.4)"

# journald (CIS 6.2)
grep -qE '^Compress=yes' /etc/systemd/journald.conf.d/size-limit.conf \
    || fail "journald: Compress=yes ausente (CIS 6.2)"

echo "=== STIG Tier A: lock de ecrã, TMOUT, inatividade de contas ==="
# Bloqueio de ecrã KDE (STIG 271055/271065/271075) — imutável via [$i]
KSL="/etc/xdg/kscreenlockerrc"
grep -qE '^\[Daemon\]\[\$i\]' "$KSL" || fail "kscreenlockerrc: grupo [Daemon] não é imutável ([\$i]) (STIG 271060/271070/271080)"
grep -qE '^Autolock=true' "$KSL"     || fail "kscreenlockerrc: Autolock!=true (STIG 271055)"
grep -qE '^Timeout=10$' "$KSL"       || fail "kscreenlockerrc: Timeout!=10 min (STIG 271065)"
grep -qE '^LockOnResume=true' "$KSL" || fail "kscreenlockerrc: LockOnResume!=true (STIG 271075)"
grep -qE '^Theme=Mokka' "$KSL"       && fail "kscreenlockerrc: Theme=Mokka inválido (Mokka não tem QML de lockscreen)"

# Timeout de shell interativo (STIG 412035)
grep -qE 'TMOUT=600' /etc/profile.d/tmout.sh \
    || fail "tmout.sh: TMOUT=600 ausente (STIG 412035)"
grep -qE 'readonly TMOUT' /etc/profile.d/tmout.sh \
    || fail "tmout.sh: TMOUT não é readonly (utilizador poderia desativar) (STIG 412035)"

# Inatividade de contas 35 dias (STIG 411050)
useradd -D 2>/dev/null | grep -qE '^INACTIVE=35$' \
    || fail "useradd defaults: INACTIVE!=35 (STIG 411050)"

if [[ $FAILED -eq 1 ]]; then
    echo "::endgroup::"
    exit 1
fi

echo "Todos os testes passaram."
echo "::endgroup::"
