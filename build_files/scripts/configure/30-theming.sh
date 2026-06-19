#!/bin/bash
# Theming: instala os assets KDE (install-assets.sh), aplica o Panel Colorizer
# e regenera o cache de fontes.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

bash /ctx/scripts/install-assets.sh
bash /ctx/scripts/panel-colorizer.sh
fc-cache -f /usr/share/fonts/
setfattr -n user.component -v "themes" /usr/share/fonts/JetBrainsMonoNerdFont
setfattr -n user.update-interval -v "yearly" /usr/share/fonts/JetBrainsMonoNerdFont
