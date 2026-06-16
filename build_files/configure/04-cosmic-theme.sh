# 04-cosmic-theme.sh — COSMIC theme derivation via Rust (Catppuccin Mocha Mauve).
# Sourced by build-configure.sh (not executed directly).

# ─── Derivar tema COSMIC (Catppuccin Mocha Mauve) ─────────────────────────────
# O tema derivado (CosmicTheme.Dark/v1/*, cores calculadas via OKLCH) é o que o
# cosmic-comp e as apps lêem. É gerado a partir do .ron ThemeBuilder do Catppuccin
# com a MESMA lógica do cosmic-settings (ThemeBuilder::build), via um helper Rust
# compilado AQUI. cargo/rust/gcc são removidos no cleanup (não ficam na imagem).
echo "::group:: COSMIC theme derivation"
dnf5 install -y --setopt=install_weak_deps=False cargo gcc
cp -r /ctx/cosmic-theme-gen /tmp/cosmic-theme-gen
(
    cd /tmp/cosmic-theme-gen
    CARGO_HOME=/tmp/cargo \
    CARGO_TARGET_DIR=/tmp/cosmic-theme-gen/target \
    XDG_CONFIG_HOME=/etc/skel/.config \
        cargo run --release -- /usr/share/cosmic-mokka/theme-builder.ron
)
# Verifica que o tema derivado foi escrito (accent é o ficheiro-chave do look)
[[ -s /etc/skel/.config/cosmic/com.system76.CosmicTheme.Dark/v1/accent ]] \
    || { echo "FATAL: tema COSMIC não foi derivado"; exit 1; }
echo "✓ tema COSMIC derivado em /etc/skel/.config/cosmic/"
echo "::endgroup::"
