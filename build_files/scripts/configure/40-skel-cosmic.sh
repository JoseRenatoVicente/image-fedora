#!/bin/bash
# Skel + defaults COSMIC: shell padrão para novos utilizadores e marcador de
# fim de setup. Ao contrário da era KDE, o tema Catppuccin (30-theming.sh) não
# importa nenhuma árvore /etc/skel de terceiros — os overrides de skel do
# overlay (build_files/overlay/etc/skel/.config/gtk-{3,4}.0/settings.ini, etc.)
# já ficam definitivos a partir do cp -aT em 10-system.sh, sem necessidade de
# reaplicação aqui.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Shell padrão para novos utilizadores: zsh (evita chsh no primeiro login)
sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd

touch /etc/cosmic-setup-done

setfattr -n user.component -v "skel" \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup \
    /usr/libexec/fedora-toolbox-setup
setfattr -n user.update-interval -v "monthly" \
    /usr/libexec/fedora-shell-setup \
    /usr/libexec/fedora-dev-setup \
    /usr/libexec/fedora-brew-setup \
    /usr/libexec/fedora-toolbox-setup
