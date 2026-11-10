#!/usr/bin/env bash
# =============================================================================
# instalar-mt5.sh — Instala MetaTrader 5 en Linux (Ubuntu / Debian / Mint)
# sin el error "A debugger has been found running in your system".
#
# Causa: la protección de MT5 da un falso positivo con Wine 10.3–11.5
# (incluido winehq-stable 11.0). Se corrigió en Wine 11.6 (bug WineHQ 58043).
# Este script instala winehq-staging (>= 11.6) desde el repositorio oficial
# de WineHQ, crea un prefijo limpio en modo Windows 11, instala WebView2 y
# MetaTrader 5.
#
# Uso:
#   ./instalar-mt5.sh
#
# Variables opcionales:
#   WINEPREFIX=~/.mt5      carpeta del prefijo de Wine (por defecto ~/.mt5)
#   WINE_BRANCH=staging    rama de WineHQ: staging (por defecto) o devel
#   SKIP_WEBVIEW=1         no instalar WebView2
#   ABRIR_MT5=0            no ofrecer abrir MT5 al terminar
# =============================================================================
set -euo pipefail

PREFIJO="${WINEPREFIX:-$HOME/.mt5}"
RAMA="${WINE_BRANCH:-staging}"
VERSION_MINIMA="11.6"
HUELLA_WINEHQ="D43F640145369C51D786DDEA76F1A20FF987672F"
URL_MT5="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
URL_WEBVIEW="https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/f2910a1e-e5a6-4f17-b52d-7faf525d17f8/MicrosoftEdgeWebview2Setup.exe"

info()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m[ok] %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
error() { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

# Pregunta s/n por teclado. Sin terminal (p. ej. en un pipe) usa la respuesta por defecto.
preguntar() { # $1 = texto, $2 = respuesta por defecto (s|n)
    local resp=""
    if { exec 3</dev/tty; } 2>/dev/null; then
        printf '%s ' "$1"
        read -r resp <&3 || true
        exec 3<&-
    fi
    resp="${resp:-$2}"
    [[ "$resp" =~ ^[sSyY] ]]
}

# version_ge A B  ->  verdadero si A >= B
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# ----------------------------------------------------------------------------
# 0. Comprobaciones
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || error "No lo ejecutes como root ni con sudo: usa tu usuario normal (el script pedirá la contraseña cuando haga falta)."
[ "$(uname -m)" = "x86_64" ] || error "Solo se soporta x86_64 (procesadores Intel/AMD de 64 bits)."
case "$RAMA" in
    staging|devel) ;;
    *) error "WINE_BRANCH debe ser 'staging' o 'devel' (stable 11.0 tiene el fallo)." ;;
esac
[ -r /etc/os-release ] || error "No encuentro /etc/os-release."
# shellcheck disable=SC1091
. /etc/os-release
if [ "${ID:-}" = "debian" ]; then
    DISTRO=debian
    CODENAME="${VERSION_CODENAME:-}"
elif [ "${ID:-}" = "ubuntu" ] || [[ " ${ID_LIKE:-} " == *" ubuntu "* ]]; then
    DISTRO=ubuntu   # Ubuntu y derivadas (Linux Mint, Pop!_OS, Zorin...)
    CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
else
    error "Distribución no soportada por el script (${PRETTY_NAME:-desconocida}). Mira el README: sección 'Otras distribuciones'."
fi
[ -n "$CODENAME" ] || error "No pude detectar el nombre en clave de tu versión del sistema."
info "Sistema: ${PRETTY_NAME:-$DISTRO}  (repositorio WineHQ: $DISTRO/$CODENAME)"

WINE="/opt/wine-$RAMA/bin/wine"
WINESERVER="/opt/wine-$RAMA/bin/wineserver"
wine_version() { "$WINE" --version 2>/dev/null | sed -E 's/^wine-([0-9.]+).*/\1/'; }

# ----------------------------------------------------------------------------
# 1. Wine >= 11.6 desde WineHQ
# ----------------------------------------------------------------------------
if [ "$RAMA" = staging ]; then OTRA=devel; else OTRA=staging; fi
# Paquetes que chocan con winehq-$RAMA o que traen una versión con el fallo.
CONFLICTOS=$(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' \
        wine wine64 wine32 libwine wine-stable winehq-stable "winehq-$OTRA" 2>/dev/null \
    | awk '$1 ~ /^.i/ {print $2}' | sort -u | tr '\n' ' ' || true)
CONFLICTOS="${CONFLICTOS% }"

if [ -x "$WINE" ] && version_ge "$(wine_version)" "$VERSION_MINIMA" && [ -z "$CONFLICTOS" ]; then
    ok "Wine $(wine_version) ($RAMA) ya está instalado; no hace falta reinstalarlo."
else
    if [ -n "$CONFLICTOS" ]; then
        aviso "Tienes paquetes de Wine que chocan con WineHQ $RAMA o que tienen el fallo: $CONFLICTOS"
        preguntar "¿Quitarlos ahora? (tus prefijos y programas de Wine NO se borran) [S/n]" s \
            || error "Cancelado. Quítalos a mano con: sudo apt remove $CONFLICTOS"
        # shellcheck disable=SC2086
        sudo apt-get remove -y $CONFLICTOS
    fi

    info "Instalando requisitos y añadiendo el repositorio oficial de WineHQ"
    sudo apt-get update
    sudo apt-get install -y curl gpg ca-certificates

    URL_SOURCES="https://dl.winehq.org/wine-builds/$DISTRO/dists/$CODENAME/winehq-$CODENAME.sources"
    curl -fsIL "$URL_SOURCES" >/dev/null \
        || error "WineHQ no tiene paquetes para '$CODENAME'. Mira el README: sección 'Problemas comunes'."

    TMPKEY=$(mktemp)
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key -o "$TMPKEY"
    HUELLA=$(gpg --show-keys --with-colons "$TMPKEY" 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')
    if [ "$HUELLA" != "$HUELLA_WINEHQ" ]; then
        rm -f "$TMPKEY"
        error "La llave de WineHQ descargada no coincide (huella: ${HUELLA:-vacía}). Abortando por seguridad."
    fi
    sudo dpkg --add-architecture i386
    sudo mkdir -pm755 /etc/apt/keyrings
    sudo gpg --dearmor --yes -o /etc/apt/keyrings/winehq-archive.key "$TMPKEY"
    rm -f "$TMPKEY"
    sudo rm -f /etc/apt/sources.list.d/winehq*
    sudo curl -fsSL -o "/etc/apt/sources.list.d/winehq-$CODENAME.sources" "$URL_SOURCES"
    sudo apt-get update

    CANDIDATA=$(LC_ALL=C apt-cache policy "winehq-$RAMA" | awk '/Candidate:/ {print $2; exit}')
    if [ -z "$CANDIDATA" ] || [ "$CANDIDATA" = "(none)" ]; then
        error "No aparece el paquete winehq-$RAMA en el repositorio de WineHQ para $CODENAME."
    fi
    version_ge "${CANDIDATA%%~*}" "$VERSION_MINIMA" \
        || error "WineHQ solo ofrece $RAMA ${CANDIDATA%%~*} para $CODENAME y hace falta >= $VERSION_MINIMA. Mira el README: sección 'Problemas comunes'."

    info "Instalando winehq-$RAMA ${CANDIDATA%%~*} (unos 300 MB)"
    sudo apt-get install -y --install-recommends "winehq-$RAMA"
    [ -x "$WINE" ] || error "No se encontró $WINE después de instalar."
    version_ge "$(wine_version)" "$VERSION_MINIMA" \
        || error "La versión instalada ($(wine_version)) es menor que $VERSION_MINIMA."
    ok "Wine $(wine_version) ($RAMA) instalado."
fi

# ----------------------------------------------------------------------------
# 2. Prefijo de Wine limpio en modo Windows 11
# ----------------------------------------------------------------------------
export WINEPREFIX="$PREFIJO"
export WINEDEBUG="${WINEDEBUG:--all}"
info "Preparando el prefijo de Wine en $PREFIJO"
if [ -e "$PREFIJO" ]; then
    RESPALDO="$PREFIJO.respaldo-$(date +%Y%m%d-%H%M%S)"
    aviso "Ya existe $PREFIJO (quizá de un intento anterior)."
    if preguntar "¿Moverlo a $RESPALDO y empezar limpio? (recomendado) [S/n]" s; then
        "$WINESERVER" -k 2>/dev/null || true
        mv "$PREFIJO" "$RESPALDO"
        ok "Respaldo guardado en $RESPALDO"
    else
        aviso "Se reutilizará el prefijo existente."
    fi
fi
# mscoree/mshtml desactivados solo aquí: evita las ventanas de Wine Mono/Gecko (MT5 no las necesita).
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}mscoree,mshtml=" "$WINE" wineboot --init
"$WINE" winecfg -v win11
timeout 120 "$WINESERVER" -w || true
if "$WINE" reg query 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v ProductName 2>/dev/null | grep -q 'Windows 11'; then
    ok "Prefijo configurado como Windows 11."
else
    error "No se pudo poner el prefijo en Windows 11. Hazlo a mano: WINEPREFIX=$PREFIJO $WINE winecfg"
fi

# ----------------------------------------------------------------------------
# 3. WebView2 y MetaTrader 5 (instaladores oficiales)
# ----------------------------------------------------------------------------
DESCARGAS=$(mktemp -d)
trap 'rm -rf "$DESCARGAS"' EXIT

if [ "${SKIP_WEBVIEW:-0}" != 1 ]; then
    info "Descargando e instalando WebView2 (lo usan el Mercado y las Noticias de MT5; tarda unos minutos)"
    curl -fSL --progress-bar -o "$DESCARGAS/webview2.exe" "$URL_WEBVIEW"
    timeout 900 "$WINE" "$DESCARGAS/webview2.exe" /silent /install \
        || aviso "WebView2 terminó con código $? (normalmente no es grave)."
    # MicrosoftEdgeUpdate.exe se queda corriendo para siempre y deja colgado
    # "wineserver -w": se cierran los procesos de ESTE prefijo para continuar.
    "$WINESERVER" -k 2>/dev/null || true
    sleep 2
fi

info "Descargando e instalando MetaTrader 5"
curl -fSL --progress-bar -o "$DESCARGAS/mt5setup.exe" "$URL_MT5"
# El instalador puede devolver código 1 aunque instale bien: se comprueba el archivo.
timeout 900 "$WINE" "$DESCARGAS/mt5setup.exe" /auto || true
TERMINAL="$PREFIJO/drive_c/Program Files/MetaTrader 5/terminal64.exe"
[ -f "$TERMINAL" ] || error "No se encontró terminal64.exe: la instalación falló. Ejecuta ./diagnostico.sh"
ok "MetaTrader 5 instalado en: $TERMINAL"

cat <<EOF

------------------------------------------------------------------
 MetaTrader 5 quedó instalado.

 - Ábrelo desde el menú de aplicaciones o el acceso del Escritorio.
 - O desde la terminal:
     WINEPREFIX="$PREFIJO" "$WINE" "$TERMINAL"
 - Si algo falla:  ./diagnostico.sh
------------------------------------------------------------------
EOF

if [ "${ABRIR_MT5:-1}" = 1 ] && preguntar "¿Abrir MetaTrader 5 ahora? [S/n]" s; then
    setsid "$WINE" "$TERMINAL" >/dev/null 2>&1 &
fi
