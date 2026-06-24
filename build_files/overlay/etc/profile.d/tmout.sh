# STIG RHEL-09-412035 — termina shells interativos após 10 min de inatividade.
# Aplica-se a bash e zsh (ambos honram TMOUT via SIGALRM). readonly impede o
# utilizador de aumentar ou desativar o valor. O guard contra TMOUT já-definido
# evita o erro "readonly variable" quando o profile é re-sourced (ex.: su -).
if [ -n "${PS1-}" ] && [ -z "${TMOUT:-}" ]; then
    TMOUT=600
    export TMOUT
    readonly TMOUT 2>/dev/null || true
fi
