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

El device tree no modifica AERA. Hay **diez parches genéricos** propuestos para `bootable/recovery`, que se guardan aparte (se aplican con `tools/apply-aera-patches.sh`):

- `patches/bootable_recovery/0001-partition-skip-fsync-on-ADB-backup-stream.diff`: en `TWPartition::Raw_Read_Write`, omite `fsync()` cuando el destino es una FIFO (el stream de `adb backup`), donde siempre falla con `EINVAL` y hacía que AERA diera por fallido un backup correcto. Las escrituras a ficheros y particiones, incluida la restauración por ADB, siguen sincronizándose. Probado en spes; candidato a PR upstream (no enviado).

- `patches/bootable_recovery/0002-catalog-fix-corrupted-Spanish-translations.diff`: en `aeraui/localization/catalog/catalog.json`, 6 cadenas `es-ES` tenían `?` en lugar de `ó`, `ú`, `ñ` o `í` (por ejemplo "A?adir red" o "Mostrar contrase?a"). Después hay que regenerar `catalog_generated.cpp` con `generate_catalog.py`, que lo hace `tools/apply-aera-patches.sh`; se comprobó que el generador reproduce exactamente el fichero de upstream a partir del JSON original. Detectado por el usuario en la pantalla de Wi-Fi.

- `patches/bootable_recovery/0003-catalog-complete-Spanish-translation.diff` (requiere `0002`): completa la traducción `es-ES` del catálogo. Solo toca entradas `es-ES` de `catalog.json`, sin reformatear (el JSON se reescribe con `indent=2`, que reproduce el fichero original byte a byte). Cobertura: de 2094 a 2747 de 2768 cadenas.
  - **653 cadenas añadidas** de las 674 que no tenían traducción.
  - **13 corregidas** que eran idénticas al inglés sin ser nombres propios: `Backup`, `Backups`, `Wipe`, `Slot`, `Slot %s`, `Flashed %s`, `Flashing %s`, `Flashing init_boot_%s`, `Fatal:`, `Update %s?`, `Recovery Update`, `Plugin Manager`, `Theme Engine`.
  - **14 reparadas** porque tenían los marcadores desplazados o saltos de línea de más (por ejemplo `%u downloads` → `"Descargas de%u "`, `Erased %s` → `" %sborrado"`).
  - **21 sin traducir a propósito**, porque se quedan en inglés: nombres de producto (`AERA Doom`, `AERA Gallery`, `AERA Recovery`, `AERA Streams`, `AERA Telegram`, `App Backup Vault`, `Doom`), términos técnicos y abreviaturas (`Swappiness`, `Firmware`, `Incremental`, `PAYLOAD`, `RAM`, `BAT`, `REC  `, `DNS 1`, `DNS 2`, `No`) y cadenas que solo son formato (`%.1f MB`, `%.1f MB / %.1f MB`, `%d %s`, `%s\n%d %s`). Sin entrada `es-ES` se usa el inglés, igual que en el resto de idiomas.
  - Criterios: español neutro y técnico, coherente con lo que ya había y con la variante mayoritaria del catálogo (tuteo en las instrucciones e infinitivo en botones y acciones). Terminología: *slot* → ranura, *flash* → flashear/flasheo, *snapshot* → instantánea, *readback* → relectura, *anti-rollback* → antirreversión (se conserva `ARB`), *plugin* → complemento, *computer* → computadora, *Enter* → Ingresa, *Swipe to* → Desliza para, *Slide to* → Deslizar para. Se dejan literales `payload`, `kernel`, `recovery`, `KMI`, `OTA`, `SHA-256`, rutas (`AERA/Extracted`, `/sdcard/AERA/Doom`), comandos y herramientas (`otaripper`, `xbl_config`, `init_boot`). Los créditos se traducen como funciones ("Fundación, desarrollo principal…") para no asignar género.
  - Validación: el JSON es válido; en cada cadena `es-ES` los marcadores printf/`{n}`, el número de saltos de línea y los espacios al inicio y al final coinciden con el inglés; no queda ningún `?` entre letras; `generate_catalog.py` regenera sin errores (2768 etiquetas); en `chinese_catalog_test.py` pasa la comprobación de que el catálogo generado está al día, y los 58 fallos de cobertura china son los mismos con y sin el parche (problema previo de upstream).

- `patches/bootable_recovery/0004-wifi-localize-status-and-test-result-Spanish-respaldo.diff` (requiere `0003`): textos de Wi-Fi que seguían en inglés en el teléfono, y "respaldo" en las etiquetas cortas. Toca `aeraui/scenes/wifi_scene.cpp` y `catalog.json`.
  - Código (`wifi_scene.cpp`, cambios genéricos):
    - `BusyTitle()` traduce el texto base antes de añadir los puntos animados. Antes, "Turning Wi-Fi on..." no coincidía con ninguna clave y salía en inglés.
    - Los estados en bruto del backend (`wlan_state`: `enabling`, `disabling`, `disconnecting`, `scanning`, `connecting`) se muestran como etiquetas del catálogo (`WifiStateTag()`).
    - Las líneas que devuelve el test de red de `wlan.cpp` ("Connected: …", "IP address: …", "Internet: Failed", "Router or upstream network may be down.") se traducen al mostrarlas (`TranslateTestResult()`): se traduce la etiqueta y el estado `OK`/`Failed`, y se dejan tal cual el SSID y la IP. `wlan.cpp` no se modifica, porque esos valores se comparan literalmente en `aera_backend.cpp`.
  - Catálogo: **9 claves nuevas** (`Enabling`, `Disabling`, `Scanning`, `Internet`, `OK` y los 4 mensajes del test de `wlan.cpp`), con `en`, `es-ES`, `zh_CN` y `zh_TW` para no añadir fallos de cobertura china. Además, **38 cadenas `es-ES` cambiadas**:
    - "Scanning nearby" → "Buscando redes cercanas".
    - "respaldo" en 29 etiquetas cortas, títulos, botones y contadores (`Backup` → "Respaldo", `Backups` → "Respaldos", "Crear respaldo", "Restaurar respaldo", "Respaldando %s"…). La etiqueta "Copia de seguridad" no cabía en un botón.
    - 8 traducciones previas con el marcador pegado a una palabra (`'%zu partitions selected'` → `'Particiones%zu seleccionadas'`).
  - Criterio: "respaldo" en etiquetas sin punto final de hasta ~30 caracteres; las frases completas mantienen "copia de seguridad".
  - Validación: el código compila con `clang++ -fsyntax-only -Wall -Wextra` sin avisos nuevos; el JSON es válido; los marcadores, saltos de línea y espacios al inicio y al final coinciden con el inglés, y ya no queda ningún marcador pegado a una palabra; `generate_catalog.py` regenera sin errores (2777 etiquetas); `chinese_catalog_test.py` mantiene los mismos 58 fallos previos y pasa la comprobación de que el catálogo generado está al día; `0001`–`0004` se aplican en cadena sobre upstream limpio.

- `patches/bootable_recovery/0005-wifi-translate-remaining-state-labels.diff` (requiere `0004`): etiquetas de estado de Wi-Fi que seguían en inglés.

- `patches/bootable_recovery/0006-aeraui-rotate-scaled-software-frame-in-landscape.diff`: en `aeraui/core/engine.cpp`, la copia escalada del frame por software no aplicaba el giro en horizontal (LVGL entrega un frame de `height_` × `width_` y deja el cuarto de vuelta al volcado). Usa la misma transformación que `SetPointer()`. Corrige la rotación en spes.

- `patches/bootable_recovery/0007-catalog-mobile-data-strings-es-zh.diff`: 57 entradas de la pantalla y los mensajes de datos móviles en `en`, `es-ES`, `zh_CN` y `zh_TW`. `chinese_catalog_test.py` pasa de 58 a 54 fallos (los de upstream) sin añadir ninguno.

- `patches/bootable_recovery/0008-browser-enable-Zink-on-Adreno-without-hw-multiview.diff`: añade `TU_DEBUG=noconform` al entorno del motor de AERA Browser en `aeraui/features/browser/jail_main.cpp`.
  - Causa: en Mesa 26.2.2, Turnip declara Vulkan 1.1 solo si la GPU tiene multiview por hardware (`tu_is_vk_1_1()` → `tu_has_multiview()`), y `VK_KHR_maintenance5` depende de eso. La Adreno 610 (y la A702, perfil `a6xx_gen1_low` con `has_hw_multiview = False`) queda en Vulkan 1.0 sin `maintenance5`, y Zink, que lo exige, rechaza el dispositivo en silencio: "egl: failed to create dri2 screen", "EGL_NOT_INITIALIZED" y el motor WebKit aborta ("La sesión persistente WebKit se cerró inesperadamente").
  - Efecto: en Turnip, `TU_DEBUG_NOCONFORM` solo se usa en `tu_has_multiview()`. En esas GPU expone multiview (no conforme con el CTS) y con ello Vulkan 1.1 y `maintenance5`; en las demás GPU no cambia nada, porque ya tienen multiview por hardware.
  - Medido en spes con una sonda Vulkan dentro del runtime del plugin: sin la variable, "Adreno (TM) 610 api 1.0.354", sin `VK_KHR_multiview` ni `VK_KHR_maintenance5`; con ella, "api 1.3.354" con las dos extensiones, y `vkCreateDevice` correcto en ambos casos. Con el jail parcheado en RAM, AERA Browser carga google.com (algo lento).
  - Alternativa sin tocar `bootable/recovery`: el mismo cambio dentro del runtime firmado del plugin (parche de Mesa para A610/A702, como los de A722/A825 de `AERA-Plugins/browser`). Se propone en el jail porque es una línea, no exige recompilar Mesa y es inocua en el resto de GPU. Ninguna de las dos opciones se ha enviado.

- `patches/bootable_recovery/0009-browser-send-Enter-from-the-keyboard-action-key.diff`: en `aeraui/features/browser/web_scene.cpp`, la tecla de acción (✓) del teclado de una página solo cerraba el teclado, así que no se podía enviar una búsqueda de Google ni un formulario con Enter. LVGL notifica esa tecla solo como `LV_EVENT_READY`, antes de la rama `VALUE_CHANGED` que inyecta las teclas, y `HideKeyboard()` borra `web_keyboard`; ahora la rama `READY` envía Enter (13) a la página y después cierra el teclado. Probado en spes (build 35).

- `patches/bootable_recovery/0010-mobile-data-show-the-private-IPv4-address.diff`: en `aeraui/scenes/mobile_data_scene.cpp`, el detalle de conexión de datos móviles añade la fila "IPv4 privada" (el `address` que el proveedor ya publica en `status.json`) debajo de "IPv4 pública". El operador suele compartir la IP pública tras su NAT (con las dos SIM de Claro salía la misma), así que solo la privada distingue por qué SIM salen los datos. Catálogo: 1 clave nueva (`Private IPv4`) en `en`, `es-ES`, `zh_CN` y `zh_TW`; `chinese_catalog_test.py` mantiene los 54 fallos previos. Verificado en hardware (build 41). La demo web de AERA ("Interactive demo · sample data") ya muestra más filas en esa tarjeta (operador, red, SIM de datos, conexión por defecto), pero ese código **no está publicado**: el 2026-11-23, `bootable/recovery` local (`1cabc50`, 2026-11-15) era la cabeza de `aera-16.0` y no contiene esas cadenas. Si se publican, hay que rehacer el parche sobre esa versión antes de proponerlo.

Propuesta sin parche (no se puede probar aquí): **descargas `blob:` en AERA Browser**. El botón "Download" de un archivo en GitHub, y en general cualquier `<a download href="blob:…">`, no descarga nada, porque el `decide-policy` de `aeraui/features/browser/worker.cpp` (idéntico a `aera_worker.cpp`) ignora toda navegación cuya URL no pase `Address()`, que solo acepta `http(s)://`. Las descargas `https://` sí funcionan (asset de Releases de GitHub, build 35). Cambio sugerido en la rama `NAVIGATION_ACTION`, antes del `ignore`:

```cpp
// Same-origin blob: URLs are how pages hand a generated file to the user
// (<a download href="blob:https://...">). Never render them; save them.
if (uri && g_str_has_prefix(uri, "blob:https://")) {
  webkit_policy_decision_download(d); return TRUE;
}
```

El worker va dentro de `prebuilt/runtime.xz` (se compila con `build-worker.sh` contra WPE 2.52.6), así que hay que reconstruir y volver a firmar el runtime para probarlo. No se ha comprobado qué nombre de archivo sugiere WebKit en ese caso: puede ser el atributo `download` o el UUID del blob.

No se ha tocado el Plugin SDK.

Propuesta para el proveedor de datos móviles oficial (`mobile_data/` de infiniti, del que deriva el de spes): **doble SIM**. El código vive en el device tree (`mobile_data/sim_session.hpp`, nuevo, y `ProvisionSims`/`SelectDataSubscription` en `daemon.cpp`), así que no hay parche de `bootable/recovery`. Sin el *stack* de radio de Android:
- el módem deja vacías las sesiones de aprovisionamiento que Android no activó (la SIM 2, o la SIM 1 si Android la dejó inactiva), y sin sesión primaria no se registra en ninguna red. Se rellenan con UIM 0x38 *Change Provisioning Session* (primaria → ranura 1, secundaria → ranura 2, con el AID de la aplicación SIM/USIM de UIM 0x2F);
- los datos siguen la DDS del módem y no la vinculación de WDS, así que con la SIM 2 elegida salían por la SIM 1. Se mueve con DSD 0x4E *Switch DDS* (TLV 0x01 = suscripción) y se espera a que DSD 0x4F *Get Current DDS* la confirme, porque el cambio es asíncrono. Los IDs se sacaron de `libril-qc-hal-qmi.so` (qcril, `DSDModemEndPointModule::qmiDDSSwitchRequest` y `DSDModemEndPoint::getCurrentDDSSync`).

Verificado en spes con dos SIM de Claro (build 40). Debería servir a cualquier árbol oficial con el mismo proveedor y doble SIM, pero solo se ha probado en el SM6225; `sim_session.hpp` no depende del dispositivo.

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
