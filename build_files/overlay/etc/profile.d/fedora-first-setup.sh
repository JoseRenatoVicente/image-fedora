# shellcheck shell=bash
# Dispara o setup de primeiro login sem systemd --user. Sourced por shells de
# login (bash e zsh). Sai barato quando o setup terminou (sentinel) ou o
# utilizador não é humano.
case $- in *i*) : ;; *) return 0 ;; esac
[ "$(id -u)" -ge 1000 ] 2>/dev/null || return 0
[ -n "${HOME:-}" ] && [ -d "$HOME" ] || return 0
_fcfg="${XDG_CONFIG_HOME:-$HOME/.config}/fedora"
[ -e "$_fcfg/.first-setup-complete" ] && { unset _fcfg; return 0; }
setsid /usr/libexec/fedora-first-setup-runner </dev/null >/dev/null 2>&1 &
unset _fcfg
