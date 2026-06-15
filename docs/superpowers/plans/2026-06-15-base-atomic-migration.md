# Base-Atomic Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the image from `kinoite:44` to `base-atomic:44` with a minimal KDE Plasma install, reducing image size from ~8.3 GB to ~4.5-5.0 GB.

**Architecture:** Replace the full Kinoite base (7.1 GB, 1740 packages) with the minimal base-atomic (4.76 GB, 1243 packages). Remove ~1.1 GB of unused packages from the base (printing, accessibility, non-Intel firmware, langpacks, input methods, VM guest agents). Install only the essential KDE Plasma packages (~50 packages instead of 512). Update build.sh to restructure the package flow: remove base bloat first, then install KDE + tools in a single dnf transaction.

**Tech Stack:** Containerfile (Podman/buildah), bash (build.sh), dnf5, rpm-ostree, bootc

**Spec:** `docs/superpowers/specs/2026-06-15-base-atomic-migration-design.md`

---

### Task 1: Update Containerfile base image

**Files:**
- Modify: `Containerfile:13`

- [ ] **Step 1: Change the FROM line to base-atomic**

Replace line 13 in `Containerfile`:

```dockerfile
# Old:
FROM quay.io/fedora-ostree-desktops/kinoite:44@sha256:61fcd0a1752050c93692d91a663e13681e45eb489aa095783d2880275cbf5406

# New:
FROM quay.io/fedora-ostree-desktops/base-atomic:44
```

Note: No digest pin yet — we'll pin after a successful build validates the image.

- [ ] **Step 2: Update comments about base images**

Update the comment block (lines 21-28) to reflect the new base:

```dockerfile
## Other possible base images include:
# FROM quay.io/fedora-ostree-desktops/kinoite:44  (full KDE, ~7.1 GB)
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
```

- [ ] **Step 3: Commit**

```bash
git add Containerfile
git commit -m "feat: switch base image from kinoite to base-atomic"
```

---

### Task 2: Restructure build.sh — Remove bloat section → Remove base-atomic bloat

**Files:**
- Modify: `build_files/build.sh:37-63`

The old "Remove bloat" section removes KDE apps that came with Kinoite (kmahjongg, kpat, etc). These don't exist in base-atomic. Replace it with removal of base-atomic packages we don't need.

- [ ] **Step 1: Remove the versionlock section (lines 37-42)**

The versionlock was needed to prevent partial KDE upgrades when installing over an existing Kinoite. With base-atomic, we install KDE fresh and no versionlock is needed.

Delete lines 37-42:

```bash
# ─── Versionlock KDE/Qt ───────────────────────────────────────────────────────
# Previne partial upgrade do Plasma durante o build (causaria black screen).
# Deve correr ANTES de qualquer dnf install que possa actualizar qt6/plasma.
echo "::group:: Versionlock KDE/Qt"
dnf5 versionlock add "qt6-*" "plasma-desktop"
echo "::endgroup::"
```

- [ ] **Step 2: Replace the "Remove bloat" section (lines 44-63) with base-atomic bloat removal**

Replace the entire section with:

```bash
# ─── Remove base-atomic bloat ─────────────────────────────────────────────────
# A base-atomic traz pacotes que não usamos (impressoras, acessibilidade, firmware
# de hardware que não temos, input methods asiáticos, VM guest agents, etc.).
# Remover ANTES de instalar KDE para evitar dnf resolver dependências contra eles.
echo "::group:: Remove base-atomic bloat"
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

    # Langpacks/fontes desnecessárias (~400 MB)
    glibc-all-langpacks
    default-fonts-cjk-mono default-fonts-cjk-sans default-fonts-cjk-serif
    cldr-emoji-annotation

    # IBus / input methods asiáticos (~160 MB)
    ibus-anthy ibus-chewing ibus-hangul
    ibus-libpinyin ibus-m17n ibus-typing-booster

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

# Substituir glibc-all-langpacks por langpacks mínimos (pt_BR + en_US)
dnf5 install -y glibc-langpack-pt glibc-langpack-en
echo "::endgroup::"
```

Note: `--setopt=clean_requirements_on_remove=False` prevents cascading removal of packages that depend on the removed ones. We only remove the explicitly listed packages.

- [ ] **Step 3: Commit**

```bash
git add build_files/build.sh
git commit -m "feat: replace kinoite bloat removal with base-atomic bloat removal"
```

---

### Task 3: Add KDE Plasma minimal install to build.sh

**Files:**
- Modify: `build_files/build.sh:84-127`

The current "Install packages" section assumes KDE is already present (from Kinoite). We need to add KDE packages to the install list.

- [ ] **Step 1: Add KDE packages to the PACKAGES array**

In the `PACKAGES` array (starting at line 86), add a KDE section at the top, before the existing packages. The new array should look like:

```bash
# ─── Install Fedora packages ──────────────────────────────────────────────────
echo "::group:: Install packages"
PACKAGES=(
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
    plasma-discover-rpm-ostree plasma-keyboard
    vulkan-tools mobile-broadband-provider-info NetworkManager-ppp
    plymouth-system-theme

    # ── Ferramentas do utilizador ─────────────────────────────────────────────
    # Dev tools
    git curl unzip tar jq make gettext
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
    # Build deps (removidos no passo cleanup)
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
    --exclude=perl-interpreter \
    --exclude=perl-libs \
    --exclude=kde-connect \
    "${PACKAGES[@]}"
echo "::endgroup::"
```

Key changes:
- Added ~50 KDE packages at the top
- Added `--exclude` flags to the `dnf5 install` command to prevent unwanted dependencies from being pulled in
- Kept all existing user tool packages unchanged

- [ ] **Step 2: Commit**

```bash
git add build_files/build.sh
git commit -m "feat: add minimal KDE Plasma install for base-atomic"
```

---

### Task 4: Add plasmalogin workaround from Kinoite

**Files:**
- Modify: `build_files/build.sh` (add after "System configs" section, before "Theming")

The Kinoite image includes a workaround service for missing plasmalogin entries in /etc/shadow and /etc/gshadow. base-atomic does NOT include this. Without it, plasma-login-manager may fail to start.

- [ ] **Step 1: Add plasmalogin workaround section**

Add this section after the "System configs" `echo "::endgroup::"` (line 297) and before "Theming" (line 299):

```bash
# ─── Plasmalogin workaround (from Kinoite) ────────────────────────────────────
# base-atomic não inclui o fix que o Kinoite tem para entries em falta do
# plasmalogin em /etc/shadow e /etc/gshadow. Sem isto o plasma-login-manager
# pode não arrancar. Ref: https://forge.fedoraproject.org/kde/tickets/issues/684
echo "::group:: Plasmalogin workaround"

cat > /usr/lib/systemd/system/fedora-kinoite-plasmalogin-workaround.service << 'EOF'
[Unit]
Description=Workaround for missing plasmalogin entries in /etc/shadow & /etc/gshadow
Documentation=https://forge.fedoraproject.org/kde/tickets/issues/684
ConditionPathIsReadWrite=/etc
ConditionPathExists=/run/ostree-booted
ConditionPathExists=!/etc/.fedora-kinoite-plasmalogin-workaround
Before=plasmalogin.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/fedora-kinoite-plasmalogin-workaround

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/libexec/fedora-kinoite-plasmalogin-workaround << 'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "Checking plasmalogin entries in /etc/shadow & /etc/gshadow"

if [[ $(grep -c "plasmalogin" "/etc/shadow") -eq 0 ]]; then
    echo "plasmalogin:!*:::::::" >> "/etc/shadow"
    echo "Added missing plasmalogin entry to /etc/shadow"
else
    echo "Nothing to do for /etc/shadow"
fi

if [[ $(grep -c "plasmalogin" "/etc/gshadow") -eq 0 ]]; then
    echo "plasmalogin:!*::" >> "/etc/gshadow"
    echo "Added missing plasmalogin entry to /etc/gshadow"
else
    echo "Nothing to do for /etc/gshadow"
fi

echo "Writing stamp file: /etc/.fedora-kinoite-plasmalogin-workaround"
touch /etc/.fedora-kinoite-plasmalogin-workaround
SCRIPT

chmod a+x /usr/libexec/fedora-kinoite-plasmalogin-workaround

# Add preset for the workaround (append to existing preset if it exists)
cat >> /usr/lib/systemd/system-preset/35-security-desktop.preset << 'EOF'

# Plasmalogin workaround (from Kinoite)
enable fedora-kinoite-plasmalogin-workaround.service
EOF

systemctl preset fedora-kinoite-plasmalogin-workaround.service

echo "::endgroup::"
```

- [ ] **Step 2: Commit**

```bash
git add build_files/build.sh
git commit -m "feat: add plasmalogin workaround for base-atomic"
```

---

### Task 5: Update cleanup section

**Files:**
- Modify: `build_files/build.sh:642-670`

The cleanup section references `dnf5 versionlock clear` which we no longer use.

- [ ] **Step 1: Remove the versionlock clear line**

In the Cleanup section (line 644), remove:

```bash
dnf5 versionlock clear
```

Since we no longer set any versionlock, this line would error or be a no-op.

- [ ] **Step 2: Commit**

```bash
git add build_files/build.sh
git commit -m "chore: remove versionlock clear from cleanup (no longer used)"
```

---

### Task 6: Update tests.sh for new base

**Files:**
- Modify: `build_files/shared/tests.sh:9-56`

The unwanted packages list needs updating — the old Kinoite-specific apps (kmahjongg, etc) are no longer relevant since they were never in base-atomic. Add the new unwanted packages (the ones we remove from base-atomic) to verify they stay removed.

- [ ] **Step 1: Update UNWANTED_PACKAGES list**

Replace the `UNWANTED_PACKAGES` array (lines 43-51) with:

```bash
UNWANTED_PACKAGES=(
    code
    firefox
    # Impressoras (removidas da base-atomic)
    cups hplip gutenprint
    # Acessibilidade (removida)
    orca brltty speech-dispatcher
    # Firmware não-Intel (removido)
    nvidia-gpu-firmware amd-gpu-firmware
    # VM guest agents (removidos)
    open-vm-tools-desktop virtualbox-guest-additions
    # KDE bloat que não deve estar presente
    plasma-discover
    plasma-workspace-wallpapers
    kde-connect
    akonadi-server
    mariadb-server
)
```

- [ ] **Step 2: Add a test for KDE Plasma core packages**

After the existing `REQUIRED_PACKAGES` check (line 40), add a section to verify essential KDE packages are installed:

```bash
echo "=== Pacotes KDE essenciais ==="
KDE_REQUIRED=(
    plasma-desktop
    plasma-workspace
    kwin
    plasma-login-manager
    dolphin
    konsole
)
for pkg in "${KDE_REQUIRED[@]}"; do
    rpm -q "$pkg" > /dev/null 2>&1 || fail "Pacote KDE ausente: $pkg"
done
```

- [ ] **Step 3: Add test for plasmalogin workaround service**

In the `REQUIRED_UNITS` array (line 73), add:

```bash
    fedora-kinoite-plasmalogin-workaround.service
```

- [ ] **Step 4: Commit**

```bash
git add build_files/shared/tests.sh
git commit -m "test: update tests for base-atomic migration"
```

---

### Task 7: Update initramfs comment

**Files:**
- Modify: `build_files/build.sh:603-608`

The comment references "A base Kinoite NÃO inclui virtio_gpu" — update it since we're now on base-atomic.

- [ ] **Step 1: Update the comment**

Replace:

```bash
# A base Kinoite NÃO inclui virtio_gpu no initramfs. Numa VM QEMU isso faz o
```

With:

```bash
# A base-atomic NÃO inclui virtio_gpu no initramfs. Numa VM QEMU isso faz o
```

- [ ] **Step 2: Commit**

```bash
git add build_files/build.sh
git commit -m "chore: update initramfs comment for base-atomic"
```

---

### Task 8: Build and verify

- [ ] **Step 1: Run the build**

```bash
just build
```

Expected: Build completes successfully, including `bootc container lint` pass.

- [ ] **Step 2: Check image size**

```bash
podman images | grep fedora-kde-custom
```

Expected: Image size is approximately 4.5-5.5 GB (significantly less than the previous 8.3 GB).

- [ ] **Step 3: Run container tests**

```bash
just test-container
```

Expected: All tests pass (required packages, unwanted packages absent, services enabled, files present).

- [ ] **Step 4: Boot test in VM**

```bash
just run-vm-gl
```

Expected: VM boots to plasma-login-manager (SDDM), KDE Plasma desktop loads with Mokka theme, panel with taskbar works, Dolphin opens, kitty terminal opens.

- [ ] **Step 5: Record final size and commit**

If all tests pass:

```bash
podman images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep fedora-kde-custom
git add -A
git commit -m "feat: complete migration from kinoite to base-atomic

Switched base image from kinoite:44 (~7.1 GB) to base-atomic:44 (~4.8 GB).
Removed ~1.1 GB of unused packages (printing, a11y, non-Intel firmware,
CJK langpacks, input methods, VM guest agents).
Installed minimal KDE Plasma (~50 packages vs Kinoite's 512).
Final image size: ~X.X GB (down from 8.3 GB)."
```

---

### Task 9: Pin base-atomic digest (after successful build)

**Files:**
- Modify: `Containerfile:13`

- [ ] **Step 1: Get the digest of the validated base-atomic image**

```bash
podman inspect quay.io/fedora-ostree-desktops/base-atomic:44 --format '{{.Digest}}'
```

- [ ] **Step 2: Update the FROM line with the pinned digest**

```dockerfile
FROM quay.io/fedora-ostree-desktops/base-atomic:44@sha256:<DIGEST_FROM_STEP_1>
```

- [ ] **Step 3: Rebuild to verify digest pin works**

```bash
just build
```

- [ ] **Step 4: Commit**

```bash
git add Containerfile
git commit -m "chore: pin base-atomic digest after successful validation"
```
