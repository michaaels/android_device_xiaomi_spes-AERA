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
| Artefacto de referencia en hardware | PASS | `fastboot boot`: R1.0, 0 aborts, todos los servicios en marcha, UDC enlazado; backup por ADB de `/boot` en 16 s, idéntico a la copia `dd` |

## Pruebas en hardware

Dispositivo: spes, SKU `k7t` (2201117TG), bootloader desbloqueado, slot `a`, EvolutionX 16.0 11.10 instalado. **Procedimiento:** solo `fastboot boot` (en RAM); no se ha escrito ninguna partición. Imagen probada: `build11-vintf`, SHA-256 `d69b491b1c0439a19ae007adcc98688de58821284530d37b7d6c1f665bba3ba3`. Evidencia en `docs/evidence/`.

| Prueba | spes | spesn | Evidencia |
|---|---|---|---|
| `fastboot boot` aceptado y kernel arrancado | PASS | NOT TESTED | `hw-abl-ramdisk-limit.txt` (antes, BLOCKED por el límite de ramdisk y por la ramdisk gzip) |
| Arranque de AERA (init, interfaz LVGL) | PASS | NOT TESTED | logo, interfaz y menús vistos por el usuario; `ro.aera.release.version=R1.0` |
| Pantalla y brillo | PASS | NOT TESTED | `max_brightness=2047`, brillo 1200 aplicado (`hw-aera-first-boot.txt`) |
| Renderizador | NOT TESTED (detalle) | | DRM `card0` presente; el renderizador exacto no está verificado |
| Táctil (`fts_ts`, FocalTech) | PASS | NOT TESTED | el usuario manejó los menús; `getevent` |
| Botones (power, volumen) | PASS | NOT TESTED | menú de power y volumen responden (`gpio-keys`, `qpnp_pon`) |
| Fluidez de la interfaz | PASS (tras la corrección USB) | | antes iba lenta por el bucle de `init` del USB (`kmsg-usb-diag.txt`) |
| ADB (shell como root) | PASS | NOT TESTED | `18d1:d001`, `UDC=4e00000.dwc3` |
| Variante detectada por SKU | PASS (`k7t` → spes 2201117TG) | NOT TESTED (`k7tn`) | `hw-aera-first-boot.txt` |
| Servicios (logd, keystore2, qseecomd, keymaster 4.1, gatekeeper 1.0, boot 1.2, health 2.1) | PASS, 0 aborts | NOT TESTED | `hw-aera-services-decrypt.txt` |
| Detección de particiones | PASS | NOT TESTED | todas las de `twrp.flags` y las lógicas `_a` (`recovery.log`) |
| Descifrado con PIN | PASS | NOT TESTED | "User 0 Decrypted Successfully", `/data` en dm-default-key y `/data/media/0` legible (`hw-aera-recovery-log-decrypt.txt`) |
| Descifrado sin contraseña | NOT TESTED | NOT TESTED | requiere un dispositivo sin bloqueo |
| Descifrado con patrón | NOT TESTED | NOT TESTED | el dispositivo de pruebas usa PIN |
| Credencial incorrecta | PASS | NOT TESTED | la interfaz muestra "That credential did not unlock data. Please try again."; en el log, `GateKeeper response error` → `Failed to decrypt user 0`, y `/data/media/0` sigue con nombres cifrados |
| Cancelar el desbloqueo (Omitir) | PASS (con `AERA_UI_ADAPTIVE_RESOLUTION`) | NOT TESTED | sin él, el teclado tapaba el botón; con él, entra al menú y los datos siguen cifrados |
| Claves de Android intactas tras descifrar en AERA | PASS | | el usuario desbloqueó Android con su PIN tras la sesión de AERA y confirmó que apps y fotos están bien (2026-11-20); por código, las claves actualizadas se escriben solo en `/tmp` |
| MTP (enumeración) | PASS | NOT TESTED | el PC ve `18d1:4ee2 (MTP + debug)` con `mtp,adb` |
| MTP (transferencia de ficheros) | PASS | NOT TESTED | 1 MB aleatorio subido y bajado; SHA-256 igual en el PC, el teléfono y la copia descargada; fichero de prueba borrado. La microSD también aparece |
| ADB sideload | PASS | NOT TESTED | zip inofensivo (`aera-sideload-test.zip`): "Installing zip file '/sideload/package.zip'", "AERA spes sideload test: OK", "Process ended with no errors" |
| Fastbootd | PASS | NOT TESTED | `adb reboot fastboot` → `is-userspace: yes`, `super-partition-name: super`, `snapshot-update-status: none` |
| Reinicio a bootloader (desde la interfaz y por adb) | PASS | | |
| Volver a Android con normalidad | PASS | NOT TESTED | `fastboot reboot` desde fastbootd → `sys.boot_completed=1`, Android 16, slot `_a` |
| Batería y temperatura | PASS (lectura) | | capacidad 100 %, cargando, 31,1 °C; CPU `pm6125-tz` 37 °C |
| Backup de particiones (desde OrangeFox, solo lectura) | PASS | | 15 particiones verificadas con SHA-256 (fuera del repositorio) |
| Backup desde AERA por ADB (`adb backup --twrp boot`) | PASS con el parche `patches/bootable_recovery/0001` | | los 128 MiB son idénticos a la copia `dd` (`9f132dc1…`) y el stream acaba en `twendadb`. Sin el parche, AERA lo da por fallido ("Unable to flush '/tmp/twadbbackup': Invalid argument"). Solo funciona fuera de la pantalla de descifrado |
| Restore desde AERA | NOT TESTED | | escribe en particiones; queda para el final y requiere autorización |
| Rotación de pantalla (horizontal) | FAIL | | con la resolución adaptativa, la imagen girada sale corrupta; no se guarda, y un reinicio la quita |
| Linterna | NOT IMPLEMENTED | | |
| microSD | PASS (detección) | | `/dev/block/mmcblk0p1` montado en `/external_sd`; visible por MTP |
| OTG | NOT TESTED | | |
| PC Connection | NOT TESTED | | |
| Wi-Fi | NOT TESTED (no implementado) | | |
| Vibración | NOT TESTED (desactivada) | | |

**Nivel alcanzado:** compila ✔ · arranca ✔ · funciona en lo básico (pantalla, táctil, ADB, particiones, descifrado con PIN, fastbootd, vuelta a Android) ✔. **No validado aún:** el resto de escenarios de descifrado, MTP con transferencia, sideload, backup/restore desde AERA, spesn y la instalación permanente. El port sigue siendo EXPERIMENTAL.

## Registro de ejecuciones

- 2026-11-20: `validate-tree.sh` → 0 fallos y 3 avisos (blobs, kernel y sin `boot.img`).
- 2026-11-20: `repo sync` iniciado dentro del contenedor `aera-spes` (imagen ext4).
- 2026-11-20: `lunch` → error en `BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE`; corregido.
- 2026-11-20: build 1 → FAIL (`TW_MAX_BRIGHTNESS`); valor 2047 leído del `dtbo` instalado; build 2 → PASS.
- 2026-11-20: hardware. Iteraciones de `fastboot boot`: (1) sin `twrpfastboot` → error fatal de init y vuelta al bootloader; (2) ramdisk de 49 MB → el ABL no arranca el kernel; (3) ramdisk gzip → falla el desempaquetado del initramfs; (4) ramdisk LZ4 de 39,6 MB → AERA arranca, pero el USB entra en bucle; (5) USB corregido → ADB funciona, pero keystore2, health y boot HAL abortan; (6) `task_profiles.json` y VINTF → todos los servicios activos y descifrado con PIN correcto.
- 2026-11-20: firmware instalado identificado (EvolutionX 16.0 11.10). Kernel y 33 blobs extraídos; `validate-tree.sh` da 0 fallos y 1 aviso (aún no hay `boot.img`).
