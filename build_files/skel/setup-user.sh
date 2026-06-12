#!/usr/bin/env bash
# setup-user.sh — Configuração de ambiente do usuário (primeira vez)
# Execute: bash ~/setup-user.sh
# Instala: NVM/Node.js, Oh My Zsh + Powerlevel10k, LazyDocker,
#          Homebrew + terraform/kubectl/flux/talosctl, Flatpaks, aliases
set -euo pipefail

log()  { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*" >&2; }
ok()   { printf "\033[1;32m OK:\033[0m %s\n" "$*"; }

# ── Função segura para baixar e executar scripts ──────────────────────────────
# Baixa o script, exibe hash para auditoria, e pede confirmação antes de executar
safe_curl_sh() {
  local url="$1" desc="$2" expected_sha="${3:-}"
  shift 2; [[ -n "$expected_sha" ]] && shift || true
  local tmpscript
  tmpscript="$(mktemp)"
  trap 'rm -f -- "$tmpscript"' RETURN
  curl -fsSL "$url" -o "$tmpscript"
  local hash
  hash="$(sha256sum "$tmpscript" | cut -d' ' -f1)"
  echo "  Script: $desc"
  echo "  URL:    $url"
  echo "  SHA256: $hash"
  if [[ -n "$expected_sha" ]]; then
    if [[ "$hash" != "$expected_sha" ]]; then
      warn "Checksum mismatch para $desc!"
      echo "  Esperado: $expected_sha"
      echo "  Obtido:   $hash"
      warn "Isto pode indicar um compromisso do script. Abortando."
      return 1
    fi
    ok "Checksum verificado"
  else
    echo "  (sem checksum esperado — verificação manual)"
  fi
  echo ""
  read -rp "  Executar? [S/n] " resp
  if [[ "${resp,,}" == "n" ]]; then
    warn "Instalação de $desc cancelada pelo usuário"
    return 1
  fi
  bash "$tmpscript" "$@"
}

# ── Versões e checksums dos scripts curl-to-bash ─────────────────────────────
# Atualizar ao mudar versões. Para obter o SHA256:
#   curl -fsSL <url> | sha256sum
OMZ_COMMIT="c954bbb168fc645592c50017de0d0e138db8df5f"
OMZ_SHA256="21043aec5b791ce4835479dc33ba2f92155946aeafd54604a8c83522627cc803"
BREW_COMMIT="93a25fd2d2fdb86422303c292b9223f84ef23eaf"
BREW_SHA256="17f204b128869ec71e6b650051f1e65ef5b74cf994c2ff8b919103241554dd2f"
LAZYDOCKER_COMMIT="7e7aadc2071d58031bf2daafca1fbd4093efc23f"
LAZYDOCKER_SHA256="57a1a5ca34097da604e19d3b5d0689a47037604d1ab9f8c1bcd0a63bab427359"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Não rode como root. Execute como seu usuário normal."
  exit 1
fi

STATE_DIR="$HOME/.local/share/fedora-kde-setup"
mkdir -p "$STATE_DIR"

done_already() { [[ -f "$STATE_DIR/$1" ]]; }
mark_done()    { touch "$STATE_DIR/$1"; }

# ── Flatpaks ──────────────────────────────────────────────────────────────────
log "Instalando Flatpaks"
if ! done_already "flatpaks"; then
  flatpak remote-add --user --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

  FLATPAKS=(
    com.discordapp.Discord
    org.telegram.desktop
    md.obsidian.Obsidian
    io.dbeaver.DBeaverCommunity
    com.slack.Slack
    org.qbittorrent.qBittorrent
    com.github.IsmaelMartinez.teams_for_linux
    org.torproject.torbrowser-launcher
    com.heroicgameslauncher.hgl
    com.valvesoftware.Steam
    com.google.Chrome
    org.videolan.VLC
    net.lutris.Lutris
  )

  for pkg in "${FLATPAKS[@]}"; do
    flatpak install --user -y flathub "$pkg" || warn "Falhou: $pkg"
  done
  mark_done "flatpaks"
  ok "Flatpaks instalados"
else
  ok "Flatpaks já instalados, pulando"
fi

# ── NVM + Node.js LTS + npm globals ──────────────────────────────────────────
log "Instalando NVM"
if ! done_already "nvm"; then
  NVM_VERSION="v0.40.3"
  safe_curl_sh "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" "NVM ${NVM_VERSION}"
  mark_done "nvm"
  ok "NVM instalado"
else
  ok "NVM já instalado, pulando"
fi

# Carrega NVM para uso imediato
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

log "Instalando Node.js LTS"
if ! done_already "nodejs"; then
  nvm install --lts
  nvm use --lts
  nvm alias default node
  mark_done "nodejs"
  ok "Node.js LTS instalado"
else
  ok "Node.js já instalado, pulando"
fi

log "Instalando pacotes npm globais"
if ! done_already "npm-globals" && command -v npm &>/dev/null; then
  npm install -g pnpm
  npm install -g @github/copilot-cli || warn "@github/copilot-cli falhou (nome pode ter mudado)"
  npm install -g opencode-ai@latest || warn "opencode-ai falhou"
  mark_done "npm-globals"
  ok "npm globals instalados"
fi

# ── Oh My Zsh + Powerlevel10k + plugins ──────────────────────────────────────
log "Instalando Oh My Zsh"
if ! done_already "omz"; then
  RUNZSH=no CHSH=no safe_curl_sh \
    "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${OMZ_COMMIT}/tools/install.sh" "Oh My Zsh (${OMZ_COMMIT:0:8})" "$OMZ_SHA256"
  mark_done "omz"
  ok "Oh My Zsh instalado"
else
  ok "Oh My Zsh já instalado, pulando"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

log "Instalando Powerlevel10k"
if ! done_already "p10k"; then
  git clone --depth=1 --branch v1.20.0 https://github.com/romkatv/powerlevel10k.git \
    "$ZSH_CUSTOM/themes/powerlevel10k" 2>/dev/null || true
  mark_done "p10k"
  ok "Powerlevel10k instalado"
fi

log "Instalando plugins zsh"
if ! done_already "zsh-plugins"; then
  git clone --depth=1 --branch v0.7.1 https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || true
  git clone --depth=1 --branch 0.8.0 https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true
  git clone --depth=1 --branch 0.36.0 https://github.com/zsh-users/zsh-completions \
    "$ZSH_CUSTOM/plugins/zsh-completions" 2>/dev/null || true
  mark_done "zsh-plugins"
  ok "Plugins zsh instalados"
fi

log "Configurando .zshrc"
if ! done_already "zshrc"; then
  ZSHRC="$HOME/.zshrc"
  # Garante que existe
  [[ -f "$ZSHRC" ]] || touch "$ZSHRC"

  # Troca tema para powerlevel10k
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC"

  # Troca plugins
  sed -i 's/^plugins=(.*/plugins=(git docker emoji kubectl terraform zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' "$ZSHRC"

  # Adiciona source do NVM se não existir
  if ! grep -q 'NVM_DIR' "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
EOF
  fi

  # Aliases
  if ! grep -q 'alias docker=' "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# Aliases
alias docker='podman'
alias docker-compose='podman-compose'
alias ls='eza --icons'
alias ll='eza -la --icons'
alias lt='eza --tree --icons'
EOF
  fi

  mark_done "zshrc"
  ok ".zshrc configurado"
fi

log "Mudando shell padrão para zsh"
if [[ "$SHELL" != "$(command -v zsh)" ]]; then
  chsh -s "$(command -v zsh)" || warn "Não foi possível mudar o shell. Rode: chsh -s $(command -v zsh)"
else
  ok "zsh já é o shell padrão"
fi

# ── eza (pré-instalado na imagem base via dnf) ───────────────────────────────
if command -v eza &>/dev/null; then
  ok "eza já disponível (instalado na imagem base)"
else
  warn "eza não encontrado — deveria estar na imagem base (dnf install eza)"
fi

# ── LazyDocker ────────────────────────────────────────────────────────────────
log "Instalando LazyDocker"
if ! done_already "lazydocker"; then
  mkdir -p "$HOME/bin"
  safe_curl_sh "https://raw.githubusercontent.com/jesseduffield/lazydocker/${LAZYDOCKER_COMMIT}/scripts/install_update_linux.sh" "LazyDocker (${LAZYDOCKER_COMMIT:0:8})" "$LAZYDOCKER_SHA256"
  mark_done "lazydocker"
  ok "LazyDocker instalado em ~/bin"
fi

# ── Homebrew + tools de infra ─────────────────────────────────────────────────
log "Instalando Homebrew"
if ! done_already "homebrew"; then
  NONINTERACTIVE=1 safe_curl_sh \
    "https://raw.githubusercontent.com/Homebrew/install/${BREW_COMMIT}/install.sh" "Homebrew (${BREW_COMMIT:0:8})" "$BREW_SHA256"
  mark_done "homebrew"
  ok "Homebrew instalado"
else
  ok "Homebrew já instalado, pulando"
fi

# Carrega brew para uso imediato
if [[ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -f "$HOME/.linuxbrew/bin/brew" ]]; then
  eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
fi

log "Instalando terraform, kubectl, flux, talosctl via Homebrew"
if ! done_already "brew-tools" && command -v brew &>/dev/null; then
  brew install terraform kubernetes-cli || warn "terraform/kubectl falharam"
  brew install fluxcd/tap/flux || warn "flux falhou"
  brew install siderolabs/tap/talosctl || warn "talosctl falhou"

  # Adiciona brew ao .zshrc se não existir
  if ! grep -q 'linuxbrew' "$HOME/.zshrc" 2>/dev/null; then
    cat >> "$HOME/.zshrc" << 'EOF'

# Homebrew
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null || true)"
EOF
  fi

  mark_done "brew-tools"
  ok "Homebrew tools instalados"
fi

# ── Finalização ───────────────────────────────────────────────────────────────
log "Setup concluído!"
echo
echo "  Próximos passos:"
echo "  1. Faça logout/login para aplicar o shell zsh"
echo "  2. Execute 'p10k configure' para configurar o Powerlevel10k"
echo "  3. Instale o Go manualmente se necessário: https://go.dev/dl/"
echo
echo "  Estado salvo em: $STATE_DIR"
echo "  Para re-executar uma etapa, delete o arquivo correspondente em $STATE_DIR"
