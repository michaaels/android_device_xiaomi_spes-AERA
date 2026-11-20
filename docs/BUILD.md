# Compilación reproducible

## Requisitos verificados en este entorno

- Fuentes: manifest **público** `AERA-Recovery/android_manifest` (rama `aera-16.0`, base `android-16.0.0_r1`, con capas TeamWin, LineageOS y AERA). Todos los proyectos AERA son públicos y se descargan por HTTPS. No hay dependencias privadas.
- Sistema de ficheros: hace falta un Linux nativo (ext4/btrfs), que distinga mayúsculas y minúsculas y conserve los bits de ejecución. **NTFS no sirve**: `ntfs3` quita los permisos de ejecución (`fmask`), no distingue mayúsculas y `windows_names` rechaza algunos nombres. En la primera prueba, el checkout de `build/blueprint` y `external/kmod` falló por esto.
- Espacio: unos 140 GB para las fuentes con `--depth=1` y `out/`. La cifra exacta se apuntará tras el primer build.
- RAM: 30 GB en este equipo; con 16 GB o más es suficiente usando swap/zram.

## Entorno usado (Docker + imagen ext4)

En este equipo el único Linux nativo es `/`, con 38 GB libres. Por eso las fuentes van en una imagen ext4 que se monta por loop dentro de un contenedor:

```bash
# 1. Imagen ext4 (asignada escribiendo ceros con dd; fallocate falla en ntfs3)
dd if=/dev/zero of=/mnt/2E6421A46421702F/aera_source/aera_src.ext4 bs=64M count=2240 status=progress conv=fsync
mkfs.ext4 -L aera_src -m 0 /mnt/2E6421A46421702F/aera_source/aera_src.ext4

# 2. Contenedor (Ubuntu 24.04). --privileged solo se usa para el losetup de esa imagen
tools/docker/run.sh

# 3. Shell de build
docker exec -it -u builder -w /src aera-spes bash
```

El device tree (este repo) se monta en `/src/device/xiaomi/spes`.

## Sincronización

```bash
cd /src
repo init -u https://github.com/AERA-Recovery/android_manifest.git -b aera-16.0 --depth=1 --no-git-lfs
repo sync -c --force-sync --no-clone-bundle --no-tags --optimized-fetch -j16
```

## Prerrequisitos del device tree

1. **Kernel stock** (obligatorio; el build se detiene sin él):
   ```bash
   device/xiaomi/spes/tools/extract-stock-kernel.sh /ruta/boot.img /src
   ```
   El `boot.img` tiene que ser el del firmware instalado en el teléfono. En el dispositivo de pruebas es `boot.img` de EvolutionX 16.0 11.10 (SHA-256 `278a6333…`). El script comprueba que la cabecera sea v3 y guarda el SHA-256 en `prebuilt/kernel.info`.
2. **Blobs de cifrado y boot control**:
   ```bash
   device/xiaomi/spes/tools/extract-files.sh --adb            # desde el teléfono, con adb pull de /vendor (solo lectura)
   device/xiaomi/spes/tools/extract-files.sh --dump <vendor>  # desde un vendor stock ya extraído
   ```
   Los checksums quedan en `tools/blobs.sha256`.

## Compilación

```bash
cd /src
export AERA_BUILD_DEVICE=spes
source build/envsetup.sh
lunch twrp_spes-bp2a-eng
mka adbd bootimage
```

- Producto: `twrp_spes` (`AndroidProducts.mk` → `twrp_spes.mk`). La release `bp2a` es la que usan los árboles oficiales AERA en `aera-16.0`. Hay que confirmar que existe en `build/release` del árbol sincronizado.
- Objetivo: **`bootimage`**, no `recoveryimage`. spes no tiene partición recovery y el ramdisk del recovery va dentro de `boot.img` (`BOARD_USES_RECOVERY_AS_BOOT`).
- Artefacto: `out/target/product/spes/boot.img`. AERA puede renombrarlo o empaquetarlo además mediante `vendor/recovery/AERA_A16.sh`; se documentará tras el primer build.

## Verificación de artefactos

```bash
device/xiaomi/spes/tools/validate-tree.sh /src          # estructura, flags AERA, tamaño frente a la partición
python3 system/tools/mkbootimg/unpack_bootimg.py --boot_img out/target/product/spes/boot.img --out /tmp/aera_unpack
sha256sum out/target/product/spes/boot.img
```

Hay que comprobar:
- `boot image header version: 3`.
- Que el kernel desempaquetado tenga el mismo SHA-256 que `prebuilt/kernel`.
- Tamaño ≤ 134217728 bytes.
- Que el ramdisk contenga `/system/bin/recovery`, `init.recovery.qcom.rc`, `twrp.flags` y los blobs.

## Estado

| Paso | Estado |
|---|---|
| Manifest y acceso a las fuentes | Verificado (todo público) |
| `repo sync` | En curso (ver `docs/TESTING.md`) |
| Kernel y blobs | Listos (EvolutionX 11.10) |
| `lunch` / `bootimage` | **No ejecutado**: espera al fin de `repo sync` |
