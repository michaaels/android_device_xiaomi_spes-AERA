# AERA Recovery: Xiaomi Redmi Note 11 / 11 NFC (`spes` / `spesn`)

Device tree de [AERA Recovery](https://github.com/AERA-Recovery) (`aera-16.0`) para el Redmi Note 11 (SM6225 / Snapdragon 680).

> **Estado: EXPERIMENTAL. Compila, arranca y funciona en un spes real con `fastboot boot`** (nunca se ha instalado de forma permanente).
>
> - **Verificado:** interfaz, táctil, botones, rotación horizontal, ADB, MTP, sideload, fastbootd, detección de particiones, **descifrado FBE con PIN**, backup por ADB y vuelta a Android. También linterna, vibración (motor y respuesta háptica), OTG, **Wi-Fi**, **datos móviles 4G con doble SIM**, PC Connection (Wi-Fi y USB), tienda de plugins y **AERA Browser**.
> - **Pendiente:** restore, descifrado sin bloqueo o con patrón, SIM con PIN, conexión automática de datos, spesn e instalación permanente.
> - **No disponible:** Root Manager (kernel 4.19 no GKI) y descargas `blob:` en AERA Browser (upstream).
>
> Detalle y evidencias en [docs/TESTING.md](docs/TESTING.md). Hay diez parches genéricos para `bootable/recovery` (`patches/bootable_recovery/`), propuestos para upstream y aún no enviados ([docs/UPSTREAM.md](docs/UPSTREAM.md)).
> Última imagen probada: `build41-private-ip`, SHA-256 `18817b760f53f118fc50bf40b163851054eebf46762f6800304b6dfce764bc67` (build incremental; falta la build limpia final).
>
> ⚠️ Solo para `fastboot boot`. No lo flashees como `boot` (ver [docs/RECOVERY_PLAN.md](docs/RECOVERY_PLAN.md)).
> Kernel y blobs ya incluidos, de **EvolutionX 16.0 11.10**, el firmware de referencia instalado. La imagen solo debe usarse con ese firmware (ver [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)).

| | |
|---|---|
| SoC | Qualcomm SM6225 `bengal`, Adreno 610 |
| Red | Wi-Fi y módem en el MPSS (icnss, QMI sobre QRTR, IPA/`rmnet_ipa0`); arranque bajo demanda con EFS y `persist` en RAM |
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
- [MOBILE_DATA](docs/MOBILE_DATA.md): cómo funcionan los datos móviles (y qué sirve para postmarketOS).
- [UPSTREAM](docs/UPSTREAM.md): origen del código, parches genéricos y contribución.

## Créditos

Valores de placa del árbol OrangeFox spes (Jashkirat, fox-12.1) y de LineageOS. Convenciones de los árboles oficiales AERA (dada, garnet); el proveedor de datos móviles viene del árbol oficial infiniti. Lo demás está detallado en [docs/UPSTREAM.md](docs/UPSTREAM.md).
