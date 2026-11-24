# Plan de seguridad, copia de seguridad y restauración

> Ninguna operación de este documento se ejecuta de forma automática. Cada paso que escribe en el teléfono necesita la autorización explícita del propietario.

## Requisitos previos

- Bootloader desbloqueado (lo hace el propietario con Mi Unlock; aquí no se automatiza).
- Batería por encima del 50 % y cable USB de datos fiable.
- **Paquete fastboot oficial** de la versión exacta instalada (`spes_global_images_V…`), guardado en el PC y con el checksum comprobado. Es la vía de restauración principal.
- `adb` y `fastboot` actualizados en el PC (`fastboot --version`).

## 1. Recogida de datos (solo lectura)

Ejecutar los comandos de `HARDWARE.md` → «Comandos de solo lectura» y guardar la salida en `docs/evidence/`.

## 2. Primera prueba: solo arranque temporal

```bash
adb reboot bootloader
fastboot getvar current-slot
fastboot getvar unlocked
fastboot boot out/target/product/spes/boot.img
```

- `fastboot boot` **no escribe en ninguna partición**: la imagen se carga en RAM junto con el `vendor_boot` instalado.
- Para volver basta con reiniciar (`adb reboot` o mantener pulsado power): se arranca el `boot` original.
- Si se queda en bucle o con la pantalla negra: mantener power + vol- unos 10 s para entrar en fastboot y reiniciar desde ahí. Nada ha cambiado en el almacenamiento.
- `fastboot boot` funciona en este bootloader: es el método de todas las pruebas (builds 11 a 35), siempre que la ramdisk quepa en el límite del ABL (ver `KNOWN_ISSUES.md`).

## 3. Copias de seguridad desde AERA (antes de cualquier instalación)

Una vez arrancado temporalmente y con ADB funcionando:

```bash
mkdir -p backup_spes && cd backup_spes
SLOT=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')
for p in boot$SLOT vendor_boot$SLOT dtbo$SLOT vbmeta$SLOT vbmeta_system$SLOT persist modemst1 modemst2 fsg fsc; do
  adb shell "dd if=/dev/block/by-name/$p of=/tmp/$p.img" && adb pull /tmp/$p.img && adb shell rm /tmp/$p.img
done
sha256sum *.img > SHA256SUMS
```

`persist` y `modemst*/fsg/fsc` contienen calibración e IMEI y **no se pueden regenerar**. Guárdalos fuera del PC.

## 4. Instalación permanente (solo cuando todo lo de TESTING.md esté en PASS)

> Estado (2026-11-23): **probada en el teléfono de pruebas**, con autorización del propietario y las copias del paso 3 verificadas.

Método usado (equivalente al de AERA y verificable antes de escribir): montar en el PC un `boot` con el kernel y la cabecera del `boot` instalado y la ramdisk de AERA.

```bash
# boot_<slot>.img es la copia del paso 3; boot.img es la build de AERA
python3 system/tools/mkbootimg/unpack_bootimg.py --boot_img boot_<slot>.img --out st
python3 system/tools/mkbootimg/unpack_bootimg.py --boot_img boot.img --out ae
python3 system/tools/mkbootimg/mkbootimg.py --header_version 3 --kernel st/kernel --ramdisk ae/ramdisk \
    --os_version <os version de st> --os_patch_level <os patch level de st> --cmdline "" --output aera_boot.img
python3 system/tools/mkbootimg/unpack_bootimg.py --boot_img aera_boot.img --out chk   # comprobar campos y SHA-256 del kernel
fastboot boot aera_boot.img        # el ABL lo arranca como Android normal: si Android llega a boot_completed, la ramdisk vale
fastboot flash boot_<slot> aera_boot.img
```

Después: `adb reboot recovery` entra en AERA, y "Reiniciar → Sistema" vuelve a Android. Sigue sin probar la función de AERA que instala su ramdisk desde el propio recovery.

> ⚠️ **Nunca** hagas `fastboot flash boot` del `boot.img` de AERA para arrancar Android con él. Su cabecera declara el nivel de parche 2099-12, y el Keymaster de Android podría actualizar las claves de forma irreversible (ver KNOWN_ISSUES).

Alternativa para el usuario final: la función de AERA que instala el recovery en la ramdisk del `boot` actual (repack). También conserva el kernel y la cabecera del firmware instalado. Sin probar: antes de recomendarla hay que comprobar, sobre una copia y desde el PC, que el `boot` resultante mantiene `os_version` y `os_patch_level` originales (`unpack_bootimg.py`).

## 5. Restauración

| Situación | Acción |
|---|---|
| Android no arranca tras instalar | `fastboot flash boot_<slot> backup_spes/boot_<slot>.img` |
| Con EvolutionX 11.10 y sin copia propia | `boot.img` / `vendor_boot.img` originales del paquete descargado (SHA-256 `278a6333…` / `48569e32…`, ver `docs/evidence/`) con `fastboot flash boot_<slot>` / `vendor_boot_<slot>` |
| `vendor_boot` o `dtbo` alterados | restaurarlos desde la copia del paso 3 |
| Fallo general | `flash_all_except_storage.sh` del paquete fastboot oficial (conserva los datos) |
| Último recurso | `flash_all.sh` (**borra los datos**) |

## Operaciones prohibidas sin autorización expresa

`fastboot flash`, `fastboot erase`, `format data`, wipes, cambiar de slot (`fastboot set_active`), modificar `super` o `vbmeta` (por ejemplo `--disable-verity`) y bloquear o desbloquear el bootloader.
