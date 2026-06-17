# shellcheck shell=bash
# Remove LESSOPEN/LESSCLOSE — o lesspipe corre preprocessadores ao abrir
# ficheiros com `less`, transformando o "só ver um ficheiro" num vetor de
# execução de código. Desativado por defeito (derivado do qubes-core-agent).
unset LESSOPEN LESSCLOSE
