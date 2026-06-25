#!/bin/bash
# Skel + defaults KDE: limpa cópias user-local redundantes do Mokka, instala os
# serviços de primeiro arranque no skel, e escreve os defaults de tema, KWin,
# lock screen, GTK e gestão de energia via kwriteconfig6.
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

for script in fedora-flatpak-setup fedora-shell-setup fedora-dev-setup fedora-brew-setup; do
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

kwriteconfig6 --file /etc/skel/.config/krunnerrc \
    --group General --key FreeFloating "true"

sed -i 's/\bsizes\b/size/g' \
    /usr/share/plasma/look-and-feel/Mokka/contents/splash/Splash.qml

sed -i 's/^Theme=Catppuccin-Mocha-Mauve-splash$/Theme=Mokka/' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

sed -i 's|^Image=file:///usr/share/wallpapers/garuda-mokka/Mokka-tree\.jpg$|Image=file:///usr/share/wallpapers/Mokka-tree/|' \
    /usr/share/plasma/look-and-feel/Mokka/contents/defaults

kwriteconfig6 --file /etc/skel/.config/ksplashrc \
    --group KSplash --key Theme "Mokka"

touch /etc/plasma-setup-done

kwriteconfig6 --file /etc/skel/.config/plasma-welcomerc \
    --group General --key ShowOnStartup "false"
kwriteconfig6 --file /etc/skel/.config/plasma-welcomerc \
    --group General --key LastSeenVersion "99.0"

setfattr -n user.component -v "skel" \
    /usr/libexec/fedora-flatpak-setup \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup
setfattr -n user.update-interval -v "monthly" \
    /usr/libexec/fedora-flatpak-setup \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup

# ── Tema Mokka ────────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/plasmarc \
    --group Theme --key name "Mokka"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key ColorScheme "Mokka"
# Cor de realce fixa (Catppuccin Mocha Mauve). Sem este valor, o plasma_accentcolor_service
# tenta usar o módulo kded "kameleon" (de kdeplasma-addons) para extrair a cor do papel
# de parede — kameleon não está instalado (kdeplasma-addons puxa qt6-qtwebengine, 290 MB),
# gerando o aviso "could not find kded module id 'kameleon'" a cada boot.
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key AccentColor "203,166,247"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group KDE --key LookAndFeelPackage "Mokka"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group KDE --key widgetStyle "kvantum-dark"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group Icons --key Theme "Tela-circle-dracula-dark"

kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key fixed "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key font "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key menuFont "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals \
    --group General --key toolBarFont "JetBrains Mono,10,-1,5,75,0,0,0,0,0"

kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group Mouse --key cursorTheme "catppuccin-mocha-mauve-cursors"
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group "Libinput" --group "default" --key NaturalScroll "true"
kwriteconfig6 --file /etc/skel/.config/kcminputrc \
    --group "Libinput" --group "default" --key PointerAcceleration "0.45"

# ── KWin ──────────────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key library "org.kde.kwin.aurorae"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key theme "__aurorae__svg__CatppuccinMocha-Classic"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key BorderSizeAuto "false"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key BorderSize "None"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key ButtonsOnLeft ""
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group "org.kde.kdecoration2" --key ButtonsOnRight "IAX"

kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key blurEnabled "false"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key roundcornersEnabled "false"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group Plugins --key kwin4_effect_roundcornersEnabled "false"

if [[ -f /usr/share/Kvantum/Mokka/Mokka.kvconfig ]]; then
    sed -i \
        -e 's/^composite=.*/composite=false/' \
        -e 's/^translucent_windows=.*/translucent_windows=false/' \
        -e 's/^blurring=.*/blurring=false/' \
        /usr/share/Kvantum/Mokka/Mokka.kvconfig
fi

kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group NightColor --key Active "true"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group NightColor --key NightTemperature "3500"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group NightColor --key DayTemperature "6500"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group NightColor --key Mode "Time"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group NightColor --key MorningBeginFixed "0700"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group NightColor --key EveningBeginFixed "1800"
kwriteconfig6 --file /etc/skel/.config/kwinrc \
    --group NightColor --key TransitionTime "30"

# ── Lock screen ───────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --key Theme --delete 2>/dev/null || true
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --key WallpaperPlugin "org.kde.image"
kwriteconfig6 --file /etc/skel/.config/kscreenlockerrc \
    --group Greeter --group Wallpaper --group "org.kde.image" --group General \
    --key Image "file:///usr/share/wallpapers/Mokka-tree/"

# ── GTK themes ────────────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/gtk-3.0/settings.ini \
    --group Settings --key gtk-theme-name "catppuccin-mocha-mauve-standard+default"
kwriteconfig6 --file /etc/skel/.config/gtk-3.0/settings.ini \
    --group Settings --key gtk-icon-theme-name "Tela-circle-dracula-dark"
kwriteconfig6 --file /etc/skel/.config/gtk-3.0/settings.ini \
    --group Settings --key gtk-font-name "JetBrains Mono, 10"
kwriteconfig6 --file /etc/skel/.config/gtk-4.0/settings.ini \
    --group Settings --key gtk-theme-name "catppuccin-mocha-mauve-standard+default"
kwriteconfig6 --file /etc/skel/.config/gtk-4.0/settings.ini \
    --group Settings --key gtk-icon-theme-name "Tela-circle-dracula-dark"
kwriteconfig6 --file /etc/skel/.config/gtk-4.0/settings.ini \
    --group Settings --key gtk-font-name "JetBrains Mono, 10"

# ── Power management ──────────────────────────────────────────────────────────
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "AC" --group "Performance" --key PowerProfile "performance"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "AC" --group "SuspendAndShutdown" --key AutoSuspendAction "1"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "AC" --group "SuspendAndShutdown" --key AutoSuspendIdleTimeoutSec "1800"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "Battery" --group "Performance" --key PowerProfile "power-saver"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "Battery" --group "SuspendAndShutdown" --key AutoSuspendAction "1"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "Battery" --group "SuspendAndShutdown" --key AutoSuspendIdleTimeoutSec "1200"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "LowBattery" --group "Performance" --key PowerProfile "power-saver"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "LowBattery" --group "SuspendAndShutdown" --key AutoSuspendAction "1"
kwriteconfig6 --file /etc/skel/.config/powerdevilrc \
    --group "LowBattery" --group "SuspendAndShutdown" --key AutoSuspendIdleTimeoutSec "300"
