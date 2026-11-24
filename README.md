# AERA Recovery Project device tree for Xiaomi Redmi Note 11

Device codename: `spes`

The image also detects the Redmi Note 11 NFC (`spesn`), which shares the
board, from `ro.boot.product.hardware.sku`, but that variant is untested and
not claimed as supported.

Platform: Qualcomm SM6225 (`bengal`, Snapdragon 680), Adreno 610
Boot layout: A/B with Virtual A/B, boot header v3 + `vendor_boot`, recovery
inside `boot` (no recovery partition)

Maintainer: Michael Xavier. Status: **beta, unofficial**: tested on one
`spes` (2201117TG).

## Hardware support

Verified on hardware (details and evidence in [docs/TESTING.md](docs/TESTING.md)):

- Display (AMOLED 1080x2400, 90 Hz), touch, buttons, landscape rotation
- File-based encryption (FBE v2 + metadata, wrapped keys): PIN, pattern and no
  lock; Keymaster 4.1 / Gatekeeper 1.0 QTI
- Backup and restore, ADB, ADB sideload, MTP, fastbootd, USB OTG
- Wi-Fi (WLAN firmware on the modem DSP, brought up on demand)
- Mobile data (internet only, 4G): dual SIM, SIM switching and auto-connect on
  boot ([docs/MOBILE_DATA.md](docs/MOBILE_DATA.md))
- Haptics (PMIC LED-class vibrator) and flashlight
- PC Connection, plugin store and AERA Browser (Zink on Adreno 610)
- Permanent installation into `boot` with the installed kernel kept

Not available: Root Manager (non-GKI 4.19 kernel). Untested: SIM PIN entry.

## Build

```sh
repo init -u https://github.com/AERA-Recovery/android_manifest.git -b aera-16.0 --depth=1
repo sync -c --no-clone-bundle --no-tags -j$(nproc)
git clone <this repository> -b aera-16.0 device/xiaomi/spes
export AERA_BUILD_DEVICE=spes
source build/envsetup.sh
lunch twrp_spes-bp2a-eng
mka adbd bootimage
```

The output is `out/target/product/spes/boot.img` (also copied as
`AERA-R1.0-*-spes.img`). The target is `bootimage`, not `recoveryimage`,
because the recovery ramdisk lives in `boot`. Full notes, including the
ramdisk size limit of the spes bootloader, are in [docs/BUILD.md](docs/BUILD.md).

The generic fixes this tree was tested with are kept as patches for
`bootable/recovery` in `patches/bootable_recovery/` (applied with
`tools/apply-aera-patches.sh`). They are proposed upstream and are not needed
to build ([docs/UPSTREAM.md](docs/UPSTREAM.md)).

## Install

Test first without writing anything:

```sh
fastboot boot boot.img
```

Do not flash the built `boot.img` as is: its header declares the far-future
patch level that recovery decryption needs, and Android must not boot with
it. To install, keep the kernel and header of the installed `boot` and replace
only the ramdisk, after backing up the partitions listed in
[docs/RECOVERY_PLAN.md](docs/RECOVERY_PLAN.md), which also describes how to
restore them.

## Prebuilt kernel and proprietary files

The kernel (`prebuilt/kernel`, 4.19.325, provenance in `prebuilt/kernel.info`)
and the vendor files under `recovery/root/vendor` were extracted from the
EvolutionX 16.0 11.10 build for spes (`tools/extract-stock-kernel.sh`,
`tools/extract-files.sh`, checksums in `tools/blobs.sha256`). Use the image
with matching firmware; do not reuse these files on another device.

## Documentation

Detailed notes are in Spanish under [docs/](docs): hardware facts, OrangeFox
to AERA compatibility, build, test matrix, known issues, backup and recovery
plan, mobile data internals and upstream status.

## Credits

Board values from the OrangeFox spes tree and LineageOS. Conventions from the
official AERA trees; the mobile data provider is derived from the official
`infiniti` tree. See [docs/UPSTREAM.md](docs/UPSTREAM.md).
