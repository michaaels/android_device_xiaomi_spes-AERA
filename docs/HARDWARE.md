# Hardware: Redmi Note 11 / 11 NFC (`spes` / `spesn`)

Leyenda de evidencia:
- **[STOCK]**: leído del volcado público del vendor stock `spes-development/spes-vendor-dump`, rama `missi_phoneext4_global-user-13-TKQ1.221114.001-V816.0.8.0.TGCMIXM-release-keys` (MIUI 14 global, vendor del 2024-09-29).
- **[OFOX]**: valor del árbol OrangeFox `fox-12.1` (Jashkirat, commit `14bdaf8`). Viene de la comunidad y no está confirmado con el stock.
- **[PEND]**: pendiente de confirmar en el hardware con ADB (comandos en la última sección).

## Identificación

| Dato | Valor | Fuente |
|---|---|---|
| SoC | Qualcomm SM6225 (Snapdragon 680), plataforma `bengal` | [STOCK] `ro.board.platform` / README del volcado |
| CPU | 4× Cortex-A73 + 4× Cortex-A53 (Kryo 265), ABI arm64-v8a (+ armeabi-v7a en Android) | [STOCK] abilist |
| GPU | Adreno 610 | especificación comercial |
| Kernel stock | Linux **4.19.157** (no GKI) | [STOCK] README del volcado |
| Primer API | 30 (Android 11): `ro.product.first_api_level=30`, `ro.board.first_api_level=30` | [STOCK] |
| Vendor | Android 12 (`ro.vendor.build.version.release=12`), parche 2024-10-01 | [STOCK] |

### Variantes `spes` / `spesn`

Las dos variantes usan **el mismo firmware**. El vendor importa `/vendor/build_${ro.boot.product.hardware.sku}.prop`:

| SKU (`ro.boot.product.hardware.sku`) | device | modelo |
|---|---|---|
| `k7t` | spes | 2201117TG |
| `k7tin` | spes | 2201117TI |
| `k7tl` | spes | 2201117TL |
| `k7tn` | **spesn** (NFC) | 2201117TY |

[STOCK] `build_k7t*.prop`. El árbol OrangeFox distingue la variante por `ro.boot.hwc` (la región: GLOBAL/EUROPE), y eso no se corresponde con el SKU. Este port usa el SKU (`recovery/root/system/bin/variant-script.sh`). En el recovery, la única diferencia entre variantes es el NFC, que este port no usa.

## Arranque y particiones

| Aspecto | Valor | Fuente |
|---|---|---|
| Esquema | A/B con **Virtual A/B** (`ro.virtual_ab.enabled=true`) | [STOCK] |
| Particiones dinámicas | sí (`ro.boot.dynamic_partitions=true`), grupo `qti_dynamic_partitions` | [STOCK] / [OFOX] |
| Particiones lógicas | system, system_ext, product, vendor, mi_ext | [STOCK] fstab. `odm` aparece en [OFOX] pero **no** en el fstab stock → [PEND] `lpdump` |
| Boot header | v3, con `vendor_boot` aparte (DTB y ramdisk de vendor) | [OFOX]; coherente con el lanzamiento en API 30 con VAB → [PEND] cabecera real |
| Partición recovery | **no existe**; el recovery va dentro de `boot` (recovery-in-boot) | [OFOX] → [PEND] `ls /dev/block/by-name` |
| `init_boot` | no existe (es de Android 13+ con GKI) | [PEND] |
| Tamaño de `boot` | 134217728 (128 MiB) | [OFOX] → [PEND] |
| Tamaño de `vendor_boot` | 100663296 (96 MiB) | [OFOX] → [PEND] |
| Tamaño de `dtbo` | 25165824 (24 MiB) | [OFOX] → [PEND] |
| Tamaño de `super` | 9126805504 | [OFOX] → [PEND] |
| Kernel cmdline | la aporta `vendor_boot` en header v3; OFox usa `androidboot.usbcontroller=4e00000.dwc3` | [OFOX] → [PEND] `/proc/cmdline` |
| AVB | `vbmeta` y `vbmeta_system`; para arrancar una imagen propia hace falta el bootloader desbloqueado | [STOCK] fstab (`avb=vbmeta_system`) |

## Sistemas de ficheros y cifrado

| Punto de montaje | FS | Opciones relevantes | Fuente |
|---|---|---|---|
| `/data` (userdata) | f2fs | `fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0`, `metadata_encryption=aes-256-xts:wrappedkey_v0`, `keydirectory=/metadata/vold/metadata_encryption`, `checkpoint=fs`, `inlinecrypt` | [STOCK] |
| `/metadata` | ext4 | first_stage_mount | [STOCK] |
| particiones lógicas | ext4 ro | | [STOCK] |
| `/mnt/vendor/persist` | ext4 | | [STOCK] |
| modem / bluetooth | vfat ro | | [STOCK] |
| dsp | ext4 ro | | [STOCK] |
| microSD | vfat (voldmanaged), host `4784000.sdhci` | | [STOCK] |

- Cifrado: **FBE v2 + metadata encryption con claves envueltas (wrapped keys, inline crypto)**. Las props `ro.crypto.volume.filenames_mode=aes-256-cts`, `ro.crypto.volume.metadata.method=dm-default-key` y `ro.crypto.dm_default_key.options_format.version=2` vienen del stock [STOCK].
- HAL de seguridad [STOCK, VINTF]: **Keymaster 4.x QTI** (`android.hardware.keymaster@4.1-service-qti`, el manifest declara 4.0), **Gatekeeper 1.0 QTI**, `qseecomd` y servicio `vendor.qti.hardware.qseecom@1.0`. No hay KeyMint, Weaver ni SPU.
- Boot control [STOCK]: `android.hardware.boot@1.1-service` con la implementación `android.hardware.boot@1.0-impl-1.1-qti.so`.
- Health [STOCK]: `android.hardware.health@2.1-service` con `android.hardware.health@2.0-impl-2.1-qti.so`.

## Controladores y firmware

- Módulos en `/vendor/lib/modules` [STOCK `modules.load`]: solo audio (`audio_*`), `exfat.ko`, `rdbg.ko` y **`qca_cld3_wlan.ko`** (Wi-Fi). La pantalla, el táctil, UFS y USB **van integrados en el kernel**, así que el recovery no necesita cargar módulos para pantalla, táctil, almacenamiento ni USB.
- Wi-Fi: `qca_cld3_wlan.ko` y firmware `bdwlan.*` / `wlanmdsp.mbn` en la partición modem [STOCK]. Queda fuera de la primera versión.
- Vibración [STOCK]: `vendor.qti.hardware.vibrator.service` (AIDL), `vendor.qti.hardware.vibrator.impl.so`, `libqtivibratoreffect.so`.
- Táctil: en `ueventd.rc` aparecen nodos `secure_touch` en varios buses i2c, pero el modelo concreto del panel táctil no está identificado → [PEND] `getevent -lp`.
- Brillo: `/sys/class/backlight/panel0-backlight/brightness` [OFOX]; valor máximo → [PEND].
- Controlador USB: dwc3 en `4e00000` [OFOX] → [PEND].

## Comandos de solo lectura para completar los [PEND]

Con Android arrancado y la depuración USB activada (no necesitan root, salvo donde se indica):

```bash
adb shell getprop | grep -E "ro.boot.(slot_suffix|product.hardware.sku|hwc|bootdevice|usbcontroller)|ro.product.vendor.device|ro.build.fingerprint|ro.boot.dynamic_partitions|ro.virtual_ab"
adb shell ls -l /dev/block/by-name/ | grep -E " (boot|recovery|vendor_boot|init_boot|dtbo|super|vbmeta)"
adb shell cat /proc/cmdline                     # puede requerir root
adb shell su -c 'for p in boot_a vendor_boot_a dtbo_a super; do echo $p $(blockdev --getsize64 /dev/block/by-name/$p); done'
adb shell su -c 'lpdump'                        # lista real de particiones lógicas
adb shell cat /sys/class/backlight/panel0-backlight/max_brightness
adb shell getevent -lp | head -40               # dispositivos de entrada (táctil, botones)
adb shell uname -a
```

Las salidas se guardan en `docs/evidence/` para que quede constancia.
