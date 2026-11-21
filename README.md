# AERA Recovery: Xiaomi Redmi Note 11 / 11 NFC (`spes` / `spesn`)

Device tree de [AERA Recovery](https://github.com/AERA-Recovery) (`aera-16.0`) para el Redmi Note 11 (SM6225 / Snapdragon 680).

> **Estado: EXPERIMENTAL. Compila y arranca en un spes real con `fastboot boot`.** Verificado: interfaz, táctil, botones, ADB, MTP (enumeración), fastbootd, detección de particiones, **descifrado FBE con PIN** y vuelta a Android. También: PIN incorrecto rechazado, Omitir, transferencia MTP, sideload y backup por ADB (con el parche `patches/bootable_recovery/0001`). **Wi-Fi** con conexión a Internet (el módem arranca con sandbox en RAM; EFS y persist intactos). Pendiente: patrón y sin bloqueo, restore, spesn, rotación horizontal (falla), linterna, backup hacia el PC desde el navegador e instalación permanente. **PC Connection** probada por Wi-Fi (`https://aera.local`) y por USB ([docs/TESTING.md](docs/TESTING.md)).
> Imagen de referencia (build limpio con Wi-Fi): SHA-256 `b4964c11fea3d22348cb176c967fc42e00dae44adfe1702534933f2019335999`.
> ⚠️ Solo para `fastboot boot`. No lo flashees como `boot` (ver [docs/RECOVERY_PLAN.md](docs/RECOVERY_PLAN.md)).
> Kernel y blobs ya incluidos, de **EvolutionX 16.0 11.10**, el firmware de referencia instalado. La imagen solo debe usarse con ese firmware (ver [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)).

| | |
|---|---|
| SoC | Qualcomm SM6225 `bengal`, Adreno 610 |
| Pantalla | AMOLED 1080×2400, 90 Hz |
| Arranque | A/B con Virtual A/B, boot header v3 + `vendor_boot`; **recovery dentro de `boot`** (sin partición recovery) |
| Cifrado | FBE v2 + metadata, wrapped keys; Keymaster 4.1 / Gatekeeper 1.0 QTI |
| Kernel | 4.19.325-cip132-st16-Cherry (prebuilt de EvolutionX) |
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
