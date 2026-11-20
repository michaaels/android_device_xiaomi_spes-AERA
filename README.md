# AERA Recovery: Xiaomi Redmi Note 11 / 11 NFC (`spes` / `spesn`)

Device tree de [AERA Recovery](https://github.com/AERA-Recovery) (`aera-16.0`) para el Redmi Note 11 (SM6225 / Snapdragon 680).

> **Estado: EXPERIMENTAL. Todavía no compila, no arranca y no está validado en hardware.**
> Bloqueos actuales: falta el kernel del `boot.img` stock y falta extraer los blobs (ver [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)).

| | |
|---|---|
| SoC | Qualcomm SM6225 `bengal`, Adreno 610 |
| Pantalla | AMOLED 1080×2400, 90 Hz |
| Arranque | A/B con Virtual A/B, boot header v3 + `vendor_boot`; **recovery dentro de `boot`** (sin partición recovery) |
| Cifrado | FBE v2 + metadata, wrapped keys; Keymaster 4.1 / Gatekeeper 1.0 QTI |
| Variantes | una sola imagen; spes o spesn se detecta por `ro.boot.product.hardware.sku` |

## Compilación (resumen)

```bash
repo init -u https://github.com/AERA-Recovery/android_manifest.git -b aera-16.0 --depth=1
repo sync -c --no-clone-bundle --no-tags -j$(nproc)
git clone <este repo> device/xiaomi/spes
device/xiaomi/spes/tools/extract-stock-kernel.sh <stock boot.img> .
device/xiaomi/spes/tools/extract-files.sh --adb
export AERA_BUILD_DEVICE=spes
source build/envsetup.sh && lunch twrp_spes-bp2a-eng
mka adbd bootimage
```

Los detalles están en [docs/BUILD.md](docs/BUILD.md). Para probarlo **solo** con `fastboot boot` y con copia de seguridad previa, sigue [docs/RECOVERY_PLAN.md](docs/RECOVERY_PLAN.md).

## Documentación

- [HARDWARE](docs/HARDWARE.md): datos verificados y pendientes de confirmar.
- [COMPATIBILITY](docs/COMPATIBILITY.md): matriz de adaptación de OrangeFox a AERA.
- [BUILD](docs/BUILD.md): entorno y compilación.
- [TESTING](docs/TESTING.md): matriz de pruebas y evidencias.
- [KNOWN_ISSUES](docs/KNOWN_ISSUES.md): bloqueos y limitaciones.
- [RECOVERY_PLAN](docs/RECOVERY_PLAN.md): copias de seguridad, arranque temporal y restauración.
- [UPSTREAM](docs/UPSTREAM.md): origen del código y contribución.

## Créditos

Valores de placa del árbol OrangeFox spes (Jashkirat, fox-12.1) y de LineageOS. Convenciones de los árboles oficiales AERA (dada, garnet). Lo demás está detallado en [docs/UPSTREAM.md](docs/UPSTREAM.md).
