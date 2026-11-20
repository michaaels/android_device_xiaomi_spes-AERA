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
- Que `fastboot boot` funcione en este bootloader está **[PEND]**. OrangeFox lo documenta para spes, pero aquí no se ha probado.

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

La opción recomendada es la función de AERA que instala el recovery en la ramdisk del `boot` actual (repack), porque conserva el kernel instalado. La alternativa es `fastboot flash boot_<slot> boot.img`, y solo con una imagen hecha con el kernel stock de **ese mismo** firmware.

## 5. Restauración

| Situación | Acción |
|---|---|
| Android no arranca tras instalar | `fastboot flash boot_<slot> backup_spes/boot_<slot>.img` |
| `vendor_boot` o `dtbo` alterados | restaurarlos desde la copia del paso 3 |
| Fallo general | `flash_all_except_storage.sh` del paquete fastboot oficial (conserva los datos) |
| Último recurso | `flash_all.sh` (**borra los datos**) |

## Operaciones prohibidas sin autorización expresa

`fastboot flash`, `fastboot erase`, `format data`, wipes, cambiar de slot (`fastboot set_active`), modificar `super` o `vbmeta` (por ejemplo `--disable-verity`) y bloquear o desbloquear el bootloader.
