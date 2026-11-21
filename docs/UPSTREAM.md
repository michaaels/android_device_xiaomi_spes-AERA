# Origen del código, cambios y contribución

## Upstream y fuentes

| Fuente | Uso | Licencia |
|---|---|---|
| `AERA-Recovery/android_manifest` `aera-16.0` | manifest de build | sin fichero de licencia (componentes AOSP Apache-2.0) |
| `AERA-Recovery/android_bootable_recovery` `aera-16.0` | **sin cambios**; solo se consulta para verificar flags y el soporte de recovery-as-boot | GPL-3.0 / Apache-2.0 según el fichero |
| `AERA-Recovery/android_device_xiaomi_dada-AERA`, `garnet-AERA` | convenciones (estructura, nombres `AERA_*`, `vendorsetup.sh`, rc USB) | Apache-2.0 / GPL-3.0 (cabeceras) |
| `OrangeFox/device/spes` `fox-12.1` (Jashkirat) | valores de placa (tamaños, plataforma, brillo, pantalla) | Apache-2.0 (cabeceras LineageOS) / GPL-3.0 (`vendorsetup.sh`) |
| `spes-development/spes-vendor-dump` | fstab, props, VINTF, lista de módulos y blobs (como referencia) | firmware propietario de Xiaomi/Qualcomm |
| `device/qcom/twrp-common` (AERA) | servicios de descifrado Qualcomm (vía `qcom_decrypt*`) | sin cambios |

### Repositorio descartado

`Aim-uses-Malware/android_device_spes-AERA` (2026-10-16) es un intento previo de AERA para spes. **No se ha reutilizado código**: no tiene licencia, incluye blobs de origen no documentado y valores marcados como TODO. Solo sirvió para confirmar que no existe un port oficial.

## Cambios en componentes AERA

El device tree no modifica AERA. Hay **un parche genérico** propuesto para `bootable/recovery`, que se guarda aparte y no se aplica desde el árbol:

- `patches/bootable_recovery/0001-partition-skip-fsync-on-ADB-backup-stream.diff`: en `TWPartition::Raw_Read_Write`, omite `fsync()` cuando el destino es una FIFO (el stream de `adb backup`), donde siempre falla con `EINVAL` y hacía que AERA diera por fallido un backup correcto. Las escrituras a ficheros y particiones, incluida la restauración por ADB, siguen sincronizándose. Probado en spes; candidato a PR upstream (no enviado).

- `patches/bootable_recovery/0002-catalog-fix-corrupted-Spanish-translations.diff`: en `aeraui/localization/catalog/catalog.json`, 6 cadenas `es-ES` tenían `?` en lugar de `ó`, `ú`, `ñ` o `í` (por ejemplo "A?adir red" o "Mostrar contrase?a"). Después hay que regenerar `catalog_generated.cpp` con `generate_catalog.py`, que lo hace `tools/apply-aera-patches.sh`; se comprobó que el generador reproduce exactamente el fichero de upstream a partir del JSON original. Detectado por el usuario en la pantalla de Wi-Fi.

No se ha tocado el Plugin SDK.

## Atribución

- `init.recovery.usb.rc` es nuevo (Apache-2.0). La primera versión se basaba en la plantilla BSD de The Linux Foundation; se reescribió para delegar en el `init.rc` de AERA y ya no contiene ese código.
- `BoardConfig.mk`, `device.mk`, `twrp_spes.mk` y `AndroidProducts.mk` conservan el copyright de LineageOS 2021 del árbol spes original.

## Contribución oficial

Repositorio propuesto: `android_device_xiaomi_spes-AERA`, rama `aera-16.0`, ruta `device/xiaomi/spes`.

Condiciones antes de proponerlo:
1. Build reproducible con el manifest público.
2. Kernel y blobs con procedencia documentada (`prebuilt/kernel.info` y `tools/blobs.sha256`).
3. Matriz de `TESTING.md` en PASS para arranque, pantalla, táctil, ADB, particiones, descifrado y vuelta a Android.

No se ha hecho push, PR ni release.
