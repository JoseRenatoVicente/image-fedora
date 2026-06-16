# 02-theming.sh — Asset installation and font cache.
# Sourced by build-configure.sh (not executed directly).

# ─── Theming ──────────────────────────────────────────────────────────────────
echo "::group:: Theming"
bash /ctx/install-assets.sh
fc-cache -f /usr/share/fonts/
setfattr -n user.component -v "themes" /usr/share/fonts/JetBrainsMonoNerdFont
setfattr -n user.update-interval -v "yearly" /usr/share/fonts/JetBrainsMonoNerdFont
echo "::endgroup::"
