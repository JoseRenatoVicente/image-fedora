# 05-services.sh — Services + Flatpak configuration.
# Sourced by build-configure.sh (not executed directly).

# ─── Serviços + Flatpak ───────────────────────────────────────────────────────
echo "::group:: Services + Flatpak"
systemctl enable podman.socket
systemctl enable tuned
systemctl enable systemd-oomd.service
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
# Display manager: cosmic-greeter (greetd) — substitui o plasma-login-manager.
# Arranca em modo gráfico por defeito.
systemctl enable cosmic-greeter.service
systemctl set-default graphical.target
systemctl enable iw-regdomain.path
# keyd: daemon de remapeamento de teclas (substitui o input-remapper). Lê
# /etc/keyd/*.conf; instalamos um default no-op pronto para o utilizador editar.
install -Dm644 /ctx/configs/keyd-default.conf /etc/keyd/default.conf
if rpm -q keyd &>/dev/null; then
    systemctl enable keyd.service
else
    echo "INFO: keyd não instalado (COPR indisponível), serviço não habilitado"
fi
if rpm -q scx-scheds &>/dev/null; then
    systemctl enable scx.service
fi

systemctl enable thermald.service irqbalance.service
# bolt e fwupd são D-Bus/udev-activated; preset mantém a política explícita sem exigir WantedBy.
systemctl preset bolt.service thermald.service irqbalance.service tuned.service fwupd.service
systemctl preset power-profiles-daemon.service 2>/dev/null || true

# ── Boot speed: mascarar serviços que atrasam o boot sem benefício ────────────
# systemctl mask não funciona em container build sem systemd a correr —
# criamos os symlinks /dev/null directamente (equivalente ao que mask faria).
# NM-wait-online: aguarda conectividade completa (~20-30s); apps com rede fazem
# retry por conta própria — não há razão para bloquear o boot inteiro por isto.
# ModemManager: hardware de modem 4G ausente neste laptop.
# plymouth-quit-wait: com KMS/DRM o handoff é imediato; esperar pelo quit é redundante.
# avahi-daemon: mDNS/Bonjour desnecessário (sem impressoras de rede, sem KDE Connect).
for _unit in \
    NetworkManager-wait-online.service \
    ModemManager.service \
    plymouth-quit-wait.service \
    avahi-daemon.service \
    avahi-daemon.socket; do
    ln -sf /dev/null "/etc/systemd/system/${_unit}"
done

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
