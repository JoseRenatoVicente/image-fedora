#!/usr/bin/python3
"""Decompõe um ThemeBuilder RON do catppuccin/cosmic-desktop nos ficheiros
system-wide do cosmic-config (um por chave, sob /usr/share/cosmic/<app-id>/v1/).

Uso: cosmic-theme-derive.py <caminho-para-o-ron>

Ver o comentário de _install_catppuccin_cosmic em install-assets.sh para o
racional completo (schema confirmado ao vivo; derivação de hover/pressed/etc.
é uma aproximação HSL, não o algoritmo real do crate cosmic-theme).
"""
import os
import re
import sys
import colorsys

BUILDER_DIR = "/usr/share/cosmic/com.system76.CosmicTheme.Dark.Builder/v1"
THEME_DIR = "/usr/share/cosmic/com.system76.CosmicTheme.Dark/v1"

# Campos do ThemeBuilder copiados tal-e-qual (mesmo nome/schema) para o Builder.
BUILDER_FIELDS = [
    "palette", "bg_color", "text_tint", "accent", "success", "warning",
    "destructive", "window_hint", "neutral_tint", "primary_container_bg",
    "secondary_container_bg", "is_frosted", "gaps", "active_hint",
    "corner_radii", "spacing",
]


def extract_field(text, name):
    """Devolve o texto bruto do valor associado a 'name: <valor>' respeitando
    parênteses aninhados (RON não é sensível a espaço em branco)."""
    idx = text.index(name + ":") + len(name) + 1
    while text[idx] in " \n\t":
        idx += 1
    depth = 0
    i = idx
    while True:
        c = text[i]
        if c in "([":
            depth += 1
        elif c in ")]":
            if depth == 0:
                break
            depth -= 1
        elif c == "," and depth == 0:
            break
        i += 1
    return text[idx:i].strip()


def parse_color(raw):
    r = float(re.search(r"red\s*:\s*([-\d.eE]+)", raw).group(1))
    g = float(re.search(r"green\s*:\s*([-\d.eE]+)", raw).group(1))
    b = float(re.search(r"blue\s*:\s*([-\d.eE]+)", raw).group(1))
    return (r, g, b)


def fmt_color(rgba):
    r, g, b, a = rgba
    return f"(red:{r},green:{g},blue:{b},alpha:{a})"


def clamp(x):
    return max(0.0, min(1.0, x))


def scale_lightness(rgb, factor):
    r, g, b = rgb
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = clamp(l * factor)
    return colorsys.hls_to_rgb(h, l, s)


def derive_colorset(rgb):
    r, g, b = rgb
    base = (r, g, b, 1.0)
    hover = (*scale_lightness(rgb, 0.92), 1.0)
    pressed = (*scale_lightness(rgb, 0.57), 1.0)
    on_disabled = (*scale_lightness(rgb, 0.50), 1.0)
    luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    on = (0.0, 0.0, 0.0, 1.0) if luminance > 0.5 else (1.0, 1.0, 1.0, 1.0)
    return {
        "base": base,
        "hover": hover,
        "pressed": pressed,
        "selected": hover,
        "selected_text": base,
        "focus": base,
        "divider": on,
        "on": on,
        "disabled": base,
        "on_disabled": on_disabled,
        "border": base,
        "disabled_border": (r, g, b, 0.5),
    }


def fmt_colorset(cs):
    order = ["base", "hover", "pressed", "selected", "selected_text", "focus",
              "divider", "on", "disabled", "on_disabled", "border", "disabled_border"]
    inner = ",".join(f"{k}:{fmt_color(cs[k])}" for k in order)
    return f"({inner})"


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    print(f"  escrito: {path}")


def patch_background_base(theme_dir, bg_rgb):
    """Substitui só o campo 'base' do ficheiro 'background' existente (stock),
    preservando component/divider/on/small_widget tal como vieram da imagem base."""
    path = f"{theme_dir}/background"
    if not os.path.isfile(path):
        raise RuntimeError(
            f"{path} não existe — esperado vir da imagem base cosmic-atomic "
            "(pacote cosmic-config-fedora); layout do tema pode ter mudado"
        )
    with open(path) as f:
        text = f.read()
    new_base = f"base:{fmt_color((*bg_rgb, 1.0))}"
    patched, n = re.subn(r"base:\s*\([^()]*\)", new_base, text, count=1)
    if n != 1:
        raise RuntimeError(f"não foi possível localizar o campo 'base' em {path}")
    write(path, patched)


def main():
    ron_path = sys.argv[1]
    with open(ron_path) as f:
        text = f.read()

    raw = {name: extract_field(text, name) for name in BUILDER_FIELDS}

    print(f"== Builder system-wide default: {BUILDER_DIR} ==")
    for name in BUILDER_FIELDS:
        write(f"{BUILDER_DIR}/{name}", raw[name])

    print(f"== Theme (built) system-wide default: {THEME_DIR} ==")
    write(f"{THEME_DIR}/name", '"Catppuccin-Mocha-Mauve"')

    # palette: Builder guarda "Dark((...))"; Theme guarda só o conteúdo interno.
    palette_inner = raw["palette"]
    assert palette_inner.startswith("Dark(") and palette_inner.endswith(")")
    write(f"{THEME_DIR}/palette", palette_inner[len("Dark("):-1])

    bg_rgb = parse_color(raw["bg_color"])
    patch_background_base(THEME_DIR, bg_rgb)

    accent_rgb = parse_color(raw["accent"])
    accent_ron = fmt_colorset(derive_colorset(accent_rgb))
    write(f"{THEME_DIR}/accent", accent_ron)
    write(f"{THEME_DIR}/accent_button", accent_ron)

    warning_rgb = parse_color(raw["warning"])
    warning_ron = fmt_colorset(derive_colorset(warning_rgb))
    write(f"{THEME_DIR}/warning", warning_ron)
    write(f"{THEME_DIR}/warning_button", warning_ron)

    success_rgb = parse_color(raw["success"])
    success_ron = fmt_colorset(derive_colorset(success_rgb))
    write(f"{THEME_DIR}/success", success_ron)
    write(f"{THEME_DIR}/success_button", success_ron)

    destructive_rgb = parse_color(raw["destructive"])
    write(f"{THEME_DIR}/destructive", fmt_colorset(derive_colorset(destructive_rgb)))

    window_hint_rgb = parse_color(raw["window_hint"])
    write(f"{THEME_DIR}/window_hint", f"Some({fmt_color((*window_hint_rgb, 1.0))})")

    for name in ("gaps", "active_hint", "is_frosted"):
        write(f"{THEME_DIR}/{name}", raw[name])

    print("Tema Catppuccin Mocha Mauve aplicado (Builder + Theme system-wide).")


if __name__ == "__main__":
    main()
