//! Deriva o tema COSMIC a partir de um ThemeBuilder .ron e escreve os ficheiros
//! de config (Builder + tema derivado) num XDG_CONFIG_HOME apontado para o skel.
//!
//! Uso: cosmic-theme-gen <theme-builder.ron>
//! Requer XDG_CONFIG_HOME definido (ex.: /etc/skel/.config) — o cosmic-config
//! escreve em $XDG_CONFIG_HOME/cosmic/<component>/v<version>/<key>.

use cosmic_config::CosmicConfigEntry;
use cosmic_theme::{Theme, ThemeBuilder};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args()
        .nth(1)
        .expect("uso: cosmic-theme-gen <theme-builder.ron>");
    let ron_str = std::fs::read_to_string(&path)?;
    let builder: ThemeBuilder = ron::de::from_str(&ron_str)?;

    // Builder = fonte de verdade (mostrado em Definições → Aparência).
    let builder_config = ThemeBuilder::dark_config()?;
    builder.write_entry(&builder_config)?;

    // Tema derivado = o que o cosmic-comp e as apps realmente lêem.
    let theme = builder.build();
    let theme_config = Theme::dark_config()?;
    theme.write_entry(&theme_config)?;

    eprintln!("cosmic-theme-gen: tema + builder escritos a partir de {path}");
    Ok(())
}
