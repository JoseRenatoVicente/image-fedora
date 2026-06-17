#!/bin/sh
# Imagem de teste apenas — força render de software para o KWin Wayland arrancar
# numa VM QEMU headless sem GPU real/virgl. Sourced por startplasma-wayland via
# /etc/xdg/plasma-workspace/env/. NÃO usar em produção.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export KWIN_COMPOSE=Q
