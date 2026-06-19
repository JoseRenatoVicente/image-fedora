# shellcheck shell=bash
# Faz `sudo …` invocar o run0 do systemd (eleva via polkit, sem setuid) em shells
# interativos (bash e zsh carregam /etc/profile.d/*.sh). O pacote sudo continua
# instalado (plasma-workspace exige kdesu→sudo), mas o utilizador passa a usar
# run0 sem mudar o hábito. NOTA: aliases não são expandidos em scripts não
# interativos — o sudo real (/usr/bin/sudo) continua a responder aí.
if command -v run0 >/dev/null 2>&1; then
    alias sudo='run0'
fi
