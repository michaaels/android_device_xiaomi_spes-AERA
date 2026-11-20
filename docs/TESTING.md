# Pruebas y validación

Estados: **PASS** · **FAIL** · **BLOCKED** · **NOT TESTED**. Cada resultado indica su evidencia.

Hay tres niveles de validación, y cumplir uno no implica los siguientes: **compila** → **arranca** → **funciona correctamente**.
**Estado actual: COMPILA (2026-11-20). No se ha comprobado que arranque ni que funcione: el port sigue siendo EXPERIMENTAL.**

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
| SHA-256 del artefacto | PASS | **build limpio, de referencia**: `7fa53ef7ed9870d246413df0bcab909ea66fa6b4a217f73ab8fbae360f44647f`; incremental: `0b6dcea3…` (`boot.img` = `AERA-R1.0-Beta-Unofficial-spes.img` en ambos) |

## Pruebas en hardware

Procedimiento: siempre con `fastboot boot` (arranque temporal, ver `RECOVERY_PLAN.md`). Nunca con `fastboot flash` mientras haya filas en NOT TESTED.

| Prueba | spes | spesn | Evidencia esperada |
|---|---|---|---|
| Arranque temporal (`fastboot boot`) | NOT TESTED | NOT TESTED | foto de pantalla + `adb shell dmesg` |
| Reinicio a recovery / a sistema | NOT TESTED | NOT TESTED | |
| Interfaz LVGL, renderizador y fps | NOT TESTED | NOT TESTED | `/tmp/recovery.log` (línea del renderizador) |
| Táctil y botones (vol+/vol-/power) | NOT TESTED | NOT TESTED | `getevent -lp` |
| Brillo | NOT TESTED | NOT TESTED | |
| ADB shell y `adb pull /tmp/recovery.log` | NOT TESTED | NOT TESTED | |
| Detección de particiones (lógicas y físicas) | NOT TESTED | NOT TESTED | `lpdump`, listado de particiones en la UI |
| Descifrado sin contraseña | NOT TESTED | NOT TESTED | `/data/media/0` legible |
| Descifrado con PIN | NOT TESTED | NOT TESTED | |
| Descifrado con patrón | NOT TESTED | NOT TESTED | |
| Credencial incorrecta (rechazada, `/data` intacto) | NOT TESTED | NOT TESTED | |
| Cancelar el desbloqueo | NOT TESTED | NOT TESTED | |
| Backup de boot, vendor_boot, dtbo, efs y persist | NOT TESTED | NOT TESTED | |
| Restore (solo en un entorno con backup comprobado) | NOT TESTED | NOT TESTED | |
| MTP | NOT TESTED | NOT TESTED | |
| ADB sideload | NOT TESTED | NOT TESTED | |
| Fastbootd (`fastboot getvar is-userspace`) | NOT TESTED | NOT TESTED | |
| microSD / OTG | NOT TESTED | NOT TESTED | |
| PC Connection (USB) | NOT TESTED | NOT TESTED | |
| Wi-Fi | NOT TESTED (no implementado) | | |
| Vibración | NOT TESTED (desactivada) | | |
| Volver a Android con normalidad | NOT TESTED | NOT TESTED | arranque completo del firmware instalado (EvolutionX) |
| Variante detectada por SKU | NOT TESTED | NOT TESTED | `getprop ro.product.device` |

## Registro de ejecuciones

- 2026-11-20: `validate-tree.sh` → 0 fallos y 3 avisos (blobs, kernel y sin `boot.img`).
- 2026-11-20: `repo sync` iniciado dentro del contenedor `aera-spes` (imagen ext4).
- 2026-11-20: `lunch` → error en `BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE`; corregido.
- 2026-11-20: build 1 → FAIL (`TW_MAX_BRIGHTNESS`); valor 2047 leído del `dtbo` instalado; build 2 → PASS.
- 2026-11-20: firmware instalado identificado (EvolutionX 16.0 11.10). Kernel y 33 blobs extraídos; `validate-tree.sh` da 0 fallos y 1 aviso (aún no hay `boot.img`).
