# Problemas conocidos y pendientes

## Bloqueos resueltos (2026-11-20)

- **Kernel**: se extrajo del `boot.img` del firmware instalado (EvolutionX 16.0 11.10, Linux 4.19.325-cip132-st16-Cherry). La trazabilidad está en `prebuilt/kernel.info`.
- **Blobs**: los 33 ficheros salen de la partición `vendor` de ese mismo firmware (`vendor.img` extraído de `payload.bin`, con el hash verificado). Los checksums están en `tools/blobs.sha256`.

## Problemas resueltos en hardware (2026-11-20)

| Síntoma | Causa | Solución |
|---|---|---|
| `fastboot boot` vuelve al bootloader a los 10 s | sin `twrpfastboot=1`, el init intenta un arranque normal de Android (`force_normal_boot=1`) | `--cmdline twrpfastboot=1` en `BOARD_MKBOOTIMG_ARGS` |
| `Booting OKAY`, pero el kernel no arranca | límite del ABL para ramdisks (≥ 42,4 MB) | ramdisk recortada a 39,6 MB; validador ≤ 40 MB |
| "rootfs image is not initramfs" | ramdisk gzip tras la LZ4 de `vendor_boot` | LZ4 obligatorio |
| Sin USB y la interfaz lenta | manejadores USB duplicados en bucle | el `init.rc` base gestiona adb/fastboot; el rc del dispositivo, solo MTP |
| La interfaz se queda en el logo | keystore2 abortaba, sin Keymaster ni `task_profiles.json` | `task_profiles.json` y manifests VINTF |

## Pendientes

1. Escenarios de descifrado sin probar: sin bloqueo, patrón, credencial incorrecta y cancelar. Tampoco MTP con transferencia, sideload, backup/restore desde AERA ni la variante spesn (ver `TESTING.md`).
3. **Límite de ramdisk**: el bootloader no arranca ramdisks de ≥ 42,4 MB (41,5 MB comprobado). Desde la build 28 se usa el mecanismo oficial `AERA_USE_EXTREME_COMPRESSION` (runtime de AERA comprimido con XZ dentro de la ramdisk; el init lo descomprime en RAM en ~2,6 s) en lugar de UPX: la ramdisk mide 36,1 MB y quedan ~5,4 MB de margen. `validate-tree.sh` falla si se supera el límite.
4. **Funciones de AERA retiradas** por tamaño: flasheo directo de payloads (necesita `aera-otaripper`), `lpdump` y `bootctl` (`lptools` sí está), fuentes CJK/árabe/hebreo/índicas/tailandés (los nombres de fichero en esas escrituras no se ven) y bash/nano GNU.
5. **Memoria de build**: `soong_build` necesita ~20 GB de RAM. Con aplicaciones pesadas abiertas, el sistema lo mata (OOM).

## Riesgos técnicos

- **⚠️ No flashear `boot.img` tal cual para arrancar Android.** La cabecera declara `os_version 99.87.36` y `os_patch_level 2099-12`, porque `PLATFORM_*` lo exige el descifrado en recovery; el `boot` de EvolutionX declara 16.0.0 / 2026-08. Si Android arranca con esta cabecera, el bootloader pasa ese nivel de parche al TEE y el Keymaster de Android puede actualizar sus claves de forma permanente. Volver al boot original dejaría entonces `/data` sin poder descifrarse. En recovery no ocurre: el vold de AERA solo escribe las claves actualizadas en `/tmp` (`system/vold/KeyStorage.cpp`). La instalación permanente solo debe hacerse con el repack de AERA sobre el `boot` actual, que conserva la cabecera original. Que el repack conserve la cabecera está **[PEND]** de verificar.

- **La imagen depende del firmware.** El kernel y los blobs son de EvolutionX 11.10. Con MIUI o con otra ROM, el descifrado puede fallar y el kernel no corresponde. Al cambiar de firmware hay que regenerarlos con `tools/extract-stock-kernel.sh` y `tools/extract-files.sh`.
- **Librerías AOSP del ramdisk.** Los blobs necesitan `android.hardware.keymaster@4.0/4.1`, `android.hardware.gatekeeper@1.0`, `android.hardware.boot@1.0/1.1/1.2`, libbinder, libhidlbase, libxml2, libcrypto, etc. Se supone que el build de AERA los incluye en el ramdisk; se comprobará en la imagen generada.
- **Variante.** No está confirmado que EvolutionX exponga `ro.boot.product.hardware.sku`. Si no lo hace, el script deja los valores del build (spes).
- **`odm` / `mi_ext`.** EvolutionX no tiene ninguna de las dos. `mi_ext` se queda en el fstab con `nofail` para quien use MIUI.
- **`overrideprops.sh` (OFox) eliminado.** OFox lo usaba para esquivar el anti-rollback de OTA. Si hiciera falta, irá como un cambio aparte y documentado.
- **SELinux.** No se fuerza el modo permisivo. La cmdline de `vendor_boot` [EVOX] no incluye `androidboot.selinux`.

## Wi-Fi: diseño y límites

- El firmware WLAN de SM6225 corre en el módem (`icnss`). Al pulsar "Start WLAN", `spes-wlan-up.sh` monta en solo lectura el `vendor` instalado y la partición `modem`, carga la IPA (`/dev/ipa`) y copia a la RAM los daemons stock (`qrtr-ns`, `pd-mapper`, `rmt_storage`, `tftp_server` y `cnss-daemon`) con sus librerías, para que no dependan del montaje de `vendor`. Los arranca desde esa copia. `spes-modem-hold.sh` mantiene encendido el módem; el envoltorio de `wpa_supplicant` escribe `ON` en `/dev/wlan` y espera a `wlan0`.
- **Sandbox:** EFS en loops respaldados por copias en RAM, `persist/rfs` en tmpfs y `/data/vendor/{wifi,tombstones}` en tmpfs. Verificado en hardware: las particiones reales no cambian.
- `pm-service` del vendor no puede registrarse en el `vndservicemanager` de recovery (no hay contextos de servicio del vendor); se sustituye por mantener abierto `/dev/subsys_modem`.
- Depende del vendor instalado: con otro firmware, las rutas o los daemons pueden cambiar.
- Mientras el Wi-Fi está activo, los nodos `by-name` de EFS apuntan a las copias en RAM, así que un backup de EFS desde AERA en ese momento leería la copia (con lo que haya escrito el módem en la sesión). Lo recomendable es hacer los backups de EFS sin el Wi-Fi activado.

## Problemas abiertos de AERA en spes

- **Wi-Fi tras un sideload (resuelto en la build 27)**: al terminar un sideload (y al flashear), AERA para todos los procesos que usan particiones dinámicas para poder desmapearlas (`QuiesceDynamicPartitionUsers`). Cuando los daemons del Wi-Fi corrían desde el `vendor` montado, AERA los paraba, el módem reportaba "Root PD crashed" y el Wi-Fi no volvía. Los árboles oficiales con particiones dinámicas (dada, instantnoodlep) llevan esos daemons en la ramdisk, pero spes no tiene espacio. Por eso `spes-wlan-up.sh` los copia a la RAM (`/tmp/spes_vendor`, 3,3 MB: 5 binarios, 18 librerías y el árbol `rfs`) y los servicios corren desde ahí. Verificado: tras el sideload no se para ningún servicio y hay internet.
- **Rotación horizontal (resuelto)**: con renderizado por software y `AERA_UI_ADAPTIVE_RESOLUTION`, AERA copiaba el frame horizontal de LVGL como si fuera vertical y la imagen salía corrupta. El parche `0006` lo gira con la misma transformación que usa el táctil. Verificado en hardware (build 24).
- **Backup por ADB**: el núcleo de AERA hace `fsync()` sobre la FIFO de ADB y marca el backup como fallido aunque los datos sean correctos. Hay un parche mínimo en `patches/bootable_recovery/0001-partition-skip-fsync-on-ADB-backup-stream.diff` (solo omite el `fsync` si el destino es una FIFO; la restauración sigue sincronizando la partición), probado en hardware y pendiente de proponer upstream. Además, AERA no atiende `adb backup` mientras muestra la pantalla de descifrado (hay que descifrar u omitir antes), y sin descifrar registra `Unable to chmod … recovery.log`, que es solo cosmético.
- **Escrituras persistentes de AERA** (comportamiento de AERA, no del port): sus ajustes y logs en `/data/media/0/AERA/` (descifrado) o en `/data/recovery/AERA/` y `/data/recovery/.version` (sin descifrar).
- **Ajustes de AERA en `persist` (convención oficial):** antes del PIN, `/data` no se puede montar (cifrado de metadatos), así que, como el árbol oficial de AERA para el Xiaomi 15, los ajustes van a `/persist/AERA` (`AERA_SETTINGS_ROOT_DIRECTORY=/persist` y `AERA_ALLOW_EARLY_SETTINGS_LOAD=1`). Así el idioma se aplica ya en la pantalla del PIN; `early-ui.conf` se escribe al guardar preferencias con los datos descifrados. Se probó antes `/data/recovery` con `persist` en solo lectura, pero dejaba la pantalla del PIN en inglés; el usuario eligió la convención oficial. El `/persist/.aera` y el `.fsec` vaciado de sesiones anteriores se restauraron con su autorización.
- **Plugins y descargas**: AERA descarga el catálogo, los plugins, las fuentes y las actualizaciones con `busybox wget`, así que el busybox estático de AERA va en `/sbin/busybox` (`AERA_USE_BUSYBOX_BINARY=1`). Sin él, con internet, la tienda de plugins no carga. El `wget` de busybox no valida certificados TLS ("TLS certificate validation not implemented"); el catálogo se acepta solo si su firma `.sig` es válida. Verificado: catálogo descargado por Wi-Fi (build 23).
- **Wi-Fi con `/persist` montada**: como AERA monta `/persist` en lectura-escritura para sus ajustes, un segundo montaje en solo lectura falla. `spes-wlan-up.sh` copia `rfs`/`hlos_rfs` a la RAM desde el montaje existente (solo lee).
- **Lentitud de la interfaz**: mejora con la resolución adaptativa, pero el renderizado sigue siendo por software (sin GPU).

## Traducciones de AERA (upstream)

- Español: 2094 de 2768 cadenas traducidas (76 %); las 674 restantes aparecen en inglés. Las 6 que estaban corruptas se corrigen con el parche `0002`.
- Otros idiomas tienen el mismo daño de codificación (`?` en lugar de letras acentuadas): ca_ES 9, cs_CZ 18, de_DE 9, fr_FR 18, hu 25, ja_JP 4, nl_NL 3, no_NO 6, pl_PL 9, pt_BR 7, pt_PT 8, ro_RO 16, sv_SE 23, tr_TR 17 y vi_VN 26 cadenas. Sin corregir; conviene reportarlo upstream.

## Funciones fuera de la primera versión

- **Root Manager**: no es viable con el kernel de EvolutionX. AERA solo trae módulos KernelSU para kernels GKI 6.1, 6.6, 6.12 y 6.18; spes usa 4.19 (no GKI). Los árboles oficiales con kernels antiguos (4.19 y 4.4) lo tienen desactivado (`AERA_ENABLE_ROOT_MANAGER=0`).
- **AERA Browser (plugin)**: bloqueado en el runtime del plugin. Se añadió lo que el árbol debe aportar: firmware de la Adreno 610 (`a630_sqe.fw`, `a610_zap.*`) y `kgsl-3d0`/`ion` en 0666 para el proceso aislado (UID 99090). Con eso la GPU arranca y Turnip la detecta ("Found compatible device '/dev/kgsl-3d0'"), pero Zink no crea la pantalla EGL ("egl: failed to create dri2 screen" → "Could not create surfaceless EGL display: EGL_NOT_INITIALIZED") y el motor WebKit aborta. Hay que reportarlo a los mantenedores del plugin con ese log.

- Linterna: **implementada**. El flash de spes es `CAM_FLASH_TYPE_GPIO`; el modo linterna es el GPIO85 del TLMM y el kernel de EvolutionX no tiene LED class. `spes-torch-setup.sh` deja el GPIO85 apagado al arrancar y enlaza `/tmp/spes-torch/brightness` a su `value` (`AERA_FL_PATH1`). No se toca el GPIO93 (flash de alta corriente). Verificado en hardware (build 25): enciende y apaga desde los ajustes rápidos.
- Vibración: **activada** (build 28). El vibrador del PMIC aparece como LED (`/sys/class/leds/vibrator`, `duration` + `activate`), que minui usa directamente sin el HAL AIDL; se probó a mano en hardware. En AERA hay que activar la respuesta háptica en Ajustes (viene apagada en las preferencias).
- Wi-Fi: **implementado** (ver la sección siguiente). PC Connection probada por Wi-Fi y por USB (API y aprobación). Pendiente: backup y restore hacia el PC desde el navegador, NAS (SMB/SFTP) y la reconexión tras desactivar y activar varias veces.
- Aceleración GPU para LVGL: se usa renderizado por software.
- **Datos móviles: implementados** (build 30). `mobile_data/` contiene el proveedor `aera-cellular-provider`: es el de infiniti (commit `f7fca594`, mismo camino de datos IPA/`rmnet_ipa0`) con `qmi.hpp` y `sim.hpp` idénticos a los oficiales, y con lo propio de spes aislado en `spes_platform.hpp`. Tres cosas son propias de spes: (1) el módem se arranca con la misma preparación que el Wi-Fi (EFS y `persist` en RAM) y queda compartido con él, así que desactivar los datos solo cierra la sesión; (2) el recovery se detecta por el servicio de init `recovery`, porque en spes `ro.bootmode` queda en `unknown` (el recovery va en `boot`); (3) el formato de datos es QMAP v1, porque el módem del SM6225 rechaza QMAPv5. Solo internet (sin llamadas ni SMS). Verificado con una SIM de Claro: 4G, APN `ba.amx` detectado automáticamente, ping, DNS del operador, HTTP/HTTPS y tienda de plugins con el Wi-Fi apagado; al desconectar se borran la interfaz, la ruta y el DNS.
- Datos móviles, pendiente: el nombre del operador sale ilegible. El análisis del TLV de PLMN es código compartido de AERA, sin cambios aquí; hay que revisarlo con el formato que envía este módem. Sin probar: SIM con PIN, cambio entre dos SIM y conexión automática al arrancar.
- Audio: fuera de alcance.
- Plugins (SSH/SFTP, MCP Bridge, AI Diagnostics): etapa 2, no se implementan.

## Entorno de build

- El volumen NTFS `/mnt/2E6421A46421702F` tiene una entrada corrupta (`aera_source/aera.ext4`) que dejó un `fallocate` fallido de ntfs3. Se repara con `chkdsk /f` desde Windows.
- Ethernet `enp129s0` (host): a veces NetworkManager no instala las rutas IPv4 aunque el DHCP sí entrega la puerta de enlace (`routers = 192.168.100.1`). Ocurre cuando la concesión llega después de que la conexión ya figura como activada (`acd pending`). Sin ruta por defecto ni ruta `/24` en `enp129s0`, el IPv4 sale por Wi-Fi; el IPv6 no se ve afectado. Se comprueba con `ip route get 1.1.1.1`. `nmcli device reapply` no basta; se corrige reactivando la conexión con `nmcli con up "Conexión cableada 1"`. Puede repetirse tras reiniciar o reconectar el cable (verificado el 2026-11-20).
