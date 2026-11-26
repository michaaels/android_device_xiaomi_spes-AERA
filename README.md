# AERA Recovery Project device tree for Xiaomi Redmi Note 11

Device codename: `spes`

The image also detects the Redmi Note 11 NFC (`spesn`), which shares the
board, from `ro.boot.product.hardware.sku`, but that variant is untested and
not claimed as supported.

Platform: Qualcomm SM6225 (`bengal`, Snapdragon 680), Adreno 610
Boot layout: A/B with Virtual A/B, boot header v3 + `vendor_boot`, recovery
inside `boot` (no recovery partition)

Maintainer: Michael Xavier. Status: **beta, unofficial**: tested on one
`spes` (2201117TG) running EvolutionX 16.0 11.10.

## Hardware support

Verified on hardware:

- Display (AMOLED 1080x2400, 90 Hz), touch, buttons, landscape rotation
- File-based encryption (FBE v2 + metadata, wrapped keys): PIN, pattern and no
  lock; Keymaster 4.1 / Gatekeeper 1.0 QTI
- Backup and restore, ADB, ADB sideload, MTP, fastbootd, USB OTG
- Wi-Fi (WLAN firmware on the modem DSP, brought up on demand)
- Mobile data (internet only, 4G): dual SIM, SIM switching and auto-connect on
  boot
- Haptics (PMIC LED-class vibrator) and flashlight
- PC Connection, plugin store and AERA Browser
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
because the recovery ramdisk lives in `boot`.

The spes bootloader accepts `fastboot boot` but never starts the kernel when
the ramdisk is 42.4 MB or more (41.5 MB boots). The tree therefore uses
`AERA_USE_EXTREME_COMPRESSION` and drops the CJK fallback fonts; check the
size of `ramdisk-recovery.img` (keep it at or below 40 MB) after adding
anything to the ramdisk.

The published beta was built with generic `bootable/recovery` fixes that are
proposed upstream, one commit each, on
[michaaels/android_bootable_recovery `spes-fixes`](https://github.com/michaaels/android_bootable_recovery/commits/spes-fixes).
The tree builds without them.

## Install

Test first without writing anything:

```sh
fastboot boot boot.img
```

Do not flash the built `boot.img` as is: its header declares the far-future
patch level that recovery decryption needs, and Android must not boot with
it. To install, back up `boot` (and `persist`, `modemst1`, `modemst2`, `fsg`,
`fsc`), then keep the kernel and header of the installed `boot` and replace
only the ramdisk:

```sh
unpack_bootimg.py --boot_img stock_boot.img --out st
unpack_bootimg.py --boot_img boot.img --out ae
mkbootimg.py --header_version 3 --kernel st/kernel --ramdisk ae/ramdisk \
    --os_version <stock os version> --os_patch_level <stock patch level> \
    --cmdline "" --output aera_boot.img
fastboot boot aera_boot.img     # must boot Android normally
fastboot flash boot aera_boot.img
```

`adb reboot recovery` then enters AERA. To undo, flash the stock `boot`.

## Prebuilt kernel and proprietary files

The kernel (`prebuilt/kernel`, 4.19.325, provenance in `prebuilt/kernel.info`,
source: [Evolution-X-Devices/kernel_xiaomi_sm6225 `cfe9fb6`](https://github.com/Evolution-X-Devices/kernel_xiaomi_sm6225/commit/cfe9fb687febaf32b2e237518604edd9867a0cee))
and the vendor files under `recovery/root/vendor` were extracted from the
EvolutionX 16.0 11.10 build for spes (`tools/extract-stock-kernel.sh`,
`tools/extract-files.sh`, checksums in `tools/blobs.sha256`). Use the image
with matching firmware; do not reuse these files on another device.

## Credits

Board values from the OrangeFox spes tree (Jashkirat, fox-12.1) and LineageOS.
Conventions from the official AERA trees; the mobile data provider is derived
from the official `infiniti` tree (`f7fca594`), with dual SIM support added
(empty UIM provisioning sessions are filled and the modem's default data
subscription follows the selected SIM).
