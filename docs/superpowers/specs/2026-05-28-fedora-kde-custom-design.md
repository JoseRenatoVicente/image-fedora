# Design: fedora-kde-custom

**Data:** 2026-05-28  
**Abordagem escolhida:** Full Bake — tudo instalado e configurado dentro da imagem  

---

## Visão Geral

Customização da imagem Universal Blue baseada em `aurora:stable` (KDE Plasma) com:
- Pacotes de desenvolvimento, multimídia e gaming
- Tema visual completo Mokka (Catppuccin Mocha Mauve stack)
- Publicação automática no GHCR via GitHub Actions
- ISO instalável gerada pelo `bootc-image-builder`

---

## Arquitetura

### Estrutura de Arquivos

```
image-fedora/
├── Containerfile                         # FROM aurora:stable; executa build.sh
├── Justfile                              # image_name = fedora-kde-custom
├── build_files/
│   ├── build.sh                          # orquestrador principal
│   ├── install-assets.sh                 # baixa/instala fontes, cursores, ícones, tema Mokka
│   └── panel-colorizer.sh               # clona e compila Panel Colorizer
├── skel/
│   └── .config/                          # configs KDE copiadas para /etc/skel no build
│       ├── kdeglobals
│       ├── kwinrc
│       ├── plasmarc
│       ├── kcminputrc
│       ├── ksplashrc
│       └── kscreenlockerrc
├── disk_config/
│   ├── disk.toml
│   ├── iso-kde.toml                      # aponta para ghcr.io/<user>/fedora-kde-custom:latest
│   └── iso-gnome.toml
└── .github/workflows/
    ├── build.yml                         # CI: build + push GHCR
    └── build-disk.yml
```

### Fluxo de Build

```
Containerfile
└── build.sh
    ├── 1. Habilita COPRs (forceblur, rounded-corners, heroic)
    ├── 2. Adiciona repo VS Code (Microsoft)
    ├── 3. dnf5 install (pacotes dev + mídia + gaming + KDE extras)
    ├── 4. Desabilita COPRs
    ├── 5. install-assets.sh (assets em /usr/share/)
    │   ├── JetBrainsMono Nerd Font
    │   ├── Catppuccin Mocha Mauve cursors
    │   ├── Tela Circle Dracula icons
    │   └── Garuda Mokka theme (look-and-feel, color-schemes, aurorae, wallpapers)
    ├── 6. panel-colorizer.sh (build + install em /usr/share/)
    ├── 7. fc-cache -f (rebuild cache de fontes)
    └── 8. rsync skel/ → /etc/skel/
```

---

## Pacotes

### Dev Tools
- `git curl wget unzip tar jq`
- `gcc-c++ cmake extra-cmake-modules libplasma-devel`
- `code` (VS Code via repositório Microsoft)

### Multimídia
- `ffmpeg`
- `gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-ugly`
- `vlc`
- `pipewire-codec-aptx`

### Gaming
- `steam`
- `lutris`
- `heroic-games-launcher` (COPR: `heroic-games-launcher/heroic-games-launcher`)
- `wine winetricks`
- `gamemode gamescope`

### KDE / Tema Mokka
- `kvantum qt6ct qt5ct` (temas Qt/Kvantum)
- `spectacle` (screenshots)
- `inter-fonts` (fonte do sistema)
- `kwin-effects-forceblur kwin-effects-forceblur-x11` (COPR: `hazel-bunny/ricing`)
- `kwin-effect-roundcorners kwin-effect-roundcorners-x11` (COPR: `matinlotfali/KDE-Rounded-Corners`)

### COPRs (habilitados no build, desabilitados ao final)
- `hazel-bunny/ricing`
- `matinlotfali/KDE-Rounded-Corners`
- `heroic-games-launcher/heroic-games-launcher`

---

## Assets do Tema Mokka

Todos instalados em `/usr/share/` durante o build (sem sessão gráfica).

| Asset | Fonte | Destino |
|---|---|---|
| JetBrainsMono Nerd Font | `ryanoasis/nerd-fonts` releases | `/usr/share/fonts/JetBrainsMonoNerdFont/` |
| Catppuccin Mocha Mauve cursors | `catppuccin/cursors` releases | `/usr/share/icons/catppuccin-mocha-mauve-cursors/` |
| Tela Circle Dracula icons | `vinceliuice/Tela-circle-icon-theme` | `/usr/share/icons/Tela-circle-dracula/` |
| Garuda Mokka look-and-feel | GitLab `garuda-linux/garuda-mokka` | `/usr/share/plasma/look-and-feel/` |
| Garuda Mokka color-schemes | idem | `/usr/share/color-schemes/` |
| Garuda Mokka aurorae themes | idem | `/usr/share/aurorae/themes/` |
| Garuda Mokka wallpapers | idem | `/usr/share/wallpapers/` |
| Panel Colorizer | `luisbocanegra/plasma-panel-colorizer` (build) | `/usr/share/plasma/plasmoids/` |

---

## Configs KDE (skel)

Arquivos em `skel/.config/` são copiados para `/etc/skel/.config/` no build e aplicados automaticamente ao criar um novo usuário.

| Arquivo | Configuração principal |
|---|---|
| `kdeglobals` | Ícones: `Tela-circle-dracula`, fonte: `JetBrains Mono` |
| `kwinrc` | blur padrão desabilitado; forceblur + roundcorners habilitados |
| `kcminputrc` | cursor: `catppuccin-mocha-mauve-cursors` |
| `plasmarc` | tema do Plasma Mokka |
| `ksplashrc` | splash screen Mokka |
| `kscreenlockerrc` | tela de bloqueio Mokka |

Os arquivos de skel são extraídos do tarball do Garuda Mokka (`etc/skel/`) durante o build.  
**Limitação:** `plasma-apply-lookandfeel` e `kbuildsycoca6` não rodam no build headless. O look-and-feel é aplicado via configs estáticas lidas pelo KDE no primeiro login.

---

## CI/CD

### `build.yml` — variáveis a ajustar
```yaml
IMAGE_NAME: fedora-kde-custom
IMAGE_REGISTRY: ghcr.io/${{ github.repository_owner }}
DEFAULT_TAG: latest
```

Disparado em push para `main`. Publica em `ghcr.io/<usuario>/fedora-kde-custom:latest`.

### `disk_config/iso-kde.toml` — atualizado
```toml
[customizations.installer.kickstart]
contents = """
%post
bootc switch --mutate-in-place --transport registry ghcr.io/<usuario>/fedora-kde-custom:latest
%end
"""
```

O `<usuario>` deve ser substituído pelo username do GitHub do proprietário do repositório.

### `Justfile`
```just
export image_name := env("IMAGE_NAME", "fedora-kde-custom")
```

---

## Tratamento de Erros

- `install-assets.sh` usa `set -euo pipefail`; falha no download de qualquer asset interrompe o build
- COPRs são desabilitados no final do `build.sh` com `trap` para garantir limpeza mesmo em caso de erro
- Downloads usam `curl -L --fail` para tratar redirects e erros HTTP
- Panel Colorizer: se o build falhar, o script retorna erro e o build do container falha (intencional)

---

## Fora do Escopo

- Configuração de `cosign` / assinatura de imagem (documentado no README original)
- Upload de ISOs para S3
- Configurações específicas de hardware (Nvidia, etc.)
- Customização do Anaconda Installer além do kickstart existente
