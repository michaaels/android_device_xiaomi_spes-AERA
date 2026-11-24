# Pruebas y validación

Estados: **PASS** · **FAIL** · **BLOCKED** · **NOT TESTED**. Cada resultado indica su evidencia.

Hay tres niveles de validación, y cumplir uno no implica los siguientes: **compila** → **arranca** → **funciona correctamente**.
**Estado actual (2026-11-23): COMPILA y ARRANCA en hardware (spes), y FUNCIONA en todo lo marcado PASS abajo. Instalado de forma permanente en `boot_a` desde el 2026-11-23. Falta lo marcado NOT TESTED y la variante spesn. EXPERIMENTAL.**

## Pruebas estáticas (automatizadas): `tools/validate-tree.sh`

| Prueba | Resultado | Evidencia |
|---|---|---|
| Ficheros obligatorios del árbol | PASS | `validate-tree.sh` (2026-11-20) |
| Producto (`twrp_spes`, `spes`, `DEVICE_PATH`) | PASS | ídem |
| Sintaxis de shell (`bash -n`) de los scripts | PASS | ídem |
| Condicionales de Make equilibrados | PASS | ídem |
| fstab: 5 columnas, sin puntos de montaje duplicados, FBE v2 y metadata | PASS | ídem |
| `twrp.flags` sin duplicados | PASS | ídem |
| Los servicios rc apuntan a binarios existentes o que aporta el build | PASS | ídem |
| Sin referencias a otros dispositivos | PASS | ídem |
| Cabeceras de licencia | PASS | ídem |
| Flags `AERA_*` existentes en el upstream | PASS (63/63) | contrastadas con `bootable/recovery`, `vendor/twrp` y `vendor/recovery` en `aera-16.0` |
| Blobs presentes | PASS (33/33) | `tools/blobs.sha256`, sacados del vendor de EvolutionX (hash del payload verificado) |
| Kernel prebuilt presente | PASS | `prebuilt/kernel.info` (4.19.325 Cherry, SHA-256 `34ebc3ee…`) |
| Parseo de Make/Soong por el propio build (`lunch`) | PASS | `lunch twrp_spes-bp2a-eng` (tras la corrección de `BOARD_*IMAGE_FILE_SYSTEM_TYPE`) |

## Pruebas de compilación

| Prueba | Resultado | Evidencia |
|---|---|---|
| Build 1 (limpio) `m adbd bootimage` | FAIL → corregido | se detuvo al 55 %: `graphics_fbdev.cpp:67: expected expression` (`TW_MAX_BRIGHTNESS` vacío) |
| Build 2 (incremental tras la corrección) | PASS | `EXIT 0`, 5 min; `/src/build2.log` |
| Build limpio completo sin errores | PASS | `OUT_DIR=/src/out_clean`, `EXIT 0`, 13 min 40 s, 0 `FAILED`; log en `aera_source/artifacts/build-clean/` |
| Comparación limpio frente a incremental | PASS (estructura) | mismos 3440 ficheros y kernel idéntico; 120 ficheros difieren por la fecha de build en las props y los build-id de ELF (`fastbootd` es idéntico sin build-id). `adbd` tiene otra diferencia sin analizar. No es reproducible bit a bit |
| Cabecera v3 | PASS | `unpack_bootimg.py`: `boot image header version: 3`, os 99.87.36 / 2099-12 |
| Kernel idéntico al prebuilt | PASS | SHA-256 `34ebc3ee…` en los dos |
| Tamaño ≤ partición | PASS | 134217728 = `BOARD_BOOTIMAGE_PARTITION_SIZE` (original 67108864 + footer AVB, algoritmo NONE) |
| Ramdisk LZ4 y contenido | PASS | 3440 ficheros; rc de qcom, usb y decrypt; `twrp.flags`; fstab; boot@1.2 y health@2.1; adbd, fastbootd, minadbd, resetprop |
| Blobs en el ramdisk idénticos a `blobs.sha256` | PASS | 33/33 |
| Librerías AOSP que necesitan los blobs | PASS | keymaster@4.0/4.1, gatekeeper@1.0, boot@1.0–1.2, hidl, binder, xml2, crypto… todas presentes |
| SHA-256 del artefacto | PASS | probado en hardware: `d69b491b1c0439a19ae007adcc98688de58821284530d37b7d6c1f665bba3ba3` (incremental). Los anteriores (`7fa53ef7…`, `0b6dcea3…`) no arrancan |
| Build limpio de la configuración a fecha de `b14656b` | PASS | `EXIT 0`, 13 min 50 s; mismos 3777 ficheros, configuración y blobs idénticos a la imagen probada, y arranca en hardware (`8982622e…`) |
| **Build limpio final** (commit `5b75963` y parche `0001` aplicado) | PASS | `EXIT 0`, 14 min 40 s, 0 FAILED; ramdisk LZ4 de 39 576 537 B; kernel idéntico; 33/33 blobs. **Artefacto de referencia `d11af8397be8ea7f55015c0047ad81ee39e3615cebf8a68e1ce14fd8afe08da5`** |
| **Build limpio final con Wi-Fi** (commit `f4b7e96`, parche `0001` aplicado) | PASS | `EXIT 0`, 15 min 58 s; 29 binarios con UPX; ramdisk LZ4 de 41 080 344 B; kernel idéntico; 37/37 blobs; **artefacto de referencia `b4964c11fea3d22348cb176c967fc42e00dae44adfe1702534933f2019335999`** |
| Ese artefacto en hardware | PASS | R1.0, 0 aborts; Wi-Fi: `wlan0` en ~14 s, conexión desde la interfaz, ping desde el PC y TCP/DNS correctos; EFS real idéntico antes y después |
| Artefacto de referencia anterior (sin Wi-Fi) en hardware | PASS | `fastboot boot`: R1.0, 0 aborts, todos los servicios en marcha, UDC enlazado; backup por ADB de `/boot` en 16 s, idéntico a la copia `dd` |

## Pruebas en hardware

Dispositivo: spes, SKU `k7t` (2201117TG), bootloader desbloqueado, slot `a`, EvolutionX 16.0 11.10 instalado. **Procedimiento:** solo `fastboot boot` (en RAM); no se ha escrito ninguna partición. Imagen de la última regresión (2026-11-20): `build25-flashlight`, SHA-256 `01fa83b1161485af46c9f1a451881c3fec90ce30b636b49eaf62d1a3d3075fc1` (parches 0001–0006, busybox, ajustes en `/persist`). Las filas marcadas **(b25)** se repitieron con ella; el resto viene de builds anteriores (primera: `build11-vintf`). Las funciones añadidas después se probaron en su build (**b27** a **b41**, ver el registro al final); la última imagen probada es la **build limpia final** `final-e038300` (SHA-256 `b35012dd…`, parches 0001–0010), con la regresión rápida del 2026-11-23, y aún no se ha repetido con ella la regresión completa. Evidencia en `docs/evidence/`.

| Prueba | spes | spesn | Evidencia |
|---|---|---|---|
| `fastboot boot` aceptado y kernel arrancado | PASS | NOT TESTED | `hw-abl-ramdisk-limit.txt` (antes, BLOCKED por el límite de ramdisk y por la ramdisk gzip) |
| Arranque de AERA (init, interfaz LVGL) | PASS | NOT TESTED | logo, interfaz y menús vistos por el usuario; `ro.aera.release.version=R1.0` |
| Pantalla y brillo | PASS | NOT TESTED | `max_brightness=2047`, brillo 1200 aplicado (`hw-aera-first-boot.txt`) |
| Renderizador | NOT TESTED (detalle) | | DRM `card0` presente; el renderizador exacto no está verificado |
| Táctil (`fts_ts`, FocalTech) | PASS | NOT TESTED | el usuario manejó los menús; `getevent` |
| Botones (power, volumen) | PASS | NOT TESTED | menú de power y volumen responden (`gpio-keys`, `qpnp_pon`) |
| Ajustes de AERA en `/persist/AERA` (convención oficial) | PASS (b25) | | `early-ui.conf` con `language=es-ES`; la pantalla del PIN sale en español (confirmado por el usuario). Antes (`build18-persist-ro`) se probó `persist` en solo lectura, descartado |
| Fluidez de la interfaz | PASS (tras la corrección USB) | | antes iba lenta por el bucle de `init` del USB (`kmsg-usb-diag.txt`) |
| ADB (shell como root) | PASS | NOT TESTED | `18d1:d001`, `UDC=4e00000.dwc3` |
| Variante detectada por SKU | PASS (`k7t` → spes 2201117TG) | NOT TESTED (`k7tn`) | `hw-aera-first-boot.txt` |
| Servicios (logd, keystore2, qseecomd, keymaster 4.1, gatekeeper 1.0, boot 1.2, health 2.1) | PASS, 0 aborts | NOT TESTED | `hw-aera-services-decrypt.txt` |
| Detección de particiones | PASS | NOT TESTED | todas las de `twrp.flags` y las lógicas `_a` (`recovery.log`) |
| Descifrado con PIN | PASS (b25) | NOT TESTED | "User 0 Decrypted Successfully", `/data` en dm-default-key y `/data/media/0` legible (`hw-aera-recovery-log-decrypt.txt`) |
| Descifrado sin contraseña | PASS (b41) | NOT TESTED | bloqueo "Ninguno" en Android (`CredentialType: NONE`): AERA descifra solo, sin pedir nada; "User 0 Decrypted Successfully" y `/data/media/0` legible |
| Descifrado con patrón | PASS (b41) | NOT TESTED | bloqueo con patrón en Android: "password type: pattern", el usuario dibujó el patrón y "User 0 Decrypted Successfully"; `/data` montado (dm-default-key) y `/data/media/0` legible |
| Credencial incorrecta | PASS | NOT TESTED | la interfaz muestra "That credential did not unlock data. Please try again."; en el log, `GateKeeper response error` → `Failed to decrypt user 0`, y `/data/media/0` sigue con nombres cifrados |
| Cancelar el desbloqueo (Omitir) | PASS (con `AERA_UI_ADAPTIVE_RESOLUTION`) | NOT TESTED | sin él, el teclado tapaba el botón; con él, entra al menú y los datos siguen cifrados |
| Claves de Android intactas tras descifrar en AERA | PASS | | el usuario desbloqueó Android con su PIN tras la sesión de AERA y confirmó que apps y fotos están bien (2026-11-20); por código, las claves actualizadas se escriben solo en `/tmp` |
| MTP (enumeración) | PASS | NOT TESTED | el PC ve `18d1:4ee2 (MTP + debug)` con `mtp,adb` |
| MTP (transferencia de ficheros) | PASS (b25) | NOT TESTED | 1 MB aleatorio subido y bajado en almacenamiento interno y microSD; SHA-256 igual en el PC, el teléfono y la copia descargada; fichero de prueba borrado. La microSD también aparece |
| ADB sideload | PASS (b25) | NOT TESTED | zip inofensivo (`aera-sideload-test.zip`): "Installing zip file '/sideload/package.zip'", "AERA spes sideload test: OK", "Process ended with no errors" |
| Fastbootd | PASS (b25) | NOT TESTED | `adb reboot fastboot` → `is-userspace: yes`, `super-partition-name: super`, `snapshot-update-status: none` |
| Reinicio a bootloader (desde la interfaz y por adb) | PASS | | |
| Volver a Android con normalidad | PASS (b25) | NOT TESTED | `fastboot reboot` desde fastbootd → `sys.boot_completed=1`, Android 16, slot `_a` |
| Batería y temperatura | PASS (lectura) | | capacidad 100 %, cargando, 31,1 °C; CPU `pm6125-tz` 37 °C |
| Backup de particiones (desde OrangeFox, solo lectura) | PASS | | 15 particiones verificadas con SHA-256 (fuera del repositorio) |
| Backup desde AERA por ADB (`adb backup --twrp boot`) | PASS (b25) con el parche `patches/bootable_recovery/0001` | | los 128 MiB son idénticos a la copia `dd` (`9f132dc1…`) y el stream acaba en `twendadb`. Sin el parche, AERA lo da por fallido ("Unable to flush '/tmp/twadbbackup': Invalid argument"). Solo funciona fuera de la pantalla de descifrado |
| Restore desde AERA | NOT TESTED | | escribe en particiones; queda para el final y requiere autorización |
| Instalación permanente en `boot` | PASS (final) | NOT TESTED | copia previa de 15 particiones verificada con SHA-256; `boot_a` instalado = kernel y cabecera del `boot_a` existente (KernelSU Next, `os_version` 16.0.0, `os_patch_level` 2026-08) + ramdisk de la build final, montado con `mkbootimg` en el PC y verificado antes de escribir. Android arranca con root; `adb reboot recovery` entra en AERA (R1.0) con ese kernel; descifrado con PIN, datos móviles automáticos por la SIM 2 con ping, y "Reiniciar → Sistema" vuelve a Android |
| Rotación de pantalla (horizontal) | PASS (b24, b25) | | corregido con el parche `0006`; antes, con la resolución adaptativa, la imagen girada salía corrupta |
| Linterna | PASS (b25) | NOT TESTED | GPIO85 del TLMM vía `/tmp/spes-torch/brightness`; enciende y apaga desde los ajustes rápidos |
| microSD | PASS (detección) | | `/dev/block/mmcblk0p1` montado en `/external_sd`; visible por MTP |
| OTG | PASS (b36) | | pendrive Kingston DT microDuo 3C por USB 3.0 (xHCI en modo host): detectado como `sdg` (`sda`–`sdf` son la UFS), `sdg1` (ext2) montada por AERA en `/usb_otg` y su contenido visible. Solo se ofrece la primera partición (entrada única de `twrp.flags`) |
| PC Connection por Wi-Fi | PASS (b27) | | `https://192.168.100.71` y `aera.local` → 200; `/api/status` sin sesión → 401 |
| PC Connection por USB (`adb forward 8443:443`) | PASS (b25) | NOT TESTED | `https://localhost:8443` → 200; el mismo token funciona |
| PC Connection: backup y restore hacia o desde el PC en el navegador | NOT TESTED | | requiere navegador Chromium con selector de carpetas; AERA lo marca como Beta |
| Wi-Fi: arranque bajo demanda | PASS | NOT TESTED | IPA y módem arrancados, `wlan_pd` → "WLAN FW is ready" → driver → `wlan0` en ~10 s (`evidence/hw-wifi.txt`) |
| Wi-Fi: conexión desde la interfaz de AERA | PASS (b25: reconexión automática a la red guardada) | NOT TESTED | DHCP `192.168.100.70/24` y DNS configurados; ping del PC al teléfono 3/3; TCP a 1.1.1.1:443, 8.8.8.8:443 y google.com:443 |
| Datos móviles tras reiniciar y en español | PASS (b32) | | arranque limpio: disponible, conecta desde la página Red y todos los textos salen en español |
| Datos móviles: reconexión y nombre del operador | PASS (b31) | | arranque limpio y 3 ciclos seguidos de conectar/desconectar con APN automático; "CLARO EC" y ping en cada ciclo |
| Datos móviles (SIM 1, Claro, 4G) | PASS (b30) | NOT TESTED | conexión desde la página Red; APN `ba.amx` automático; IPv4 por `rmnet_aera`; ping 8.8.8.8 3/3 (~99 ms); DNS del operador; HTTP/HTTPS y tienda de plugins con el Wi-Fi apagado; al desconectar se limpian interfaz, ruta y DNS y el módem sigue en línea |
| Tienda de plugins (catálogo con internet) | PASS (b23, b25) | | `busybox wget` descarga `catalog.json` y `catalog.json.sig` a `/tmp/aera-plugin-store` |
| Wi-Fi tras un sideload | PASS (b27) · FAIL (b25) | | b25: AERA paraba los daemons (corrían desde `vendor`) y el módem perdía `wlan_pd`. b27: corren desde una copia en RAM; tras el sideload, mismos PID, sin "Root PD crashed" y con internet |
| Wi-Fi: sin escrituras en EFS ni persist reales | PASS | | SHA-256 de `modemst1/2`, `fsg`, `fsc` y `persist` reales idéntico antes y después de la sesión, aunque el módem escribió EFS (en las copias en RAM) |
| Compresión oficial (`AERA_USE_EXTREME_COMPRESSION`) | PASS (b28) | | sustituye a UPX; ramdisk 36 148 800 B; "AERA runtime: unpacked successfully in 2630 ms"; servicios sin abortos; descifrado con PIN correcto |
| Vibración: motor | PASS (b28) | | `AERA_NO_HAPTICS` quitado; el vibrador del PMIC (`/sys/class/leds/vibrator`, `duration` + `activate`) vibra al activarlo a mano |
| Vibración: respuesta háptica de la interfaz | PASS (b36) | | con la opción activada en AERA, el usuario la sintió al tocar; 88 cambios del motor registrados en 10 s (pulsos de 5 a 39 ms en `/sys/class/leds/vibrator/duration`) |
| Datos móviles: activados antes que el Wi-Fi (módem en frío) | PASS (b34) · FAIL (b33) | | b33: "QMI error 52 (request 46) [service 2]"; b34 reintenta DMS *Set Operating Mode*: 4G, "CLARO EC", APN `ba.amx` |
| Datos móviles: SIM con PIN | NOT TESTED | | ninguna SIM de pruebas tiene PIN; el usuario decidió no activarlo para la prueba (2026-11-23). El código es el oficial (UIM 0x26, sin reenvíos) |
| Datos móviles: SIM 2 y cambio entre SIM 1 y SIM 2 | PASS (b40) · FAIL (b36) | | dos SIM de Claro con datos. b36: la SIM 2 fallaba ("no provisioning application") y, tras forzarla a mano, los datos salían por la SIM 1. b40: SIM 2 → `100.72.198.81`, SIM 1 → `10.91.199.180`, SIM 2 → `100.72.198.81`, ping en cada cambio y la DDS del módem sigue a la SIM elegida (`MOBILE_DATA.md`, pasos 6 y 6b) |
| Datos móviles: SIM insertada en caliente | FAIL (b36) | | al meter la segunda SIM con el recovery arrancado, las dos quedaron en `initializing`; con las dos desde el arranque funciona. No corregido |
| Datos móviles: IPv4 privada en el detalle de conexión | PASS (b41) | | parche `0010`; la fila "IPv4 privada" cambia con cada SIM aunque la IPv4 pública sea la misma |
| Datos móviles: conexión automática al arrancar | PASS (b41) | | con "Conectar al iniciar" activado y la SIM 2 elegida: tras `fastboot boot` y descifrar con el PIN, conecta solo por la SIM 2 (`10.203.77.90`) con 1 min de uptime y ping OK. AERA lee el ajuste de `/data/media/0/AERA/preferences.conf`, así que sin descifrar no se conecta solo |
| AERA Browser: navegación | PASS (b33) | | parche `0008` (Zink en Adreno 610); google.com carga, algo lento (sin medir) |
| AERA Browser: navegación solo por datos móviles | PASS (b34) | | con el Wi-Fi apagado |
| AERA Browser: Enter desde el teclado (búsqueda de Google) | PASS (b35) · FAIL (b34) | | parche `0009`: la tecla ✓ envía Enter a la página |
| AERA Browser: descarga `https://` | PASS (b35) | | asset de Releases de GitHub, guardado en `AERA/Downloads` |
| AERA Browser: descarga `blob:` (botón "Download" de un archivo en GitHub) | FAIL (b35) | | no descarga nada; el worker precompilado del plugin ignora `blob:` (`KNOWN_ISSUES.md`); aportación futura para upstream |
| Root Manager | N/A | | no disponible con el kernel 4.19 no GKI (`KNOWN_ISSUES.md`) |

**Nivel alcanzado:** compila ✔ · arranca ✔ · funciona ✔ en pantalla, táctil, rotación, linterna, ADB, MTP, sideload, backup por ADB, particiones, descifrado con PIN, patrón y sin bloqueo, Wi-Fi, plugins, PC Connection, fastbootd y vuelta a Android. Además: datos móviles (4G, también con doble SIM), OTG, AERA Browser y vibración (motor y respuesta háptica) e instalación permanente. **No validado aún:** restore desde AERA, SIM con PIN, SIM insertada en caliente, spesn y la función de AERA que instala la ramdisk desde el propio recovery. **No funciona:** descargas `blob:` en AERA Browser (upstream). El port sigue siendo EXPERIMENTAL.

## Registro de ejecuciones

- 2026-11-20: `validate-tree.sh` → 0 fallos y 3 avisos (blobs, kernel y sin `boot.img`).
- 2026-11-20: `repo sync` iniciado dentro del contenedor `aera-spes` (imagen ext4).
- 2026-11-20: `lunch` → error en `BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE`; corregido.
- 2026-11-20: build 1 → FAIL (`TW_MAX_BRIGHTNESS`); valor 2047 leído del `dtbo` instalado; build 2 → PASS.
- 2026-11-20: hardware. Iteraciones de `fastboot boot`: (1) sin `twrpfastboot` → error fatal de init y vuelta al bootloader; (2) ramdisk de 49 MB → el ABL no arranca el kernel; (3) ramdisk gzip → falla el desempaquetado del initramfs; (4) ramdisk LZ4 de 39,6 MB → AERA arranca, pero el USB entra en bucle; (5) USB corregido → ADB funciona, pero keystore2, health y boot HAL abortan; (6) `task_profiles.json` y VINTF → todos los servicios activos y descifrado con PIN correcto.
- 2026-11-20: firmware instalado identificado (EvolutionX 16.0 11.10). Kernel y 33 blobs extraídos; `validate-tree.sh` da 0 fallos y 1 aviso (aún no hay `boot.img`).
- 2026-11-20: regresión de `build25-flashlight` → todo PASS salvo el Wi-Fi tras un sideload (FAIL) y PC Connection por Wi-Fi (BLOCKED por ese fallo).
- 2026-11-20: `build27-wlan-ram` (SHA-256 `9f29457b98ea98a1a8ed40694a4df3075b2d56a20d33a796d6531966c1936bcf`) → Wi-Fi con daemons en RAM, Wi-Fi tras un sideload y PC Connection por Wi-Fi: PASS.
- 2026-11-21: `build28-extreme-xz` (SHA-256 `9841966cf54c4ac35f0ef4a9ad03e1216fe139d4193b4b8fede572925c91ed11`) → arranca con la compresión oficial y descifra con PIN. AERA Browser sigue fallando en Zink (ver `KNOWN_ISSUES.md`).
- 2026-11-21: `build30-mobile-data` (SHA-256 `383e371730ff6cba3a544df9f9755f30b80ea41b07a89c6cc08534c17f7d24cc`) → datos móviles por 4G: PASS.
- 2026-11-21: `build31-mobile-data` (SHA-256 `25af3ab314fbd43b0047181063dac86cd86a460a27296cce8dce846aab7dc52b`) → reconexión repetida y nombre del operador: PASS.
- 2026-11-21: `build32-mobile-es` (SHA-256 `8c91f44a91c372695117e671d51b46218d9781741d3c6f274fdf4aa72a583544`) → datos móviles disponibles al arrancar y en español: PASS.
- 2026-11-23: `build33-browser` (SHA-256 `59c7522fd63617f595b324a1ac1271f5b247864f5e6ba8f8828d845abb103924`) → AERA Browser con el parche `0008`: PASS (carga google.com; algo lento). Datos móviles activados antes que el Wi-Fi: FAIL, "QMI error 52 (request 46) [service 2]".
- 2026-11-23: `build34-dms-retry` (SHA-256 `4eb21d6fc3ea324f4bf23b852a40f3fd77498ef3548d3f71494a4d789b2ebb11`) → datos móviles activados con el módem en frío (sin Wi-Fi): PASS (4G, CLARO EC, APN ba.amx); AERA Browser navegando por datos móviles: PASS.
- 2026-11-23: `build35-enter` (SHA-256 `c753884c86ff65dd4ea5123cf4d1602f78b498ff16f60cc9d311061f9c4791fc`) → AERA Browser: Enter desde el teclado en una página (búsqueda de Google) con el parche `0009`: PASS. Descarga de un asset de Releases de GitHub (`https://`): PASS. Botón "Download" de un archivo en GitHub (`blob:`): FAIL, no descarga nada (worker del runtime, ver `KNOWN_ISSUES.md`).
- 2026-11-23: `build36-maintainer` (SHA-256 `c17ddd661ba61b92f9c7919d7b257e1c8235e8ce16c3afc41a13a32898df7bf4`) → `AERA_MAINTAINER` "Michael Xavier" visible en la UI. Respuesta háptica de la interfaz: PASS. OTG: PASS. Dual SIM: la SIM 2 no conecta (sesión de aprovisionamiento vacía) y, al forzarla con UIM 0x38 a mano, los datos salen por la SIM 1 (DDS).
- 2026-11-23: `build37-ui-scale` → lienzo de la UI a 1280×2844 (`AERA_SCREEN_W/H` 960×2133): se ve más grande, pero varias pantallas de AERA tienen medidas fijas para 1440 de ancho. Descartado (`KNOWN_ISSUES.md`).
- 2026-11-23: `build40-dds-wait` (SHA-256 `bbd335c1242f18b82702e3f596517d95dd3f10462a3e2f68afc614c44e926bef`) → dual SIM: el proveedor rellena las sesiones UIM vacías y mueve la DDS (DSD 0x4E) a la SIM elegida, esperando a DSD 0x4F. SIM 1 ↔ SIM 2 sin reiniciar, cada una con su IP privada y ping: PASS. (b38 y b39 fueron pasos intermedios: b39 no veía la confirmación de la DDS por un error de código, corregido en b40.)
- 2026-11-23: `build41-private-ip` (SHA-256 `18817b760f53f118fc50bf40b163851054eebf46762f6800304b6dfce764bc67`) → parche `0010`: el detalle de conexión de datos móviles muestra la IPv4 privada; vista por el usuario al cambiar de SIM: PASS.
- 2026-11-23: `build41-private-ip` → conexión automática de datos al arrancar (SIM 2, tras descifrar): PASS.
- 2026-11-23: `build41-private-ip` → descifrado con patrón: PASS. Descifrado sin bloqueo (descifra solo): PASS. El usuario cambió el bloqueo en Android para cada prueba y luego volvió a su PIN.
- 2026-11-23: **build limpia final** `final-e038300` (`AERA-R1.0-Beta-Unofficial-spes.img`, SHA-256 `b35012ddbe375ba5f456088c9a5170c7b9af7a3b9e7a1fc479bd2b81a62d3337`, commit `e038300`, parches `0001`–`0010`, 14 min 05 s desde cero) → regresión rápida, todo PASS: arranque (R1.0, maintainer "Michael Xavier"); descifrado con PIN y servicios (keystore2, qseecomd, keymaster 4.1, gatekeeper); MTP (`18d1:4ee2`); conexión automática de datos por la SIM 2 al descifrar; cambio SIM 1 (`100.97.49.154`) ↔ SIM 2 (`100.64.148.215`) con ping; ADB sideload (zip de prueba, "Process ended with no errors"; AERA apaga los datos, como está previsto); Wi-Fi (ping y HTTPS); fastbootd (`is-userspace: yes`, `super`); vuelta a Android 16 (`sys.boot_completed=1`, slot `_a`). No se repitieron en esta imagen: rotación, linterna, OTG, navegador, backup por ADB, PC Connection ni descifrado con patrón o sin bloqueo (probados en b25–b41).
- 2026-11-23: **instalación permanente** (autorizada por el usuario). Copia en el PC de `boot`, `vendor_boot`, `dtbo`, `vbmeta` y `vbmeta_system` de los dos slots, `persist`, `modemst1/2`, `fsg` y `fsc` (`aera_source/backup_spes/2026-11-23/`, `SHA256SUMS` verificado; `persist` leído con un remontaje temporal en solo lectura, porque AERA lo usa). `boot_a-installed-repack.img` (SHA-256 `6f6abb42cf3fdf0115bd4d75b6f5787ef9b527287f64714708e2294e30866dc0`): kernel del `boot_a` instalado y ramdisk de la build final, con la cabecera original. Con `fastboot boot`, el ABL pasa `androidboot.force_normal_boot=1` y arranca **Android** (completo y con root), lo que validó el arranque normal antes de escribir. `fastboot flash boot_a`, verificado leyendo la partición: Android PASS; `adb reboot recovery` → AERA PASS (descifrado, datos móviles); vuelta a Android desde AERA PASS. `vbmeta` tiene la verificación desactivada (flags 3), así que el `boot` modificado no necesita firma.
