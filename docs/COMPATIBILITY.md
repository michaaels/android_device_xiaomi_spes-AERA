# Matriz de adaptación: OrangeFox `fox-12.1` (spes) → AERA `aera-16.0`

Estados: **Directo** (compatible directamente) · **Adaptado** (requiere adaptación, ya hecha) · **Implementar** (requiere implementación) · **HW** (requiere validación en hardware) · **Bloqueado** (bloqueado por una dependencia).

## Sistema de build

| Elemento OrangeFox | AERA | Estado | Notas |
|---|---|---|---|
| Variables `TW_*` / `OF_*` / `FOX_*` | Solo `AERA_*` | Adaptado | `bootable/recovery/aera_config.mk` las traduce internamente. `tools/validate-tree.sh` comprobó **63/63** flags usadas contra las fuentes AERA. |
| `vendorsetup.sh` con `FOX_*` | `AERA_*` + `AERA_BUILD_DEVICE` | Adaptado | Se eliminaron `AERA_DELETE_AROMAFM` y `AERA_DELETE_MAGISK_ADDON`: nada las lee. |
| `OF_MAINTAINER`, `FOX_VERSION`, addon de Magisk | `AERA_MAINTAINER`; sin addon | Adaptado | No se distribuye ningún zip de Magisk (OFox lo incluía en `addon/`). |
| `twrp.dependencies` (kernel desde fuente) | Kernel prebuilt del stock | Adaptado | Ver la sección Kernel. |
| `BOARD_VNDK_VERSION`, `PRODUCT_TARGET_VNDK_VERSION` | eliminados | Adaptado | VNDK está obsoleto en Android 16. |
| `TARGET_2ND_ARCH` (arm) | `core_64_bit_only` | Adaptado | Los blobs de recovery son de 64 bits. |
| `TARGET_CPU_VARIANT := cortex-a73` | `generic` + `TARGET_CPU_VARIANT_RUNTIME := cortex-a73` | Adaptado / HW de build | Igual que dada. Se confirma al compilar. |
| `virtual_ab_ota.mk`, `updatable_apex.mk`, `developer_gsi_keys.mk`, `full_base_telephony.mk`, `phone-xhdpi-6144-dalvik-heap.mk` | `virtual_ab_ota/launch_with_vendor_ramdisk.mk` + `base.mk` | Adaptado / build | Se confirma que la ruta existe en AOSP 16 al compilar. |
| `bootctrl/` y `gpt-utils/` (fuente qcom-caf) | `boot@1.2-service` de AOSP + blob `boot@1.0-impl-1.2-qti` del vendor instalado | Adaptado / HW | `hardware/qcom-caf/bootctrl` no está en el manifest AERA. |
| `vendor.qti.hardware.vibrator.*` compilado desde fuente | `AERA_NO_HAPTICS` | Implementar | La fuente qcom no está en el manifest. Habrá que incluir el blob AIDL stock. |
| `update_engine`, `otapreopt_script`, `checkpoint_gc`, fastboot mock | eliminados del device tree | Adaptado | AERA ya aporta fastbootd y sideload (`AERA_INCLUDE_FASTBOOTD`). |

## Kernel, boot y particiones

| Elemento | Estado | Notas |
|---|---|---|
| Header v3 + recovery-in-boot (`BOARD_USES_RECOVERY_AS_BOOT`) | Adaptado / HW | Confirmado que AERA lo soporta (`bootable/recovery/Android.mk`, `data.cpp`). |
| `BOARD_INCLUDE_DTB_IN_BOOTIMG`, offsets de kernel/ramdisk/tags/DTB | eliminados | En header v3 el DTB va en `vendor_boot` y los offsets no se usan. |
| `BOARD_KERNEL_CMDLINE` (incluido `androidboot.selinux=permissive`) | eliminado | En v3 la cmdline la aporta `vendor_boot`. No se fuerza SELinux permisivo. |
| `BOARD_RAMDISK_USE_LZ4` | **Obligatorio** (HW) | La ramdisk de `boot` se concatena tras la LZ4 *legacy* de `vendor_boot`; con gzip falla el initramfs. Además, el ABL no arranca ramdisks ≥ 42,4 MB, así que se retiró contenido opcional hasta 39,6 MB (`evidence/hw-abl-ramdisk-limit.txt`). |
| Kernel desde fuente `mi-sdm680/android_kernel_xiaomi_sm6225` (`spes-r-oss`) | Adaptado → kernel del firmware instalado | Se usa el prebuilt de EvolutionX 11.10 (4.19.325 Cherry). El kernel de un recovery-in-boot también arranca Android, así que tiene que coincidir con el vendor instalado. |
| fstab | Adaptado | Hecho a partir del `fstab.qcom` de EvolutionX y del `fstab.default` de MIUI, que coinciden. Sin `odm`; `mi_ext` va con `nofail`, porque solo existe en MIUI. |
| `twrp.flags` | Adaptado | Se añadieron `vendor_boot`, `vbmeta`, `vbmeta_system` y microSD (`mmcblk0`). Se quitó `/cust`, que no aparece en el fstab stock. |
| Particiones dinámicas / lptools / dmctl | Directo | Flags AERA estándar. |
| Fastbootd | Adaptado / HW | `AERA_INCLUDE_FASTBOOTD` + función `ffs.fastboot` en el rc USB. |

## Init y servicios

| Elemento | Estado | Notas |
|---|---|---|
| `init.recovery.qcom.rc` | Adaptado | Enlace a bootdevice, `boot-hal-1-2` (como el vendor instalado), `health-hal-2-1` y script de variante. |
| `overrideprops.sh` (pone a cero `ro.*.build.date.utc`) | eliminado | Servía para saltarse el anti-rollback de OTAs en OFox. Se deja fuera hasta que se demuestre que hace falta (ver KNOWN_ISSUES). |
| `variant-script.sh` por `ro.boot.hwc` | Adaptado | Ahora por `ro.boot.product.hardware.sku`. |
| `ueventd.qcom.rc`, manifiestos VINTF de OFox | sustituidos por **manifests VINTF mínimos** propios (framework: hidl.manager/token/memory; dispositivo: keymaster 4.1, gatekeeper 1.0, boot 1.2) | Sin manifests, `hwservicemanager` se desactiva y ningún HAL HIDL se registra (HW). |
| `task_profiles.json` | añadido (de `system/core`) | Sin él abortan logd, keystore2 y health (HW). |
| `AERA_ENABLE_ALL_PARTITION_TOOLS`, bash/nano/tar/sed/grep GNU, `aera-otaripper`, `htop`, fuentes de escrituras extra | retirados | Por el límite de ramdisk del ABL. Quedan lptools, toybox y el extractor nativo de payloads. |

## Pantalla y entrada

| Elemento | Estado | Notas |
|---|---|---|
| Ruta de brillo, brillo por defecto 1200 y 90 fps | Adaptado / HW | Valores de OFox, sin validar en hardware. |
| Interfaz LVGL de AERA y renderizador | HW | Se espera framebuffer/DRM por software. La aceleración Adreno 610 (EGL) no está configurada: los árboles de referencia que la usan traen blobs gráficos de su propio SoC, que no sirven aquí. |
| Táctil | HW | El driver está integrado en el kernel. Debería funcionar sin módulos. |
| Vibración | Implementar | Ver arriba. |

## Cifrado

| Elemento | Estado | Notas |
|---|---|---|
| FBE v2 + metadata (wrapped keys) | Adaptado / HW | `AERA_INCLUDE_CRYPTO(_FBE)`, `AERA_INCLUDE_FBE_METADATA_DECRYPT`, `AERA_USE_FSCRYPT_POLICY=2`. |
| Keymaster 4.1 / Gatekeeper 1.0 / qseecomd | Adaptado → HW | 33 blobs del vendor de EvolutionX 11.10, con el cierre de dependencias revisado mediante `readelf` (`tools/blobs.sha256`). |
| `AERA_DEFAULT_KEYMASTER_VERSION=4.1` + `AERA_FORCE_KEYMASTER_VER` | Adaptado | Equivale a `OF_DEFAULT_KEYMASTER_VERSION` / `TW_FORCE_KEYMASTER_VER` de OFox. |

## USB y conectividad

| Elemento | Estado | Notas |
|---|---|---|
| ADB / sideload / MTP / fastbootd (configfs) | Adaptado → **PASS** (ADB, MTP enumerado, fastbootd) | adb, sideload y fastboot los gestiona el `init.rc` de AERA. El rc del dispositivo solo activa configfs y añade MTP. Duplicar los manejadores dejaba el gadget sin enlazar (`evidence/kmsg-usb-diag.txt`). |
| PC Connection de AERA (USB) | HW | Funcionalidad existente de AERA. No se tocó. |
| Wi-Fi | **Adaptado → PASS** | `AERA_ENABLE_WLAN`, con el módem y los daemons del vendor instalado cargados en tiempo de ejecución y sandbox en RAM (`init.recovery.wifi.rc`, `spes-wlan-up.sh`). |
| Batería y temperatura | HW | Health 2.1. |
| Audio | fuera de alcance | Opcional. |
