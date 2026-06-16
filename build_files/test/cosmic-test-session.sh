#!/bin/sh
# Imagem de teste apenas — força render de software para o cosmic-comp arrancar
# numa VM QEMU headless sem GPU real/virgl, depois arranca a sessão COSMIC.
# NÃO usar em produção.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
exec cosmic-session
