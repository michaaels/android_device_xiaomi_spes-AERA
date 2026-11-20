# Pruebas y validación

Estados: **PASS** · **FAIL** · **BLOCKED** · **NOT TESTED**. Cada resultado indica su evidencia.

Hay tres niveles de validación, y cumplir uno no implica los siguientes: **compila** → **arranca** → **funciona correctamente**.
**Estado actual: ninguno de los tres se ha alcanzado. El port es EXPERIMENTAL.**

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
| Blobs presentes | BLOCKED (0/26) | falta extraerlos |
| Kernel prebuilt presente | BLOCKED | falta el `boot.img` stock |
| Parseo de Make/Soong por el propio build (`lunch`) | NOT TESTED | requiere el sync completo y el kernel |

## Pruebas de compilación

| Prueba | Resultado | Evidencia |
|---|---|---|
| Build limpio `mka bootimage` | BLOCKED | kernel y blobs |
| Build incremental | NOT TESTED | |
| Cabecera v3 / kernel idéntico / tamaño ≤ partición | NOT TESTED | |
| Contenido del ramdisk sin restos de builds anteriores | NOT TESTED | |
| SHA-256 del artefacto | NOT TESTED | no hay artefacto |

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
| Volver a Android con normalidad | NOT TESTED | NOT TESTED | arranque completo de MIUI/HyperOS |
| Variante detectada por SKU | NOT TESTED | NOT TESTED | `getprop ro.product.device` |

## Registro de ejecuciones

- 2026-11-20: `validate-tree.sh` → 0 fallos y 3 avisos (blobs, kernel y sin `boot.img`).
- 2026-11-20: `repo sync` iniciado dentro del contenedor `aera-spes` (imagen ext4).
