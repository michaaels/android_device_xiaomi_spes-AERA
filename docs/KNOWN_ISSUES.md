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
3. **Límite de ramdisk**: queda ~1,9 MB de margen hasta lo comprobado (41,5 MB). Añadir funciones (Wi-Fi, vibración, idiomas extra) obliga a volver a medir; `validate-tree.sh` falla si se superan los 40 MB.
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

- El firmware WLAN de SM6225 corre en el módem (`icnss`). Al pulsar "Start WLAN", `spes-wlan-up.sh` monta en solo lectura el `vendor` instalado y la partición `modem`, carga la IPA (`/dev/ipa`) y arranca los daemons stock (`qrtr-ns`, `pd-mapper`, `rmt_storage`, `tftp_server` y `cnss-daemon`) desde ese vendor. `spes-modem-hold.sh` mantiene encendido el módem; el envoltorio de `wpa_supplicant` escribe `ON` en `/dev/wlan` y espera a `wlan0`.
- **Sandbox:** EFS en loops respaldados por copias en RAM, `persist/rfs` en tmpfs y `/data/vendor/{wifi,tombstones}` en tmpfs. Verificado en hardware: las particiones reales no cambian.
- `pm-service` del vendor no puede registrarse en el `vndservicemanager` de recovery (no hay contextos de servicio del vendor); se sustituye por mantener abierto `/dev/subsys_modem`.
- Depende del vendor instalado: con otro firmware, las rutas o los daemons pueden cambiar.
- Mientras el Wi-Fi está activo, los nodos `by-name` de EFS apuntan a las copias en RAM, así que un backup de EFS desde AERA en ese momento leería la copia (con lo que haya escrito el módem en la sesión). Lo recomendable es hacer los backups de EFS sin el Wi-Fi activado.

## Problemas abiertos de AERA en spes

- **Rotación horizontal**: con `AERA_UI_ADAPTIVE_RESOLUTION`, la imagen sale corrupta al girar a horizontal. No se guarda en los ajustes y un reinicio la quita. Sin investigar todavía.
- **Backup por ADB**: el núcleo de AERA hace `fsync()` sobre la FIFO de ADB y marca el backup como fallido aunque los datos sean correctos. Hay un parche mínimo en `patches/bootable_recovery/0001-partition-skip-fsync-on-ADB-backup-stream.diff` (solo omite el `fsync` si el destino es una FIFO; la restauración sigue sincronizando la partición), probado en hardware y pendiente de proponer upstream. Además, AERA no atiende `adb backup` mientras muestra la pantalla de descifrado (hay que descifrar u omitir antes), y sin descifrar registra `Unable to chmod … recovery.log`, que es solo cosmético.
- **Escrituras persistentes de AERA** (comportamiento de AERA, no del port): sus ajustes y logs en `/data/media/0/AERA/` (descifrado) o en `/data/recovery/AERA/` y `/data/recovery/.version` (sin descifrar).
- **AERA escribe en `persist`:** heredado de OrangeFox, guarda sus ajustes en `/persist/.aera` y la copia del bloqueo por contraseña de AERA en `/persist/.fsec`, y cada vez que guarda ajustes monta `/persist` en lectura-escritura (`data.cpp` → `SaveValues`, `variables.h`). Comprobado en hardware: el superbloque registra `Last mounted on: /persist` durante una sesión de AERA, aparece `.aera` y cambia `.fsec`. No afecta a los datos de calibración, pero es una modificación persistente. Corrección propuesta y pendiente: montar `/persist` en solo lectura en `twrp.flags` y redirigir los ajustes con `AERA_SETTINGS_ROOT_DIRECTORY=/data/recovery`, como hace garnet.
- **Lentitud de la interfaz**: mejora con la resolución adaptativa, pero el renderizado sigue siendo por software (sin GPU).

## Funciones fuera de la primera versión

- Linterna: no configurada (`AERA_FLASHLIGHT_ENABLE` / `AERA_FL_PATH1`). Hay que comprobar si el kernel de EvolutionX expone el LED del flash en `/sys/class/leds`; el kernel de OrangeFox del usuario lleva un parche para ello.
- Vibración (`AERA_NO_HAPTICS`): hay que incluir el servicio AIDL `vendor.qti.hardware.vibrator` de EvolutionX.
- Wi-Fi: **implementado** (ver la sección siguiente). PC Connection probada por Wi-Fi y por USB (API y aprobación). Pendiente: backup y restore hacia el PC desde el navegador, NAS (SMB/SFTP) y la reconexión tras desactivar y activar varias veces.
- Aceleración GPU para LVGL: se usa renderizado por software.
- Audio y redes móviles: fuera de alcance.
- Plugins (SSH/SFTP, MCP Bridge, AI Diagnostics): etapa 2, no se implementan.

## Entorno de build

- El volumen NTFS `/mnt/2E6421A46421702F` tiene una entrada corrupta (`aera_source/aera.ext4`) que dejó un `fallocate` fallido de ntfs3. Se repara con `chkdsk /f` desde Windows.
- Ethernet `enp129s0` (host): a veces NetworkManager no instala las rutas IPv4 aunque el DHCP sí entrega la puerta de enlace (`routers = 192.168.100.1`). Ocurre cuando la concesión llega después de que la conexión ya figura como activada (`acd pending`). Sin ruta por defecto ni ruta `/24` en `enp129s0`, el IPv4 sale por Wi-Fi; el IPv6 no se ve afectado. Se comprueba con `ip route get 1.1.1.1`. `nmcli device reapply` no basta; se corrige reactivando la conexión con `nmcli con up "Conexión cableada 1"`. Puede repetirse tras reiniciar o reconectar el cable (verificado el 2026-11-20).
