# Hardware: Redmi Note 11 / 11 NFC (`spes` / `spesn`)

Leyenda de evidencia:
- **[EVOX]**: firmware **instalado** en el dispositivo de pruebas: EvolutionX 16.0 `20260807` 11.10 Official (Android 16, SDK 36). Datos sacados de su `boot.img`, de `vendor_boot.img` y de la partición `vendor` extraída de `payload.bin`, con el hash verificado contra el manifest del payload. Evidencia completa en [evidence/evolutionx-16.0-11.10.txt](evidence/evolutionx-16.0-11.10.txt).
- **[STOCK]**: volcado público del vendor MIUI 14 global V816.0.8.0.TGCMIXM (`spes-development/spes-vendor-dump`).
- **[OFOX]**: árbol OrangeFox `fox-12.1`. Valor de la comunidad, sin confirmar.
- **[HW]**: leído en el dispositivo de pruebas por ADB desde AERA (solo lectura, 2026-11-23).
- **[PEND]**: falta confirmarlo en el hardware con ADB.

## Identificación

| Dato | Valor | Fuente |
|---|---|---|
| SoC | Qualcomm SM6225 (Snapdragon 680), plataforma `bengal` | [STOCK] |
| CPU | 4× Cortex-A73 + 4× Cortex-A53 (Kryo 265) | especificación |
| GPU | Adreno 610 | especificación |
| Kernel instalado | **Linux 4.19.325-cip132-st16-Cherry** (custom, clang 21, imagen gzip) | [EVOX] |
| Kernel stock MIUI | Linux 4.19.157 | [STOCK] |
| Primer API | 30 (Android 11) | [STOCK] |
| Vendor instalado | Android 16, parche de vendor 2026-05-01 | [EVOX] |

### Variantes `spes` / `spesn`

Un solo firmware para ambas variantes: el paquete EvolutionX declara `pre-device=spes,spesn` [EVOX]. En stock, el vendor elige `build_${ro.boot.product.hardware.sku}.prop` [STOCK]:

| SKU | device | modelo |
|---|---|---|
| `k7t` / `k7tin` / `k7tl` | spes | 2201117TG / TI / TL |
| `k7tn` | **spesn** (NFC) | 2201117TY |

El port detecta la variante por el SKU (`variant-script.sh`). [HW]: el bootloader pone `ro.boot.product.hardware.sku=k7t` y `ro.boot.hwc=Global` en el teléfono de pruebas (spes). Falta un spesn para confirmar `k7tn`.

## Arranque y particiones

| Aspecto | Valor | Fuente |
|---|---|---|
| Esquema | A/B con **Virtual A/B y compresión VABC (gz)** | [EVOX] payload |
| Particiones del payload | boot, dtbo, vendor_boot, vbmeta, vbmeta_system, system, system_ext, product, vendor | [EVOX] |
| Grupo `super` | `qti_dynamic_partitions`, 9122611200 bytes: **system, system_ext, product, vendor** (sin `odm` ni `mi_ext`) | [EVOX]. MIUI añade `mi_ext` [STOCK] |
| Boot header | **v3** (`boot.img`), `vendor_boot` v3 con DTB de 3858030 bytes | [EVOX] |
| Recovery | **dentro de `boot`**: el ramdisk de boot de EvolutionX ya es un recovery (`/system/bin/recovery`, fastbootd, minadbd) | [EVOX] |
| Partición recovery | **no existe**: no hay `recovery`, `recovery_a` ni `recovery_b` en `/dev/block/by-name` | [HW] |
| `init_boot` | no existe | [EVOX] payload |
| Tamaño de `boot` | **134217728** (128 MiB) | [EVOX] |
| Tamaño de `vendor_boot` | **100663296** (96 MiB) | [EVOX] |
| Tamaño de `dtbo` | **25165824** (24 MiB) | [EVOX] |
| Tamaño de `super` | 9126805504 (grupo más 4 MiB de metadatos) | [HW] `blockdev --getsize64` (coincide con [OFOX]) |
| Compresión del ramdisk | **LZ4** (boot y vendor_boot) | [EVOX] |
| Cmdline (`vendor_boot`) | `androidboot.console=ttyMSM0 androidboot.hardware=qcom androidboot.memcg=1 androidboot.usbcontroller=4e00000.dwc3 console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0x4a90000 loop.max_part=7 lpm_levels.sleep_disabled=1 msm_rtb.filter=0x237 service_locator.enable=1 swiotlb=2048 kpti=off kasan=off` | [EVOX] |
| Módulos en primera etapa | ninguno (el ramdisk de vendor solo contiene `fstab.qcom`) | [EVOX] |
| AVB | vbmeta y vbmeta_system; para imágenes propias hace falta el bootloader desbloqueado | [EVOX] |

## Sistemas de ficheros y cifrado

Idéntico en [EVOX] y [STOCK]:

| Punto de montaje | FS | Opciones relevantes |
|---|---|---|
| `/data` | f2fs | `fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0`, `metadata_encryption=aes-256-xts:wrappedkey_v0`, `keydirectory=/metadata/vold/metadata_encryption`, `checkpoint=fs`, `inlinecrypt` |
| `/metadata` | ext4 | first_stage_mount |
| system, system_ext, product, vendor | ext4 ro (lógicas) | |
| persist | ext4 | |
| modem / bluetooth | vfat ro | |
| dsp | ext4 ro | |
| microSD | vfat, `4784000.sdhci` (`mmcblk0p1` / `mmcblk1p1`) | |

- Cifrado: **FBE v2 + metadata encryption con wrapped keys (inline crypto)**.
- HAL de seguridad [EVOX]: `android.hardware.keymaster@4.1-service-qti`, `android.hardware.gatekeeper@1.0-service-qti`, `qseecomd` y `vendor.qti.hardware.qseecom@1.0-service`. No hay KeyMint, Weaver ni SPU.
- Boot control [EVOX]: `android.hardware.boot@1.2-service` con `android.hardware.boot@1.0-impl-1.2-qti.so`. MIUI usa la 1.1 [STOCK].
- Health [EVOX]: AIDL `android.hardware.health-service.qti`. El recovery de EvolutionX usa `health-service.qti_recovery`.

## Controladores y firmware

- `modules.load` de vendor **vacío** [EVOX]. Pantalla, táctil, UFS, USB y Wi-Fi van integrados en el kernel Cherry, así que el recovery no necesita cargar módulos. `lcd.ko` es la librería genérica de clase LCD y no se carga.
- Firmware de Wi-Fi: `/vendor/firmware/wlan/qca_cld` [EVOX].
- Vibración: `vendor.qti.hardware.vibrator.service` (AIDL) [EVOX]. En el kernel es un LED del PMIC, `/sys/class/leds/vibrator` (`duration` + `activate`), que AERA usa sin el HAL [HW].
- Brillo: `/sys/class/backlight/panel0-backlight/brightness`, `max_brightness` = **2047** [HW].
- Linterna: GPIO85 del TLMM (`CAM_FLASH_TYPE_GPIO`); el kernel no tiene LED class para el flash [HW].
- GPU: Adreno 610 (`/dev/kgsl-3d0`); para AERA Browser hacen falta `a630_sqe.fw` y `a610_zap.*` en `/vendor/firmware` [HW].
- Módem y Wi-Fi: MPSS con firmware de la partición `modem`, IPA con `ipa_fws`, datos por `rmnet_ipa0` (ver [MOBILE_DATA.md](MOBILE_DATA.md)) [HW].
- Controlador USB: **dwc3 `4e00000`** [EVOX cmdline].

## Acoplamiento firmware ↔ imagen

`boot.img` contiene el kernel, así que la imagen AERA lleva el kernel de **EvolutionX 11.10**. Arrancarla con otro firmware (MIUI u otra ROM) supone ejecutar un kernel que no corresponde a ese `vendor_boot`/vendor. Con `fastboot boot` el riesgo es bajo, porque no se escribe nada. **Instalarla en otro firmware no está soportado**: para cada firmware hay que regenerar `prebuilt/kernel` y los blobs.

## Comandos de solo lectura para cerrar los [PEND]

Ya se ejecutaron en spes (marcados [HW]); sirven para repetirlos en un spesn.

```bash
adb shell getprop | grep -E "ro.boot.(slot_suffix|product.hardware.sku|hwc|bootdevice)|ro.product.vendor.device"
adb shell ls -l /dev/block/by-name/ | grep -E " (boot|recovery|vendor_boot|init_boot|dtbo|super)"
adb shell cat /sys/class/backlight/panel0-backlight/max_brightness
adb shell getevent -lp | head -40
```
