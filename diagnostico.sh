#!/usr/bin/env bash
# =============================================================================
# diagnostico.sh — Revisa por qué MetaTrader 5 no abre en Wine.
#
# Uso:
#   ./diagnostico.sh                  (revisa el prefijo ~/.mt5)
#   WINEPREFIX=~/.wine ./diagnostico.sh
#
# Solo lee información, no cambia nada. La salida oculta tu carpeta personal,
# tu usuario, direcciones IP y números de cuenta para que puedas compartirla
# (aun así, revísala antes de publicarla).
# =============================================================================
set -uo pipefail

PREFIJO="${WINEPREFIX:-$HOME/.mt5}"
VERSION_MINIMA="11.6"
PROBLEMAS=0

version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }
titulo() { printf '\n== %s ==\n' "$*"; }
mal()    { printf '  [x] %s\n' "$*"; PROBLEMAS=$((PROBLEMAS + 1)); }
bien()   { printf '  [ok] %s\n' "$*"; }

informe() {
    titulo "Sistema"
    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null
    echo "  ${PRETTY_NAME:-desconocido} | kernel $(uname -r) | sesión ${XDG_SESSION_TYPE:-?}"

    titulo "Wine instalados"
    local w v encontrado=0
    for w in /opt/wine-*/bin/wine /usr/bin/wine; do
        [ -x "$w" ] || continue
        encontrado=1
        v=$("$w" --version 2>/dev/null)
        if version_ge "$(sed -E 's/^wine-([0-9.]+).*/\1/' <<<"$v")" "$VERSION_MINIMA"; then
            bien "$w -> $v"
        else
            mal "$w -> $v  (menor que $VERSION_MINIMA: tiene el fallo del 'debugger')"
        fi
    done
    [ "$encontrado" = 1 ] || mal "No hay Wine instalado."
    if command -v wine >/dev/null; then
        echo "  El comando 'wine' apunta a: $(readlink -f "$(command -v wine)")"
    fi

    titulo "Paquetes de Wine (dpkg)"
    dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package} ${Version}\n' 2>/dev/null \
        | awk '$1 ~ /^.i/ && $2 ~ /wine/ {printf "  %s %s\n", $2, $3}'
    if dpkg-query -W -f='${db:Status-Abbrev}\n' winehq-stable 2>/dev/null | grep -q '^.i'; then
        mal "winehq-stable instalado: la rama stable (11.0) tiene el fallo. Usa winehq-staging o winehq-devel."
    fi

    titulo "Repositorios de WineHQ"
    if ls /etc/apt/sources.list.d/winehq* >/dev/null 2>&1; then
        grep -hE '^(URIs|Suites):' /etc/apt/sources.list.d/winehq* 2>/dev/null | sed 's/^/  /'
    else
        echo "  (ninguno)"
    fi

    titulo "Prefijo: $PREFIJO"
    if [ ! -f "$PREFIJO/system.reg" ]; then
        mal "El prefijo no existe o está incompleto."
    else
        echo "  Arquitectura: $(grep -m1 '^#arch=' "$PREFIJO/system.reg" | cut -d= -f2)"
        local so
        so=$(awk '/^\[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\]/ {s=1; next}
                  /^\[/ {s=0}
                  s && /^"(ProductName|CurrentBuild)"=/ {printf "%s ", $0}' "$PREFIJO/system.reg")
        echo "  Windows: ${so:-?}"
        if grep -q 'Windows 11' <<<"$so"; then
            bien "Modo Windows 11."
        else
            mal "El prefijo no está en Windows 11 (WINEPREFIX=$PREFIJO winecfg -> Windows 11)."
        fi
    fi

    titulo "MetaTrader 5"
    local mt5="$PREFIJO/drive_c/Program Files/MetaTrader 5"
    if [ -f "$mt5/terminal64.exe" ]; then
        bien "terminal64.exe instalado."
        local log
        # Los logs de la terminal se llaman AAAAMMDD.log (metaeditor.log es del editor).
        log=$(find "$mt5/logs" -name '[0-9]*.log' 2>/dev/null | sort | tail -n1)
        if [ -n "$log" ]; then
            echo "  Últimas líneas de $(basename "$log"):"
            iconv -f UTF-16LE -t UTF-8 "$log" 2>/dev/null | tr -d '\r' | tail -n 12 | sed 's/^/    /'
            if iconv -f UTF-16LE -t UTF-8 "$log" 2>/dev/null | grep -q 'build .* started'; then
                bien "MT5 llegó a arrancar (si viste el error 'debugger', no habría log)."
            fi
        else
            echo "  Sin logs: MT5 nunca llegó a arrancar (típico del error 'debugger')."
        fi
    else
        mal "terminal64.exe no está en el prefijo."
    fi

    titulo "Procesos"
    pgrep -af 'terminal64|wineserver' 2>/dev/null | cut -c1-140 | sed 's/^/  /' || echo "  (ninguno)"

    titulo "Resultado"
    if [ "$PROBLEMAS" -eq 0 ]; then
        echo "  No se detectaron problemas."
    else
        echo "  $PROBLEMAS problema(s) detectado(s). Revisa el README: sección 'Problemas comunes'."
    fi
}

# Oculta datos personales: carpeta personal, usuario, IPs y números de cuenta del log de MT5.
informe 2>&1 | sed -E \
    -e "s#$HOME#~#g" \
    -e "s#\\b${USER:-$(id -un)}\\b#USUARIO#g" \
    -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/x.x.x.x/g' \
    -e "s/'[0-9]{5,}'/'CUENTA'/g" \
    -e 's/\b(account|login|cuenta) #?[0-9]{5,}/\1 CUENTA/gI'
