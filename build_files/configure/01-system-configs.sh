# 01-system-configs.sh — run0 alias, rpmfusion removal, system config installs,
# Bazzite-derived configs, login.defs, container signing, setfattr annotations,
# dbus-broker, greetd, cosmic-greeter, bluetooth-suspend, WiFi regulatory domain.
# Sourced by build-configure.sh (not executed directly).

# ─── sudo → run0 (alias) ──────────────────────────────────────────────────────
echo "::group:: sudo → run0 (alias)"
install -Dm644 /ctx/configs/run0-alias.sh /etc/profile.d/run0-alias.sh
echo "::endgroup::"

# ─── Remove repos rpmfusion ───────────────────────────────────────────────────
rm -f /etc/yum.repos.d/rpmfusion-*.repo

# ─── System configs ───────────────────────────────────────────────────────────
echo "::group:: System configs"

install -Dm644 /ctx/configs/selinux-enforcing.conf /etc/selinux/config

install -Dm644 /ctx/configs/sysctl-hardening.conf \
    /etc/sysctl.d/60-security-hardening.conf
install -Dm644 /ctx/configs/sysctl-ptrace.conf \
    /etc/sysctl.d/61-ptrace-scope.conf
install -Dm644 /ctx/configs/sysctl-performance.conf \
    /etc/sysctl.d/99-performance.conf

install -Dm644 /ctx/configs/modprobe-hardening.conf \
    /etc/modprobe.d/security-hardening.conf
install -Dm644 /ctx/configs/modprobe-framebuffer-blacklist.conf \
    /etc/modprobe.d/blacklist-framebuffer.conf
install -Dm644 /ctx/configs/modprobe-dvb-rc.conf \
    /etc/modprobe.d/no-dvb-rc.conf
# IPSec blacklist opcional — não ativo por defeito (quebraria VPNs).
install -Dm644 /ctx/configs/modprobe-ipsec-blacklist.conf \
    /usr/share/fedora-hardening/modprobe-ipsec-blacklist.conf

install -Dm644 /ctx/configs/bootc-kargs.toml \
    /usr/lib/bootc/kargs.d/10-hardening.toml

# GRUB: hide the boot menu and boot immediately.
install -Dm644 /ctx/configs/grub-timeout.cfg \
    /usr/lib/bootupd/grub2-static/configs.d/05_timeout.cfg

install -Dm644 /ctx/configs/limits-coredump.conf \
    /etc/security/limits.d/60-disable-coredump.conf
install -Dm644 /ctx/configs/systemd-coredump-system.conf \
    /etc/systemd/system.conf.d/60-disable-coredump.conf
install -Dm644 /ctx/configs/systemd-coredump-user.conf \
    /etc/systemd/user.conf.d/60-disable-coredump.conf

install -Dm644 /ctx/configs/resolved-dns.conf \
    /etc/systemd/resolved.conf.d/60-security-dns.conf
install -Dm644 /ctx/configs/resolved-disable-llmnr.conf \
    /etc/systemd/resolved.conf.d/10-disable-llmnr.conf

install -Dm644 /ctx/configs/chrony-nts.conf /etc/chrony.conf

install -Dm644 /ctx/configs/firewalld-workstation.xml \
    /etc/firewalld/zones/FedoraWorkstation.xml

install -Dm644 /ctx/configs/pwquality.conf /etc/security/pwquality.conf
install -Dm644 /ctx/configs/faillock.conf /etc/security/faillock.conf

install -Dm644 /ctx/configs/networkmanager-hardening.conf \
    /usr/lib/NetworkManager/conf.d/40-hardening.conf

install -Dm644 /ctx/configs/dracut-omit-firewire.conf \
    /etc/dracut.conf.d/99-omit-firewire.conf
install -Dm644 /ctx/configs/dracut-omit-unused.conf \
    /etc/dracut.conf.d/98-omit-unused.conf

install -Dm644 /ctx/configs/udev-hardening.rules \
    /usr/lib/udev/rules.d/99-hardening.rules

install -Dm644 /ctx/configs/systemd-preset-desktop.preset \
    /usr/lib/systemd/system-preset/35-security-desktop.preset

install -Dm644 /ctx/configs/journald-size.conf \
    /etc/systemd/journald.conf.d/size-limit.conf

install -Dm644 /ctx/configs/fstrim-fix.conf \
    /etc/systemd/system/fstrim.service.d/quiet-unsupported.conf

# systemd-oomd: tuning do swap/pressão (slices ManagedOOM vêm de systemd-oomd-defaults).
install -Dm644 /ctx/configs/oomd.conf \
    /etc/systemd/oomd.conf.d/10-oomd.conf

install -Dm644 /ctx/configs/chrony-nts-policy.pmod \
    /etc/crypto-policies/policies/modules/CHRONY-NTS.pmod

install -Dm644 /ctx/configs/rpm-ostreed.conf /etc/rpm-ostreed.conf

install -Dm644 /ctx/configs/dracut-luks.conf \
    /etc/dracut.conf.d/90-luks-security.conf

install -Dm644 /ctx/configs/copr-vendor.conf \
    /usr/share/dnf/plugins/copr.vendor.conf

install -Dm644 /ctx/configs/flatpak-nuke-fedora.service \
    /usr/lib/systemd/system/flatpak-nuke-fedora.service

install -Dm644 /ctx/configs/flathub-system-setup.service \
    /usr/lib/systemd/system/flathub-system-setup.service

# ── Bazzite-derived configs ───────────────────────────────────────────────────
install -Dm644 /ctx/configs/zram-generator.conf \
    /etc/systemd/zram-generator.conf

install -Dm644 /ctx/configs/udev-io-schedulers.rules \
    /usr/lib/udev/rules.d/60-io-schedulers.rules

install -Dm644 /ctx/configs/wireplumber-no-suspend.conf \
    /usr/share/wireplumber/wireplumber.conf.d/51-disable-suspension.conf

# Wireplumber: bloquear Steam de limpar defaults de áudio (equiv. ao patch Nobara)
mv /usr/bin/wpctl /usr/bin/wpctl.real
install -Dm755 /ctx/configs/wpctl-steam-wrapper /usr/bin/wpctl

install -Dm644 /ctx/configs/systemd-timeout.conf \
    /etc/systemd/system.conf.d/timeout.conf
install -Dm644 /ctx/configs/systemd-timeout.conf \
    /etc/systemd/user.conf.d/timeout.conf

install -Dm644 /ctx/configs/udev-gpu-reset.rules \
    /usr/lib/udev/rules.d/80-gpu-reset.rules

install -Dm755 /ctx/configs/dnf-wrapper /usr/bin/dnf

install -Dm644 /ctx/configs/dnf-no-weak-deps.conf \
    /etc/dnf/conf.d/no-weak-deps.conf

install -Dm644 /ctx/configs/modules-ntsync.conf \
    /usr/lib/modules-load.d/wine-ntsync.conf

install -Dm644 /ctx/configs/limits-memlock.conf \
    /etc/security/limits.d/50-memlock.conf

# login.defs: UMASK 027 (ficheiros novos não são world-readable por defeito)
# e YESCRYPT_COST_FACTOR 8 (hashing de password mais resistente a brute-force)
sed -i 's/^UMASK\s\+022/UMASK\t\t027/' /etc/login.defs
sed -i 's/^#\?YESCRYPT_COST_FACTOR.*/YESCRYPT_COST_FACTOR 8/' /etc/login.defs

# Container image signing: políticas sigstore para registos usados na imagem
install -Dm644 /ctx/configs/containers-registries-d/quay.io-fedora-ostree-desktops.yaml \
    /etc/containers/registries.d/quay.io-fedora-ostree-desktops.yaml
install -Dm644 /ctx/configs/containers-registries-d/quay.io-toolbx-images.yaml \
    /etc/containers/registries.d/quay.io-toolbx-images.yaml

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
    /etc/systemd/resolved.conf.d/60-security-dns.conf \
    /etc/systemd/resolved.conf.d/10-disable-llmnr.conf \
    /etc/chrony.conf \
    /etc/security/pwquality.conf \
    /etc/security/faillock.conf \
    /usr/lib/NetworkManager/conf.d/40-hardening.conf \
    /usr/lib/systemd/system-preset/35-security-desktop.preset \
    /etc/systemd/journald.conf.d/size-limit.conf

# ── COSMIC: dbus-broker open-file limit ──────────────────────────────────────
# COSMIC abre muitas conexões D-Bus (applets, portal, settings daemon); o limite
# padrão (~1024) é atingido em sessões longas, congelando applets.
install -Dm644 /ctx/configs/dbus-broker-nofile.conf \
    /usr/lib/systemd/user/dbus-broker.service.d/10-nofile.conf

# ── greetd: forçar VT 1 para handoff correto do plymouth ─────────────────────
# greetd por defeito usa vt="next", mas plymouth ocupa a VT 1; sem esta config
# o greeter abre numa VT diferente e o ecrã de boot fica em branco.
install -Dm644 /ctx/configs/greetd-config.toml /etc/greetd/config.toml

# ── cosmic-greeter: limpar estado stale antes de arrancar ────────────────────
# Previne que estado de tema do CosmicSettingsDaemon de uma sessão anterior
# contamine o greeter seguinte (sintoma: tema errado ou ecrã branco no login).
install -Dm644 /ctx/configs/cosmic-greeter-nuke.conf \
    /usr/lib/systemd/system/cosmic-greeter.service.d/10-nuke-stale-state.conf

# ── Bluetooth: preservar estado rfkill em suspend/resume ─────────────────────
install -Dm755 /ctx/configs/bluetooth-suspend.sh \
    /usr/lib/systemd/system-sleep/bluetooth-suspend

# ── WiFi regulatory domain via timezone ──────────────────────────────────────
# Deriva o domínio regulatório WiFi do timezone do sistema usando zone1970.tab.
# Ativado por uma .path unit que dispara ao mudar /etc/localtime.
install -Dm755 /ctx/configs/iw-regdomain.sh /usr/libexec/iw-regdomain
install -Dm644 /ctx/configs/iw-regdomain.path \
    /usr/lib/systemd/system/iw-regdomain.path
install -Dm644 /ctx/configs/iw-regdomain.service \
    /usr/lib/systemd/system/iw-regdomain.service

echo "::endgroup::"
