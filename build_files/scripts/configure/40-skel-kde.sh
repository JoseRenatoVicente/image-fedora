#!/bin/bash
# Skel + defaults KDE: limpa cópias user-local redundantes do Mokka, instala os
# serviços de primeiro arranque no skel, e aplica patches nos ficheiros do pacote
# Mokka. As configs de skel (kwinrc, kdeglobals, etc.) vivem em overlay/etc/skel.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

mkdir -p /etc/skel/.config

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

# First-boot user services
mkdir -p /etc/skel/.config/systemd/user/timers.target.wants

for script in fedora-shell-setup fedora-dev-setup fedora-brew-setup; do
    install -Dm644 /ctx/skel/.config/systemd/user/"${script}".service \
        /etc/skel/.config/systemd/user/"${script}".service
    install -Dm644 /ctx/skel/.config/systemd/user/"${script}".timer \
        /etc/skel/.config/systemd/user/"${script}".timer
    ln -sf ../"${script}".timer \
        /etc/skel/.config/systemd/user/timers.target.wants/"${script}".timer
done

install -Dm755 /ctx/skel/.local/bin/kwin-vm-compat.sh \
    /usr/libexec/kwin-vm-compat.sh
install -Dm644 /ctx/skel/.config/autostart/kwin-vm-compat.desktop \
    /etc/xdg/autostart/kwin-vm-compat.desktop

install -Dm644 /ctx/skel/.config/plasma-org.kde.plasma.desktop-appletsrc \
    /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc

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
