# fedora-kde-custom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Customizar o template Universal Blue para gerar uma imagem bootc baseada em Aurora (KDE Plasma) com pacotes de dev/mídia/gaming e tema visual Mokka (Catppuccin Mocha Mauve stack) publicada no GHCR.

**Architecture:** Full Bake — todos os assets (fontes, cursores, ícones, tema Garuda Mokka, Panel Colorizer) são baixados e instalados em `/usr/share/` durante o build do container. Configs KDE são escritas em `/etc/skel/.config/` via `kwriteconfig6` e aplicadas automaticamente ao criar um novo usuário.

**Tech Stack:** bootc, podman/buildah, Aurora (KDE Plasma 6), dnf5, GitHub Actions, GHCR, kwriteconfig6

---

## Mapa de Arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `Containerfile` | Modificar | Trocar base para `aurora:stable` |
| `Justfile` | Modificar | Atualizar `image_name` |
| `build_files/build.sh` | Reescrever | Orquestrador: COPR, pacotes, chamar scripts, kwriteconfig6 |
| `build_files/install-assets.sh` | Criar | Baixar e instalar fontes/cursores/ícones/tema Mokka |
| `build_files/panel-colorizer.sh` | Criar | Clonar e instalar Panel Colorizer em /usr/share/ |
| `disk_config/iso.toml` | Criar | Config ISO para build-disk.yml (alias de iso-kde.toml) |
| `disk_config/iso-kde.toml` | Modificar | Atualizar URL do bootc switch |
| `.github/workflows/build.yml` | Modificar | Atualizar IMAGE_DESC |

---

## Task 1: Atualizar Containerfile e Justfile

**Files:**
- Modify: `Containerfile`
- Modify: `Justfile`

- [ ] **Step 1: Trocar base image no Containerfile**

Substituir a linha `FROM`:

```dockerfile
# De:
FROM ghcr.io/ublue-os/bazzite:stable

# Para:
FROM ghcr.io/ublue-os/aurora:stable
```

- [ ] **Step 2: Atualizar image_name no Justfile**

Substituir a primeira linha:

```just
export image_name := env("IMAGE_NAME", "fedora-kde-custom")
```

- [ ] **Step 3: Verificar sintaxe**

```bash
head -1 Justfile
# Esperado: export image_name := env("IMAGE_NAME", "fedora-kde-custom")

grep "^FROM" Containerfile
# Esperado: FROM ghcr.io/ublue-os/aurora:stable
```

- [ ] **Step 4: Commit**

```bash
git add Containerfile Justfile
git commit -m "feat: use aurora:stable as base image, rename to fedora-kde-custom"
```

---

## Task 2: Criar install-assets.sh

**Files:**
- Create: `build_files/install-assets.sh`

Este script roda dentro do container como root. Baixa e instala todos os assets visuais do tema Mokka em `/usr/share/`.

- [ ] **Step 1: Criar o arquivo**

```bash
cat > build_files/install-assets.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*" >&2; }

TMPDIR_ASSETS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ASSETS"' EXIT

# ── Fontes: JetBrainsMono Nerd Font ──────────────────────────────────────────
log "Instalando JetBrainsMono Nerd Font"
FONT_DIR="/usr/share/fonts/JetBrainsMonoNerdFont"
mkdir -p "$FONT_DIR"
curl -L --fail -o "$TMPDIR_ASSETS/JetBrainsMono.zip" \
  "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
unzip -qo "$TMPDIR_ASSETS/JetBrainsMono.zip" -d "$FONT_DIR"
# Remove arquivos desnecessários (Windows, etc)
find "$FONT_DIR" -name "*.ttf" ! -name "*NerdFont*" -delete 2>/dev/null || true
fc-cache -f "$FONT_DIR"

# ── Cursores: Catppuccin Mocha Mauve ─────────────────────────────────────────
log "Instalando cursores Catppuccin Mocha Mauve"
curl -L --fail -o "$TMPDIR_ASSETS/catppuccin-cursors.zip" \
  "https://github.com/catppuccin/cursors/releases/latest/download/catppuccin-mocha-mauve-cursors.zip"
unzip -qo "$TMPDIR_ASSETS/catppuccin-cursors.zip" -d /usr/share/icons/

# ── Ícones: Tela Circle Dracula ───────────────────────────────────────────────
log "Instalando ícones Tela Circle Dracula"
git clone --depth=1 https://github.com/vinceliuice/Tela-circle-icon-theme \
  "$TMPDIR_ASSETS/Tela-circle-icon-theme"
bash "$TMPDIR_ASSETS/Tela-circle-icon-theme/install.sh" \
  -d /usr/share/icons \
  -c dracula

# ── Tema Garuda Mokka ─────────────────────────────────────────────────────────
log "Baixando tema Garuda Mokka"
GARUDA_URL="https://gitlab.com/garuda-linux/themes-and-settings/settings/garuda-mokka/-/archive/main/garuda-mokka-main.tar.gz"
curl -L --fail -o "$TMPDIR_ASSETS/garuda-mokka.tar.gz" "$GARUDA_URL"
tar -xzf "$TMPDIR_ASSETS/garuda-mokka.tar.gz" -C "$TMPDIR_ASSETS"

GARUDA_DIR="$(find "$TMPDIR_ASSETS" -maxdepth 1 -type d -name 'garuda-mokka*' | head -n1)"
if [[ -z "$GARUDA_DIR" ]]; then
  warn "Tarball do Garuda Mokka não encontrado no caminho esperado. Pulando assets do tema."
else
  log "Instalando assets do Garuda Mokka de: $GARUDA_DIR"

  copy_dir_if_exists() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dst"
    rsync -a "$src"/ "$dst"/
  }

  copy_dir_if_exists "$GARUDA_DIR/usr/share/plasma/look-and-feel" \
    /usr/share/plasma/look-and-feel
  copy_dir_if_exists "$GARUDA_DIR/usr/share/color-schemes" \
    /usr/share/color-schemes
  copy_dir_if_exists "$GARUDA_DIR/usr/share/plasma/desktoptheme" \
    /usr/share/plasma/desktoptheme
  copy_dir_if_exists "$GARUDA_DIR/usr/share/aurorae/themes" \
    /usr/share/aurorae/themes
  copy_dir_if_exists "$GARUDA_DIR/usr/share/wallpapers" \
    /usr/share/wallpapers
  copy_dir_if_exists "$GARUDA_DIR/usr/share/konsole" \
    /usr/share/konsole

  # Skel do Garuda Mokka (configs KDE defaults)
  SKEL_SRC=""
  [[ -d "$GARUDA_DIR/etc/skel" ]] && SKEL_SRC="$GARUDA_DIR/etc/skel"
  if [[ -n "$SKEL_SRC" ]]; then
    log "Aplicando skel do Garuda Mokka"
    rsync -a "$SKEL_SRC"/ /etc/skel/
  else
    warn "Skel não encontrado no tarball do Garuda Mokka."
  fi
fi

log "Assets instalados com sucesso."
SCRIPT
chmod +x build_files/install-assets.sh
```

- [ ] **Step 2: Verificar sintaxe com shellcheck**

```bash
shellcheck build_files/install-assets.sh
# Esperado: sem erros (warnings de style são aceitáveis)
```

- [ ] **Step 3: Commit**

```bash
git add build_files/install-assets.sh
git commit -m "feat: add install-assets.sh for Mokka theme assets"
```

---

## Task 3: Criar panel-colorizer.sh

**Files:**
- Create: `build_files/panel-colorizer.sh`

Clona o Panel Colorizer, usa `HOME` temporário para rodar o `install.sh`, depois move para `/usr/share/`.

- [ ] **Step 1: Criar o arquivo**

```bash
cat > build_files/panel-colorizer.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

TMPDIR_PC="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_PC"' EXIT

log "Clonando Panel Colorizer"
git clone --depth=1 https://github.com/luisbocanegra/plasma-panel-colorizer \
  "$TMPDIR_PC/plasma-panel-colorizer"

# Cria HOME falso para o install.sh instalar sem sessão de usuário
FAKE_HOME="$TMPDIR_PC/fakehome"
mkdir -p "$FAKE_HOME"

log "Instalando Panel Colorizer (HOME temporário)"
(
  cd "$TMPDIR_PC/plasma-panel-colorizer"
  export HOME="$FAKE_HOME"
  # install.sh usa kpackagetool6 ou cópia direta dependendo da versão
  if [[ -f install.sh ]]; then
    bash ./install.sh || true
  fi
)

# Copia o plasmoid instalado para /usr/share/ (system-wide)
PLASMOID_SRC=""
if [[ -d "$FAKE_HOME/.local/share/plasma/plasmoids" ]]; then
  PLASMOID_SRC="$FAKE_HOME/.local/share/plasma/plasmoids"
fi

if [[ -n "$PLASMOID_SRC" ]]; then
  log "Movendo Panel Colorizer para /usr/share/plasma/plasmoids/"
  mkdir -p /usr/share/plasma/plasmoids
  cp -r "$PLASMOID_SRC"/. /usr/share/plasma/plasmoids/
else
  # Fallback: copia o diretório package diretamente
  log "Fallback: copiando package/ diretamente para /usr/share/plasma/plasmoids/"
  PACKAGE_DIR="$(find "$TMPDIR_PC/plasma-panel-colorizer" -maxdepth 2 -type d -name 'luisbocanegra.panelcolorizer*' | head -n1 || true)"
  if [[ -n "$PACKAGE_DIR" ]]; then
    mkdir -p /usr/share/plasma/plasmoids
    cp -r "$PACKAGE_DIR" /usr/share/plasma/plasmoids/
  else
    echo "WARN: Panel Colorizer não encontrado após instalação. Pulando." >&2
  fi
fi

log "Panel Colorizer instalado."
SCRIPT
chmod +x build_files/panel-colorizer.sh
```

- [ ] **Step 2: Verificar sintaxe**

```bash
shellcheck build_files/panel-colorizer.sh
```

- [ ] **Step 3: Commit**

```bash
git add build_files/panel-colorizer.sh
git commit -m "feat: add panel-colorizer.sh build script"
```

---

## Task 4: Reescrever build.sh

**Files:**
- Modify: `build_files/build.sh`

Orquestra toda a customização: COPR, repos, pacotes, scripts de assets, e overrides de config KDE via `kwriteconfig6`.

- [ ] **Step 1: Reescrever build.sh**

```bash
cat > build_files/build.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

# ── Trap para garantir limpeza de COPRs mesmo em caso de erro ────────────────
COPRS_ENABLED=()
cleanup_coprs() {
  if [[ ${#COPRS_ENABLED[@]} -gt 0 ]]; then
    for copr in "${COPRS_ENABLED[@]}"; do
      dnf5 -y copr disable "$copr" 2>/dev/null || true
    done
  fi
}
trap cleanup_coprs EXIT

# ── Plugin dnf5-plugins (necessário para copr) ───────────────────────────────
log "Garantindo dnf5-plugins"
dnf5 install -y dnf5-plugins

# ── COPRs ─────────────────────────────────────────────────────────────────────
log "Habilitando COPRs"
dnf5 -y copr enable hazel-bunny/ricing
COPRS_ENABLED+=("hazel-bunny/ricing")

dnf5 -y copr enable matinlotfali/KDE-Rounded-Corners
COPRS_ENABLED+=("matinlotfali/KDE-Rounded-Corners")

dnf5 -y copr enable heroic-games-launcher/heroic-games-launcher
COPRS_ENABLED+=("heroic-games-launcher/heroic-games-launcher")

# ── Repositório VS Code (Microsoft) ──────────────────────────────────────────
log "Adicionando repositório VS Code"
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# ── Instalação de Pacotes ─────────────────────────────────────────────────────
log "Instalando pacotes"
dnf5 install -y --skip-unavailable \
  `# Dev tools` \
  git curl wget unzip tar jq \
  gcc-c++ cmake extra-cmake-modules libplasma-devel \
  code \
  `# Multimídia` \
  ffmpeg \
  gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free gstreamer1-plugins-ugly \
  vlc \
  pipewire-codec-aptx \
  `# Gaming` \
  steam \
  lutris \
  heroic-games-launcher \
  wine winetricks \
  gamemode gamescope \
  `# KDE / Tema Mokka` \
  kvantum qt6ct qt5ct \
  spectacle \
  inter-fonts \
  kwin-effects-forceblur kwin-effects-forceblur-x11 \
  kwin-effect-roundcorners kwin-effect-roundcorners-x11 \
  `# Build deps para Panel Colorizer e assets` \
  rsync

# ── Desabilitar COPRs e repo VS Code ─────────────────────────────────────────
log "Desabilitando COPRs"
cleanup_coprs
trap - EXIT
# Não remove o repo do VS Code para que updates funcionem via rpm-ostree/bootc

# ── Assets do tema Mokka ──────────────────────────────────────────────────────
log "Instalando assets do tema Mokka"
bash /ctx/install-assets.sh

# ── Panel Colorizer ───────────────────────────────────────────────────────────
log "Instalando Panel Colorizer"
bash /ctx/panel-colorizer.sh

# ── Rebuild cache de fontes ───────────────────────────────────────────────────
log "Rebuild cache de fontes"
fc-cache -f /usr/share/fonts/

# ── Config KDE defaults via kwriteconfig6 ────────────────────────────────────
# Garante que /etc/skel/.config existe (pode ter sido criado pelo install-assets.sh)
mkdir -p /etc/skel/.config

log "Aplicando overrides de config KDE no skel"

# Ícones
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group Icons --key Theme "Tela-circle-dracula"

# Fonte monospace
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key fixed "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

# Fonte geral
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key font "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

# Fonte menu
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key menuFont "JetBrains Mono,10,-1,5,50,0,0,0,0,0"

# Fonte toolbar
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
  --group General --key toolBarFont "JetBrains Mono,10,-1,5,75,0,0,0,0,0"

# Cursor
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
  --group Mouse --key cursorTheme "catppuccin-mocha-mauve-cursors"

# KWin: desabilita blur padrão, habilita forceblur e rounded corners
kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key blurEnabled "false"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key forceblurEnabled "true"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key kwin4_effect_forceblurEnabled "true"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key roundcornersEnabled "true"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
  --group Plugins --key kwin4_effect_roundcornersEnabled "true"

# ── Serviços do sistema ───────────────────────────────────────────────────────
log "Habilitando serviços"
systemctl enable podman.socket

log "Build concluído."
SCRIPT
chmod +x build_files/build.sh
```

- [ ] **Step 2: Verificar sintaxe**

```bash
shellcheck build_files/build.sh
```

- [ ] **Step 3: Commit**

```bash
git add build_files/build.sh
git commit -m "feat: rewrite build.sh with full Mokka stack and dev/gaming packages"
```

---

## Task 5: Atualizar disk_config/iso.toml e iso-kde.toml

**Files:**
- Create: `disk_config/iso.toml`
- Modify: `disk_config/iso-kde.toml`

O `build-disk.yml` referencia `./disk_config/iso.toml` para gerar ISOs Anaconda. Precisa apontar para a imagem correta.

**Atenção:** substitua `YOUR_GITHUB_USERNAME` pelo seu usuário real do GitHub antes de commitar.

- [ ] **Step 1: Criar disk_config/iso.toml**

```bash
cat > disk_config/iso.toml << 'EOF'
[customizations.installer.kickstart]
contents = """
%post
bootc switch --mutate-in-place --transport registry ghcr.io/YOUR_GITHUB_USERNAME/image-fedora:latest
%end
"""

[customizations.installer.modules]
enable = [
  "org.fedoraproject.Anaconda.Modules.Storage",
  "org.fedoraproject.Anaconda.Modules.Runtime",
  "org.fedoraproject.Anaconda.Modules.Network",
  "org.fedoraproject.Anaconda.Modules.Security",
  "org.fedoraproject.Anaconda.Modules.Services",
  "org.fedoraproject.Anaconda.Modules.Users",
  "org.fedoraproject.Anaconda.Modules.Timezone"
]

disable = [
  "org.fedoraproject.Anaconda.Modules.Subscription",
]
EOF
```

- [ ] **Step 2: Atualizar iso-kde.toml com a mesma URL**

```bash
cat > disk_config/iso-kde.toml << 'EOF'
[customizations.installer.kickstart]
contents = """
%post
bootc switch --mutate-in-place --transport registry ghcr.io/YOUR_GITHUB_USERNAME/image-fedora:latest
%end
"""

[customizations.installer.modules]
enable = [
  "org.fedoraproject.Anaconda.Modules.Storage",
  "org.fedoraproject.Anaconda.Modules.Runtime",
  "org.fedoraproject.Anaconda.Modules.Network",
  "org.fedoraproject.Anaconda.Modules.Security",
  "org.fedoraproject.Anaconda.Modules.Services",
  "org.fedoraproject.Anaconda.Modules.Users",
  "org.fedoraproject.Anaconda.Modules.Timezone"
]

disable = [
  "org.fedoraproject.Anaconda.Modules.Subscription",
]
EOF
```

- [ ] **Step 3: Substituir YOUR_GITHUB_USERNAME pelo usuário real**

```bash
# Substitua seuusuario pelo username real do GitHub
sed -i 's/YOUR_GITHUB_USERNAME/seuusuario/g' disk_config/iso.toml disk_config/iso-kde.toml
```

- [ ] **Step 4: Verificar**

```bash
grep "ghcr.io" disk_config/iso.toml
# Esperado: linha com ghcr.io/<seuusuario>/image-fedora:latest
```

- [ ] **Step 5: Commit**

```bash
git add disk_config/iso.toml disk_config/iso-kde.toml
git commit -m "feat: update iso configs to point to fedora-kde-custom image"
```

---

## Task 6: Atualizar build.yml

**Files:**
- Modify: `.github/workflows/build.yml`

Atualizar apenas a descrição da imagem. O `IMAGE_NAME` já é gerado automaticamente a partir do nome do repositório.

- [ ] **Step 1: Atualizar IMAGE_DESC**

No arquivo `.github/workflows/build.yml`, linha 17, substituir:

```yaml
# De:
  IMAGE_DESC: "My Customized Universal Blue Image"
  IMAGE_KEYWORDS: "bootc,ublue,universal-blue"

# Para:
  IMAGE_DESC: "Fedora KDE custom image — Aurora base, Mokka theme, dev/gaming packages"
  IMAGE_KEYWORDS: "bootc,ublue,universal-blue,kde,plasma,mokka,catppuccin"
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "chore: update image description and keywords in build.yml"
```

---

## Task 7: Build local e verificação

Verifica que o Containerfile compila sem erros antes de fazer push e disparar o CI.

- [ ] **Step 1: Build local**

```bash
just build
# Equivalente a: podman build --tag fedora-kde-custom:latest .
# Esperado: BUILD COMPLETO sem erros. O build vai demorar ~10-20 min na primeira vez.
```

- [ ] **Step 2: Verificar linting do bootc**

O `bootc container lint` já está no Containerfile. Se o build passou, o lint passou. Verificar explicitamente:

```bash
podman run --rm fedora-kde-custom:latest bootc container lint
# Esperado: sem erros críticos
```

- [ ] **Step 3: Verificar assets instalados**

```bash
podman run --rm fedora-kde-custom:latest bash -c "
  echo '=== Fontes ===' && ls /usr/share/fonts/JetBrainsMonoNerdFont/ | head -5
  echo '=== Cursores ===' && ls /usr/share/icons/ | grep catppuccin
  echo '=== Ícones ===' && ls /usr/share/icons/ | grep Tela
  echo '=== Wallpapers ===' && ls /usr/share/wallpapers/ | head -5
  echo '=== Look and Feel ===' && ls /usr/share/plasma/look-and-feel/ | grep -i mokka
  echo '=== Panel Colorizer ===' && ls /usr/share/plasma/plasmoids/ | grep -i panel
  echo '=== skel config ===' && ls /etc/skel/.config/
"
```

- [ ] **Step 4: Verificar packages instalados**

```bash
podman run --rm fedora-kde-custom:latest bash -c "
  rpm -q code steam lutris wine gamemode vlc kvantum kwin-effects-forceblur kwin-effect-roundcorners
"
# Esperado: todos os pacotes listados com versão
```

- [ ] **Step 5: Verificar kwinrc no skel**

```bash
podman run --rm fedora-kde-custom:latest bash -c "
  cat /etc/skel/.config/kwinrc | grep -A5 '\[Plugins\]'
"
# Esperado: blurEnabled=false, forceblurEnabled=true ou kwin4_effect_forceblurEnabled=true
```

- [ ] **Step 6: Commit final se tudo passou**

```bash
git status
# Todos os arquivos já devem estar commitados nesse ponto
git log --oneline -8
```

---

## Notas Pós-Deploy

- Após o push para `main`, o GitHub Actions vai publicar a imagem em `ghcr.io/<usuario>/image-fedora:latest`
- Para instalar via ISO: `just build-iso` (requer a imagem publicada no GHCR para o kickstart funcionar)
- Para fazer `bootc switch` numa máquina existente:
  ```bash
  sudo bootc switch ghcr.io/<usuario>/image-fedora:latest
  ```
- O tema Mokka aplicará visualmente após o **primeiro login** de um novo usuário (os configs em `/etc/skel/` são aplicados na criação do home)
- Usuários existentes precisam copiar os configs manualmente de `/etc/skel/.config/` ou rodar o `mokka-setup.sh` original
