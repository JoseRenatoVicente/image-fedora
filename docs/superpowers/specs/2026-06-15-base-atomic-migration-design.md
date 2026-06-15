# Design: Migrar para base-atomic com KDE minimo

**Data:** 2026-06-15
**Objetivo:** Reduzir significativamente o tamanho da imagem OCI trocando a base de `kinoite:44` (~7.1 GB) para `base-atomic:44` (~4.76 GB) e instalando apenas os pacotes KDE essenciais.
**Estimativa de tamanho final:** ~4.5-5.0 GB (vs 8.3 GB atual)

## Contexto

| Imagem | Tamanho | Pacotes |
|--------|---------|---------|
| base-atomic:44 | 4.76 GB | 1243 |
| kinoite:44 | 7.10 GB | 1740 |
| Imagem atual (custom) | 8.30 GB | ~1800+ |
| **Meta** | **~4.5-5.0 GB** | **~1000-1100** |

A base-atomic ja inclui: kernel, firmware, NetworkManager, podman/buildah/skopeo, flatpak, systemd, SELinux, rpm-ostree, chrony, firewalld, pipewire, mesa, e todo o sistema base Fedora. Nao inclui nenhum desktop environment.

## Estrategia

Tres acoes combinadas:

1. **Trocar a base image** de kinoite para base-atomic
2. **Remover pacotes desnecessarios** da base-atomic (firmware, impressoras, a11y, langpacks)
3. **Instalar KDE Plasma minimo** com apenas os pacotes essenciais

## 1. Mudanca de base image

### Containerfile

```dockerfile
FROM quay.io/fedora-ostree-desktops/base-atomic:44
```

O pin por digest sera atualizado apos validacao.

### Impacto no build.sh

- A secao "Remove bloat" (kmahjongg, kpat, etc) deixa de ser necessaria -- esses pacotes nao existem na base-atomic
- O versionlock de KDE/Qt continua necessario (agora protege o install em vez de update)
- A secao de COPR packages nao muda
- Todas as configs de seguranca continuam iguais

## 2. Pacotes a REMOVER da base-atomic

### Impressoras (~124 MB)

```
cups cups-browsed cups-filters hplip gutenprint gutenprint-cups
bluez-cups system-config-printer-udev c2esp dymo-cups-drivers
printer-driver-brlaser ptouch-driver splix mpage paps
```

### Acessibilidade (~121 MB)

```
orca brltty speech-dispatcher
```

Nota: `at-spi2-core` e `at-spi2-atk` sao dependencias de GTK e nao podem ser removidos sem arrastar apps GTK. Manter.

### Firmware nao-Intel (~224 MB)

```
nvidia-gpu-firmware amd-gpu-firmware amd-ucode-firmware
atheros-firmware mt7xxx-firmware realtek-firmware brcmfmac-firmware
libertas-firmware tiwilink-firmware nxpwireless-firmware
b43-fwcutter b43-openfwwf qcom-wwan-firmware
```

**Manter (Intel):**
```
intel-gpu-firmware intel-audio-firmware intel-vsc-firmware
iwlwifi-mvm-firmware iwlwifi-mld-firmware iwlegacy-firmware
microcode_ctl alsa-sof-firmware linux-firmware
libva-intel-media-driver
```

Nota: `linux-firmware` contem drivers genericos alem dos especificos por vendor; nao remover.

### Langpacks e fontes desnecessarias (~400 MB)

```
glibc-all-langpacks
default-fonts-cjk-mono default-fonts-cjk-sans default-fonts-cjk-serif
cldr-emoji-annotation
```

**Substituir `glibc-all-langpacks` por:**
```
glibc-langpack-pt glibc-langpack-en
```

### IBus / input methods (~160 MB)

```
ibus-anthy ibus-chewing ibus-hangul ibus-libpinyin ibus-m17n
ibus-typing-booster
```

Manter `ibus-gtk3` e `ibus-gtk4` se necessarios para input basico.

### Virtualizacao / guest agents (~50 MB)

```
open-vm-tools-desktop spice-vdagent spice-webdavd
hyperv-daemons qemu-guest-agent virtualbox-guest-additions
```

### Servicos de rede nao utilizados

```
nfs-utils cifs-utils samba-client sssd-common sssd-kcm
```

### Outros

```
hunspell sos fpaste words pinfo lrzsz kmscon
```

### Total estimado de remocao: ~1.1-1.5 GB

## 3. Pacotes KDE a INSTALAR

### Core Plasma (obrigatorio)

```
plasma-desktop
plasma-workspace
kwin
kscreenlocker
kscreen
plasma-login-manager
kde-settings-plasmalogin
kcm-plasmalogin
```

### Painel e widgets

```
kdeplasma-addons
plasma-pa
plasma-nm
plasma-nm-openvpn
bluedevil
polkit-kde
plasma-drkonqi
kinfocenter
plasma-systemmonitor
```

### Integracao de sistema

```
kde-gtk-config
flatpak-kcm
kio-admin
pam-kwallet
pinentry-qt
libappindicator-gtk3
```

### File manager e utilitarios

```
dolphin
kio-gdrive
konsole
kwrite
spectacle
ark
kdialog
ffmpegthumbs
kdegraphics-thumbnailers
audiocd-kio
kamera
```

### Display e graficos

```
xorg-x11-server-Xwayland
xwaylandvideobridge
mesa-dri-drivers
mesa-vulkan-drivers
libva-intel-media-driver
```

### Portais

```
xdg-desktop-portal
xdg-desktop-portal-kde
```

### Temas fallback

```
plasma-breeze
breeze-icon-theme
aurorae
```

### Extras mantidos do build atual

```
plasma-discover-rpm-ostree
plasma-keyboard
vulkan-tools
mobile-broadband-provider-info
NetworkManager-ppp
```

### Pacotes KDE EXCLUIDOS (vs Kinoite)

| Pacote | Tamanho | Razao |
|--------|---------|-------|
| plasma-workspace-wallpapers | 227 MB | Usa tema custom |
| qt6-qtwebengine (via Discover) | 290 MB | Nao instala Discover |
| akonadi-server + mariadb | ~140 MB | PIM nao utilizado |
| plasma-discover + notifier | ~20 MB | Usa terminal |
| kde-connect | ~15 MB | Nao utilizado |
| phonon-qt6-backend-vlc + vlc-libs | ~45 MB | Nao necessario |
| gdb / gdb-headless | ~18 MB | Debug nao necessario |
| krfb / krdp | ~5 MB | Remote desktop |
| khelpcenter | ~10 MB | Docs offline |
| plasma-print-manager | ~5 MB | Sem impressora |
| plasma-thunderbolt | ~2 MB | Nao utilizado |
| plasma-vault | ~3 MB | Nao utilizado |
| plasma-welcome / plasma-setup | ~5 MB | Nao necessario |
| kdenetwork-filesharing | ~3 MB | Nao utilizado |
| colord-kde | ~2 MB | Calibracao de cor |
| kaccounts-integration-qt6 | ~5 MB | Online accounts |
| **Total excluido** | **~800 MB** | |

## 4. Pacotes exclude-packages (dnf)

Usar `exclude-packages` no treefile ou `--exclude` no dnf para prevenir pull de dependencias indesejadas:

```
PackageKit PackageKit-glib
plasma-discover-offline-updates plasma-discover-packagekit plasma-pk-updates
tracker tracker-miners localsearch tinysparql
plasma-x11 plasma-workspace-x11
mariadb-server-utils
qt5-qtbase
perl-interpreter perl-libs
kde-connect
```

## 5. Postprocess e workarounds

### Do Kinoite (necessarios)

- **PlasmaDiscoverUpdates config**: manter (auto updates)
- **Plasmalogin workaround** (`fedora-kinoite-plasmalogin-workaround.service`): obrigatorio -- a base-atomic nao inclui este fix que o Kinoite tem

### Do common.yaml (ja na base-atomic)

- Journal persistent storage: ja incluido
- glibc_post_upgrade workaround: ja incluido
- Systemd preset-all: ja incluido

## 6. Mudancas no build.sh

### Remover secoes

- "Remove bloat" (pacotes KDE nao existem na base-atomic)
- Versionlock pode ser simplificado (instala versoes frescas)

### Adicionar secoes

- "Remove base-atomic bloat" -- `dnf5 remove` dos pacotes listados na secao 2
- "Install KDE minimal" -- `dnf5 install` dos pacotes listados na secao 3
- "Plasmalogin workaround" -- copiar do Kinoite shared config
- Substituir `glibc-all-langpacks` por langpacks especificos

### Manter inalterado

- Todas as configs de seguranca (sysctl, modprobe, bootc-kargs, etc)
- COPR packages (roundcorners, scx-scheds)
- Temas e assets (install-assets.sh)
- Panel colorizer (panel-colorizer.sh)
- Configuracoes KDE/Plasma do skel
- Servicos systemd (earlyoom, tuned, flatpak setup, etc)
- Cleanup final (docs, locales, cache)
- Dracut / initramfs
- Crypto policy

## 7. Riscos e mitigacao

| Risco | Mitigacao |
|-------|-----------|
| Dependencias KDE faltando causam crash | Testar boot completo em VM antes de merge |
| Firmware Intel faltando apos remocao de `linux-firmware` | NAO remover linux-firmware, apenas firmware vendor-specific |
| Plasma login nao funciona sem workaround | Incluir o workaround do Kinoite |
| Pacotes removidos sao dependencia de algo | Usar `dnf5 remove --noautoremove` e verificar o que seria removido antes |
| Tamanho nao reduz o esperado | Verificar com `podman images` apos build; ajustar iterativamente |

## 8. Validacao

1. Build local com `just build`
2. `podman images` para verificar tamanho
3. `just run-vm-gl` para testar boot e desktop funcional
4. Verificar que todos os servicos de seguranca estao ativos
5. Testar Flatpak install, Distrobox, containers
6. `just test-container` para testes estaticos
