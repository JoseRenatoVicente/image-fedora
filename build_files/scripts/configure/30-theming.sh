#!/bin/bash
# Theming: instala os assets (install-assets.sh, inclui o tema Catppuccin
# Mocha/Mauve do COSMIC) e regenera o cache de fontes.
set -euo pipefail
trap 'printf "\033[1;31mERRO linha %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

bash /ctx/scripts/install-assets.sh
fc-cache -f /usr/share/fonts/
setfattr -n user.component -v "themes" /usr/share/fonts/JetBrainsMonoNerdFont
setfattr -n user.update-interval -v "yearly" /usr/share/fonts/JetBrainsMonoNerdFont
