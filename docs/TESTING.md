# Pruebas y validación

Estados: **PASS** · **FAIL** · **BLOCKED** · **NOT TESTED**. Cada resultado indica su evidencia.

Hay tres niveles de validación, y cumplir uno no implica los siguientes: **compila** → **arranca** → **funciona correctamente**.
**Estado actual (2026-11-20): COMPILA y ARRANCA en hardware (spes); la funcionalidad básica está verificada y el resto sigue pendiente. EXPERIMENTAL.**

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

Dispositivo: spes, SKU `k7t` (2201117TG), bootloader desbloqueado, slot `a`, EvolutionX 16.0 11.10 instalado. **Procedimiento:** solo `fastboot boot` (en RAM); no se ha escrito ninguna partición. Imagen de la última regresión (2026-11-20): `build25-flashlight`, SHA-256 `01fa83b1161485af46c9f1a451881c3fec90ce30b636b49eaf62d1a3d3075fc1` (parches 0001–0006, busybox, ajustes en `/persist`). Las filas marcadas **(b25)** se repitieron con ella; el resto viene de builds anteriores (primera: `build11-vintf`). Evidencia en `docs/evidence/`.

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
| Descifrado sin contraseña | NOT TESTED | NOT TESTED | requiere un dispositivo sin bloqueo |
| Descifrado con patrón | NOT TESTED | NOT TESTED | el dispositivo de pruebas usa PIN |
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
| Rotación de pantalla (horizontal) | PASS (b24, b25) | | corregido con el parche `0006`; antes, con la resolución adaptativa, la imagen girada salía corrupta |
| Linterna | PASS (b25) | NOT TESTED | GPIO85 del TLMM vía `/tmp/spes-torch/brightness`; enciende y apaga desde los ajustes rápidos |
| microSD | PASS (detección) | | `/dev/block/mmcblk0p1` montado en `/external_sd`; visible por MTP |
| OTG | NOT TESTED | | |
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
| PC Connection por Wi-Fi | PASS (antes) · BLOCKED (b25) | | en esta regresión no se pudo repetir por el fallo anterior |
| Wi-Fi: sin escrituras en EFS ni persist reales | PASS | | SHA-256 de `modemst1/2`, `fsg`, `fsc` y `persist` reales idéntico antes y después de la sesión, aunque el módem escribió EFS (en las copias en RAM) |
| Compresión oficial (`AERA_USE_EXTREME_COMPRESSION`) | PASS (b28) | | sustituye a UPX; ramdisk 36 148 800 B; "AERA runtime: unpacked successfully in 2630 ms"; servicios sin abortos; descifrado con PIN correcto |
| Vibración | NOT TESTED (desactivada) | | |

**Nivel alcanzado:** compila ✔ · arranca ✔ · funciona ✔ en pantalla, táctil, rotación, linterna, ADB, MTP, sideload, backup por ADB, particiones, descifrado con PIN, Wi-Fi, plugins, PC Connection, fastbootd y vuelta a Android. **No validado aún:** restore desde AERA, descifrado sin bloqueo o con patrón, OTG, spesn, vibración y la instalación permanente. El port sigue siendo EXPERIMENTAL.

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
- 2026-11-23: `build35-enter` (SHA-256 `c753884c86ff65dd4ea5123cf4d1602f78b498ff16f60cc9d311061f9c4791fc`) → AERA Browser: Enter desde el teclado en una página (búsqueda de Google) con el parche `0009`: PASS. Descargas desde GitHub: sin diagnosticar (ver `KNOWN_ISSUES.md`).
