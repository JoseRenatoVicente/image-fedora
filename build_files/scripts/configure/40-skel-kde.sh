#!/bin/bash
# Skel + defaults KDE: limpa cópias user-local redundantes do Mokka, reaplica
# defaults locais após a importação do skel upstream, e aplica patches nos
# ficheiros do pacote Mokka. As configs de skel vivem em overlay/etc/skel.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

rm -f /etc/skel/.config/autostart/initial-setup.desktop \
      /etc/skel/.config/autostart/initial-setup.sh \
      /etc/skel/.config/starship-mokka.toml
rm -rf /etc/skel/.config/environment.d \
       /etc/skel/.config/fish \
       /etc/skel/.local/share/plasma/look-and-feel/Mokka \
       /etc/skel/.local/share/plasma/desktoptheme/Mokka \
       /etc/skel/.local/share/color-schemes/Mokka.colors \
       /etc/skel/.local/share/wallpapers/Mokka-tree \
       /etc/skel/.local/share/konsole/Mokka.colorscheme \
       /etc/skel/.local/share/Kvantum/Mokka

# Shell padrão para novos utilizadores: zsh (evita chsh no primeiro login)
sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd

# install-assets.sh imports Garuda Mokka's upstream /etc/skel after the overlay.
# Re-apply local files that intentionally diverge from upstream Mokka defaults.
install -Dm644 /ctx/overlay/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc \
    /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
install -Dm644 /ctx/overlay/etc/skel/.config/kscreenlockerrc \
    /etc/skel/.config/kscreenlockerrc
install -Dm644 /ctx/overlay/etc/skel/.config/gtk-3.0/settings.ini \
    /etc/skel/.config/gtk-3.0/settings.ini
install -Dm644 /ctx/overlay/etc/skel/.config/gtk-4.0/settings.ini \
    /etc/skel/.config/gtk-4.0/settings.ini

rm -rf /usr/share/plasma/look-and-feel/Mokka/contents/layouts

sed -i 's/\bsizes\b/size/g' \
    /usr/share/plasma/look-and-feel/Mokka/contents/splash/Splash.qml

sed -i 's/^Theme=Catppuccin-Mocha-Mauve-splash$/Theme=Mokka/' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

sed -i 's|^Image=file:///usr/share/wallpapers/garuda-mokka/Mokka-tree\.jpg$|Image=file:///usr/share/wallpapers/Mokka-tree/|' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

# O tema Mokka herdou o nome do cursor do Catppuccin original (CamelCase com dashes),
# mas o pacote instala o diretório em lowercase. Corrigir para evitar falha no greeter.
sed -i 's/^cursorTheme=Catppuccin-Mocha-Mauve-Cursors$/cursorTheme=catppuccin-mocha-mauve-cursors/' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

touch /etc/plasma-setup-done

setfattr -n user.component -v "skel" \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup
setfattr -n user.update-interval -v "monthly" \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup

if [[ -f /usr/share/Kvantum/Mokka/Mokka.kvconfig ]]; then
    sed -i \
        -e 's/^composite=.*/composite=false/' \
        -e 's/^translucent_windows=.*/translucent_windows=false/' \
        -e 's/^blurring=.*/blurring=false/' \
        /usr/share/Kvantum/Mokka/Mokka.kvconfig
fi
