# MetaTrader 5 en Linux: solución al error «A debugger has been found running in your system»

Instala **MetaTrader 5** en Ubuntu, Debian o Linux Mint con Wine **sin** el error del «debugger».

Probado en noviembre de 2026 en **Ubuntu 26.04.1 LTS** (kernel 7.0, GNOME Wayland, AMD Ryzen) con **Wine Staging 11.21** y **MetaTrader 5 build 6314**: abre, conecta con una cuenta demo y opera con normalidad.

---

## El problema

Al instalar o abrir MetaTrader 5 con Wine aparece esta ventana y el programa se cierra:

```
A debugger has been found running in your system.
Please, unload it from memory and restart your program.
```

No tienes ningún depurador abierto: es un **falso positivo**. Reinstalar MT5, reiniciar el equipo o usar Docker no lo arregla.

## Solución rápida

```bash
git clone https://github.com/Wilmerony/mt5-linux-debugger-fix.git
cd mt5-linux-debugger-fix
./instalar-mt5.sh
```

Ejecútalo con tu usuario normal, **sin** `sudo`. El script pide la contraseña solo cuando la necesita. Tarda unos 5–10 minutos según tu conexión.

Al terminar tendrás MetaTrader 5 en el menú de aplicaciones y en el Escritorio.

## Por qué pasa

MetaTrader 5 trae una protección anticopia y antidepuración (Themida). Desde **Wine 10.3**, Wine incluye unas funciones internas de `ntdll` («Zw…») que antes faltaban. Al encontrarlas, la protección cambia de camino: hace **llamadas directas al sistema** (*syscalls*). En modo Windows 10 usa números de llamada fijos que solo coinciden con los de un Windows real, y eso termina en el falso aviso de «debugger».

- El fallo se rastreó hasta el cambio `ntdll: Add some missing Zw exports` y se **corrigió en Wine 11.6** ([bug 58043 de WineHQ](https://bugs.winehq.org/show_bug.cgi?id=58043)).
- En modo **Windows 11** la protección lee los números de llamada del propio `ntdll`, por eso el prefijo se configura como Windows 11.
- **La trampa:** la rama `winehq-stable` sigue en **11.0**, que **no** tiene la corrección. La mayoría de las guías dicen «instala winehq-stable», y justo esa falla.

| Versión de Wine | Resultado con MT5 |
|---|---|
| Paquete `wine` de Ubuntu 26.04 (10.0) | ❌ no funcionó en este equipo |
| WineHQ 10.3 – 11.5 (devel / staging) | ❌ fallo conocido (bug 58043) |
| **WineHQ stable 11.0** (`winehq-stable`) | ❌ error «debugger» (probado) |
| Docker `gmag11/metatrader5_vnc` (usa `winehq-stable` dentro) | ❌ error «debugger» (probado) |
| **WineHQ staging 11.21** (`winehq-staging`) | ✅ **funciona (probado)** |
| WineHQ devel ≥ 11.6 (`winehq-devel`) | ✅ incluye la corrección (no probado aquí) |

## Qué hace `instalar-mt5.sh`

1. **Detecta tu sistema** (Ubuntu, Debian y derivadas como Mint, Pop!_OS o Zorin) y usa el repositorio de WineHQ **de tu versión exacta**.
2. **Quita paquetes de Wine que chocan o tienen el fallo** (`wine` de la distro, `winehq-stable`), pero solo si le das permiso. No borra tus programas ni tus prefijos.
3. **Añade el repositorio oficial de WineHQ** y comprueba la huella de su llave (`D43F 6401 4536 9C51 D786 DDEA 76F1 A20F F987 672F`).
4. **Instala `winehq-staging`** y verifica que la versión sea ≥ 11.6.
5. **Crea un prefijo limpio en `~/.mt5`** (64 bits, **Windows 11**). Si ya existía, lo mueve a una copia de respaldo.
6. **Instala WebView2**, que usan el Mercado y las Noticias de MT5, y cierra el servicio de Edge Update que deja Wine colgado.
7. **Instala MetaTrader 5** con el instalador oficial de MetaQuotes en modo automático (`/auto`).

Opciones (variables de entorno):

```bash
WINEPREFIX=~/otra-carpeta ./instalar-mt5.sh   # otro prefijo en vez de ~/.mt5
WINE_BRANCH=devel ./instalar-mt5.sh           # usar winehq-devel en vez de staging
SKIP_WEBVIEW=1 ./instalar-mt5.sh              # no instalar WebView2
ABRIR_MT5=0 ./instalar-mt5.sh                 # no preguntar si abrir MT5 al final
```

## Instalación manual paso a paso

Si prefieres hacerlo tú mismo, este es el ejemplo para **Ubuntu 26.04 (`resolute`)**. Cambia `resolute` por el nombre de tu versión: `noble` (24.04), `jammy` (22.04), `bookworm` o `trixie` (Debian). En Debian, cambia `ubuntu` por `debian` en la URL.

```bash
# 1. Quitar versiones de Wine con el fallo (si las tienes)
sudo apt remove wine wine64 wine32 libwine winehq-stable wine-stable

# 2. Repositorio oficial de WineHQ
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key -
sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/resolute/winehq-resolute.sources
sudo apt update

# 3. Wine staging (>= 11.6). NO winehq-stable.
sudo apt install --install-recommends winehq-staging
wine --version        # debe decir 11.6 o mayor

# 4. Prefijo limpio en modo Windows 11
export WINEPREFIX=~/.mt5
WINEDLLOVERRIDES="mscoree,mshtml=" wineboot --init
winecfg -v win11

# 5. WebView2 y MetaTrader 5
wget -O webview2.exe "https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/f2910a1e-e5a6-4f17-b52d-7faf525d17f8/MicrosoftEdgeWebview2Setup.exe"
wget -O mt5setup.exe "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
wine webview2.exe /silent /install
wineserver -k         # cierra Edge Update, que se queda colgado
wine mt5setup.exe /auto

# 6. Abrir MetaTrader 5
wine "C:\\Program Files\\MetaTrader 5\\terminal64.exe"
```

> ℹ️ El script oficial de MetaQuotes (`mt5linux.sh`) usa en Ubuntu 26.04 el repositorio de la 25.10 (`questing`) y hace un `apt upgrade` de todo el sistema. Este repositorio usa el repositorio nativo de tu versión y solo instala Wine.

## Si ya lo intentaste antes: limpieza

- **Wine de la distro o `winehq-stable`:** el script ofrece quitarlos. A mano: `sudo apt remove wine wine64 wine32 libwine winehq-stable wine-stable`.
- **Prefijo viejo (`~/.wine`):** el script usa `~/.mt5`, así que no hace falta borrarlo. Si solo tenías MT5 ahí y quieres recuperar espacio: `rm -rf ~/.wine`.
- **Accesos directos rotos** del intento anterior, que apuntan a `~/.wine` o a `wine-stable`:
  ```bash
  rm -rf ~/.local/share/applications/wine/Programs/"MetaTrader 5"
  rm -f ~/.config/menus/applications-merged/wine-Programs-MetaTrader\ 5-*.menu
  ```
- **Contenedor Docker `gmag11/metatrader5_vnc`:** usa `winehq-stable` por dentro, así que tiene el mismo fallo. Además publica los puertos 3000 y 8001 en **toda tu red** (`0.0.0.0`). Para borrarlo:
  ```bash
  docker stop mt5 && docker rm mt5
  docker volume rm mt5_config
  docker rmi gmag11/metatrader5_vnc
  ```

## Problemas comunes

**El script o `wineserver -w` se queda colgado después de instalar WebView2.**
El servicio `MicrosoftEdgeUpdate.exe` nunca termina. Ciérralo con `WINEPREFIX=~/.mt5 wineserver -k` (solo afecta a ese prefijo). El script ya lo hace solo.

**El instalador de MT5 devuelve el código de salida 1.**
Es normal. Si existe `~/.mt5/drive_c/Program Files/MetaTrader 5/terminal64.exe`, la instalación salió bien.

**Error de conflictos al instalar `winehq-staging`.**
Tienes instalado el Wine de tu distribución o `winehq-stable`/`winehq-devel`. Quítalos primero (ver «Limpieza»).

**«WineHQ no tiene paquetes para tu versión» o la versión ofrecida es menor que 11.6.**
WineHQ deja de compilar para versiones del sistema sin soporte. Por ejemplo, el repositorio de Ubuntu 25.10 se quedó en 11.12, que todavía sirve. Si el tuyo está por debajo de 11.6, actualiza tu sistema o usa el Wine de [Kron4ek](https://github.com/Kron4ek/Wine-Builds) (≥ 11.6) con el mismo prefijo en Windows 11.

**El error vuelve después de una actualización.**
Ejecuta `./diagnostico.sh` y revisa `wine --version`. Si una versión nueva de Wine lo rompe, puedes congelar la que funciona hasta que se arregle:
```bash
sudo apt-mark hold winehq-staging wine-staging     # congelar
sudo apt-mark unhold winehq-staging wine-staging   # volver a recibir actualizaciones
```
Si sabes cuál era la última versión buena, también puedes volver a ella con `sudo apt install winehq-staging=<versión> wine-staging=<versión>`.

**Uso Wayland.**
No hace falta nada: Wine funciona a través de XWayland.

**En pantallas 4K o HiDPI la letra se ve diminuta.**
Ejecuta `WINEPREFIX=~/.mt5 winecfg`, ve a la pestaña *Gráficos* y sube la resolución de pantalla (dpi) a 144 o 192.

**Fedora, Arch y otras distribuciones.**
El script es solo para la familia Debian/Ubuntu, pero la solución es la misma: Wine ≥ 11.6 y un prefijo en Windows 11.
- Fedora: añade el repositorio de WineHQ (`https://dl.winehq.org/wine-builds/fedora/<versión>/winehq.repo`) y ejecuta `sudo dnf install winehq-staging`.
- Arch y Manjaro: `sudo pacman -S wine-staging`.

Después sigue los pasos 4 a 6 de la instalación manual.

## Diagnóstico

```bash
./diagnostico.sh                     # revisa ~/.mt5
WINEPREFIX=~/.wine ./diagnostico.sh  # revisa otro prefijo
```

Revisa qué Wine tienes, los paquetes y repositorios, si el prefijo está en Windows 11, si MT5 llegó a arrancar (con el error del «debugger» no se crea ningún log) y los procesos activos. **Solo lee, no cambia nada.**

La salida oculta tu carpeta personal, tu usuario, las direcciones IP y los números de cuenta, para que puedas pegarla al pedir ayuda. Aun así, revísala antes de publicarla.

## Historial del caso

Lo que se intentó, en este orden, en un portátil con Ubuntu 26.04:

1. **El paquete `wine` de Ubuntu (10.0) con `winetricks`:** MT5 no abría.
2. **El script oficial `mt5linux.sh` de MetaQuotes**, y después **`winehq-stable` 11.0** de WineHQ a mano: error «A debugger has been found running in your system».
3. **Docker `gmag11/metatrader5_vnc`**, incluso con `--cap-add=SYS_PTRACE` y `--security-opt seccomp=unconfined`: mismo error, porque dentro usa `winehq-stable`.
4. **Solución:** se quitaron las versiones anteriores, se instaló **`winehq-staging` 11.21** desde el repositorio nativo `resolute` y se creó un prefijo nuevo `~/.mt5` en **Windows 11**. Luego se instalaron WebView2 y MT5. Resultado: MT5 build 6314 abre sin errores y se conecta a una cuenta demo de MetaQuotes.

## Fuentes

- [WineHQ bug 58043: «A debugger has been found running in your system» desde Wine 10.3, corregido en 11.6](https://bugs.winehq.org/show_bug.cgi?id=58043)
- [Foro MQL5: MT5 en openSUSE con Wine 11 da el error del debugger](https://www.mql5.com/en/forum/503128/page2)
- [Foro MQL5: Wine 11 rompió MetaTrader 5](https://www.mql5.com/en/forum/503844)
- [Foro MQL5: error del debugger en Ubuntu tras actualizar MT5 (octubre de 2026)](https://www.mql5.com/en/forum/518725)
- [MetaTrader 5: instalación oficial en Linux](https://www.metatrader5.com/en/terminal/help/start_advanced/install_linux)
- [Repositorio de paquetes de WineHQ](https://dl.winehq.org/wine-builds/)

## Aviso

- Proyecto comunitario, **sin relación con MetaQuotes, WineHQ ni Microsoft**.
- Los scripts descargan los instaladores oficiales directamente de MetaQuotes y Microsoft. No se redistribuye ningún programa.
- Úsalo bajo tu responsabilidad. **Prueba primero con una cuenta demo** antes de operar con dinero real en Wine.

---

## English summary

**Fix for MetaTrader 5 on Linux showing "A debugger has been found running in your system".**

It's a false positive caused by MT5's protector (Themida) taking a direct-syscall code path on Wine 10.3–11.5. The cause was the commit `ntdll: Add some missing Zw exports`, and it was fixed in **Wine 11.6** ([WineHQ bug 58043](https://bugs.winehq.org/show_bug.cgi?id=58043)). Note that `winehq-stable` is still **11.0** and still broken.

The fix:
- Install `winehq-staging` (or `winehq-devel`) **≥ 11.6** from WineHQ's repo for your exact release.
- Create a fresh 64-bit prefix set to **Windows 11**.
- Install WebView2 and MT5. Run `wineserver -k` after WebView2, because Edge Update never exits.

`./instalar-mt5.sh` automates all of this on Debian/Ubuntu/Mint. `./diagnostico.sh` prints a shareable, anonymized report.

Tested: Ubuntu 26.04.1 LTS, Wine Staging 11.21, MT5 build 6314 (November 2026).

## Licencia

[MIT](LICENSE)
