#!/bin/bash
set -euo pipefail

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*" >&2; }

export TMPDIR_ASSETS
TMPDIR_ASSETS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ASSETS"' EXIT

# curl wrapper with retry for transient network failures in container builds
fetch() { curl -L --fail --retry 3 --retry-delay 5 "$@"; }

# Verify SHA256 checksum
verify_checksum() {
    local file="$1" expected="$2"
    local actual
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
    if [[ "$actual" != "$expected" ]]; then
        echo "FATAL: checksum mismatch para $(basename "$file")"
        echo "  Esperado: $expected"
        echo "  Obtido:   $actual"
        echo "  Ficheiro: $file"
        exit 1
    fi
    echo "  SHA256 OK: $(basename "$file")"
}

# ── Funções de instalação ────────────────────────────────────────────────────
# Cada função instala um asset. Recebem $ARCHIVE (ficheiro descarregado) e
# $TMPDIR_ASSETS (dir temporário) no ambiente, definidos pelo loop principal.
# Substituem o antigo eval de strings do manifesto: lintáveis e debugáveis.

_install_starship() {
    tar -xzf "$ARCHIVE" -C /usr/bin starship
    chmod 0755 /usr/bin/starship
    /usr/bin/starship --version
}

_install_jetbrains_mono() {
    local dir=/usr/share/fonts/JetBrainsMonoNerdFont
    mkdir -p "$dir"
    unzip -qo "$ARCHIVE" -d "$dir"
    # Mantém só as variantes Nerd Font (remove os .ttf originais sem patch)
    find "$dir" -name '*.ttf' ! -name '*NerdFont*' -delete 2>/dev/null || true
    # Mantém apenas os pesos essenciais (Regular/Bold/Italic/BoldItalic) em
    # versão normal e Mono. As 90+ variantes restantes (NL, ExtraLight, Thin,
    # Light, Medium, SemiBold, ExtraBold, etc.) aumentam a ISO em ~200 MB sem
    # ganho prático para o uso desta imagem.
    keep_re='JetBrainsMono(NerdFontMono|NerdFont)-(Regular|Bold|Italic|BoldItalic)\.ttf$'
    find "$dir" -name '*.ttf' -type f | while read -r font; do
        if [[ ! "$(basename "$font")" =~ $keep_re ]]; then
            rm -f "$font"
        fi
    done
    fc-cache -f "$dir"
}

_install_catppuccin_cursors() {
    unzip -qo "$ARCHIVE" -d /usr/share/icons/
}

_install_tela_circle() {
    tar -xzf "$ARCHIVE" -C "$TMPDIR_ASSETS"
    bash "$TMPDIR_ASSETS/Tela-circle-icon-theme-${TELA_CIRCLE_VERSION}/install.sh" \
        -d /usr/share/icons -c dracula
    # O skel usa Tela-circle-dracula-dark; removemos só a variante light.
    rm -rf /usr/share/icons/Tela-circle-dracula-light
}

# Tema COSMIC Catppuccin Mocha/Mauve — substituto do Mokka (KDE).
#
# O COSMIC guarda config em ficheiros RON, um por chave, sob
# /usr/share/cosmic/<app-id>/v1/<chave> (fallback system-wide usado pelo
# cosmic-config quando o utilizador não tem override próprio). O repositório
# catppuccin/cosmic-desktop publica o tema como um único ThemeBuilder RON
# (formato "importável" via cosmic-settings), cujo schema de topo (palette,
# bg_color, accent, success, warning, destructive, window_hint, neutral_tint,
# text_tint, primary_container_bg, secondary_container_bg, is_frosted, gaps,
# active_hint, corner_radii, spacing) foi confirmado, campo a campo, contra o
# /usr/share/cosmic/com.system76.CosmicTheme.Dark.Builder/v1/ real da imagem
# cosmic-atomic — os dois batem exactamente, por isso a decomposição abaixo é
# uma cópia directa (sem risco de mismatch de schema).
#
# Para o tema efectivamente RENDERIZADO (CosmicTheme.Dark, não o Builder), o
# cálculo dos estados hover/pressed/disabled/etc. de cada cor é feito pelo
# crate cosmic-theme (Rust) e não está disponível neste ambiente de build.
# Aproximamo-lo com escalonamento de luminosidade em HSL, calibrado empiricamente
# a partir do par (accent seed → accent computado) do tema "cosmic-dark" de
# origem — aproximação best-effort, não os valores exactos que o COSMIC
# produziria; ajustar depois de testar visualmente numa sessão real.
_install_catppuccin_cosmic() {
    tar -xzf "$ARCHIVE" -C "$TMPDIR_ASSETS"
    local dir="$TMPDIR_ASSETS/cosmic-desktop-${CATPPUCCIN_COSMIC_COMMIT}"
    local settings_ron="$dir/themes/cosmic-settings/catppuccin-mocha-mauve+round.ron"
    local term_ron="$dir/themes/cosmic-term/catppuccin-mocha.ron"
    if [[ ! -f "$settings_ron" ]]; then
        warn "Tema catppuccin-mocha-mauve+round.ron não encontrado em $dir. Pulando."
        return
    fi

    python3 "$(dirname "$0")/../assets/cosmic-theme-derive.py" "$settings_ron"

    # cosmic-term: sem diretório de defaults system-wide nesta base (a app não
    # traz /usr/share/cosmic/com.system76.CosmicTerm/); fica disponível para
    # import manual em ~/.config caso um utilizador queira aplicá-lo.
    if [[ -f "$term_ron" ]]; then
        install -Dm644 "$term_ron" /usr/share/cosmic-term-themes/catppuccin-mocha.ron
    fi

    # Wallpaper: reaproveita um dos assets já incluídos pelo pacote
    # cosmic-wallpapers da imagem base (nebulosa escura, combina com a
    # paleta Mocha/Mauve) em vez de trazer um novo binário de imagem.
    local wallpaper=/usr/share/backgrounds/cosmic/orion_nebula_nasa_heic0601a.jpg
    if [[ -f "$wallpaper" ]]; then
        install -Dm644 /dev/stdin /usr/share/cosmic/com.system76.CosmicBackground/v1/all <<EOF
(
    output: "all",
    source: Path("$wallpaper"),
    filter_by_theme: false,
    rotation_frequency: 3600,
    filter_method: Lanczos,
    scaling_mode: Zoom,
    sampling_method: Alphanumeric,
)
EOF
    else
        warn "Wallpaper padrão do cosmic-wallpapers não encontrado: $wallpaper"
    fi
}

_install_catppuccin_gtk() {
    mkdir -p /usr/share/themes
    unzip -qo "$ARCHIVE" -d /usr/share/themes/
}

_install_winapps() {
    local prefix="winapps-${WINAPPS_COMMIT}"
    tar -xzf "$ARCHIVE" -C "$TMPDIR_ASSETS" \
        "${prefix}/bin/winapps" \
        "${prefix}/apps" \
        "${prefix}/install"
    install -Dm755 "$TMPDIR_ASSETS/${prefix}/bin/winapps" /usr/bin/winapps
    sed -i 's|^readonly SYS_APP_PATH=.*|readonly SYS_APP_PATH="/usr/share/winapps"|' /usr/bin/winapps
    mkdir -p /usr/share/winapps
    cp -a "$TMPDIR_ASSETS/${prefix}/apps" /usr/share/winapps/
    cp -a "$TMPDIR_ASSETS/${prefix}/install" /usr/share/winapps/
}

# Load the asset manifest
# shellcheck source=../assets/assets-manifest.sh
source "$(dirname "$0")/../assets/assets-manifest.sh"

CURRENT_ARCH="$(uname -m)"

for entry in "${ASSETS[@]}"; do
    IFS='|' read -r name url sha256 arch_filter install_fn <<< "$entry"

    if [[ -n "$arch_filter" && "$CURRENT_ARCH" != "$arch_filter" ]]; then
        warn "Arquitetura $CURRENT_ARCH sem binário pinado para $name — ignorado."
        continue
    fi

    if ! declare -F "$install_fn" >/dev/null; then
        echo "FATAL: função de instalação '$install_fn' não definida para o asset '$name'" >&2
        exit 1
    fi

    log "Instalando $name"
    export ARCHIVE="$TMPDIR_ASSETS/${name}.download"
    fetch -o "$ARCHIVE" "$url"
    verify_checksum "$ARCHIVE" "$sha256"

    "$install_fn"
done

log "Assets instalados com sucesso."
