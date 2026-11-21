#
# Copyright (C) 2021 The LineageOS Project
# Copyright (C) 2026 AERA Recovery Project contributors
#
# SPDX-License-Identifier: Apache-2.0
#
# Xiaomi Redmi Note 11 / Redmi Note 11 NFC (spes / spesn) - SM6225 "bengal".
# Board values cross-checked against the stock MIUI 14 V816.0.8.0.TGCMIXM
# vendor image and the OrangeFox fox-12.1 spes tree. See docs/HARDWARE.md for
# the evidence behind each value and which ones still need hardware checks.
#

DEVICE_PATH := device/xiaomi/spes

# The AERA manifest is a recovery-only subset of AOSP.
ALLOW_MISSING_DEPENDENCIES := true

# Build rules (same relaxations the standalone AERA trees use)
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_PLUGIN_VALIDATION := soong-libaosprecovery_defaults soong-libguitwrp_defaults soong-libminuitwrp_defaults soong-vold_defaults

# Architecture (Kryo 265 = 4x Cortex-A73 + 4x Cortex-A53). Recovery is 64-bit only.
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a73

# Platform / bootloader
PRODUCT_PLATFORM := bengal
TARGET_BOARD_PLATFORM := bengal
TARGET_BOOTLOADER_BOARD_NAME := bengal
TARGET_NO_BOOTLOADER := true
QCOM_BOARD_PLATFORMS += bengal

# ---------------------------------------------------------------------------
# Kernel / boot image
# spes uses boot image header v3 with a separate vendor_boot (which carries the
# DTB and vendor ramdisk). There is no recovery partition: the recovery ramdisk
# lives in boot.img (BOARD_USES_RECOVERY_AS_BOOT).
#
# The kernel MUST come from the boot.img of the firmware installed on the
# device (tools/extract-stock-kernel.sh). A kernel built from another source
# would not match the vendor modules / vendor_boot and could break Android boot
# once the image is installed. Current prebuilt: EvolutionX 16.0 11.10
# (Linux 4.19.325-cip132-st16-Cherry), see prebuilt/kernel.info.
# ---------------------------------------------------------------------------
BOARD_BOOT_HEADER_VERSION := 3
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_IMAGE_NAME := Image.gz
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)

# `fastboot boot` on spes passes androidboot.force_normal_boot=1, so first-stage
# init would try a normal Android boot (and fatally reboot to the bootloader)
# unless the image carries twrpfastboot=1. vendor/twrp only adds it to
# GENERIC_KERNEL_CMDLINE when a vendor_boot exists, and build/make writes that
# into boot.img only for BOARD_USES_GENERIC_KERNEL_IMAGE (GKI), which a 4.19
# kernel is not. Put it in the boot header explicitly. An image produced by
# AERA's repack of the installed boot keeps the stock (empty) cmdline.
BOARD_MKBOOTIMG_ARGS += --cmdline "twrpfastboot=1"

# Ramdisk constraints, both measured on hardware (docs/evidence/hw-abl-ramdisk-limit.txt):
# 1. LZ4 is mandatory: the bootloader concatenates the installed vendor_boot
#    ramdisk (LZ4 legacy) with this one, and the kernel's LZ4 legacy decoder
#    has no end marker, so a gzip boot ramdisk fails with "rootfs image is not
#    initramfs (Decoding failed)" and init never runs.
# 2. Size: the bootloader accepts `fastboot boot` but never starts the kernel
#    when the ramdisk is >= 42.4 MB; 41.5 MB boots with either kernel, so the
#    limit is on the ramdisk alone (consistent with 40 MiB). Keep it <= 40 MB;
#    tools/validate-tree.sh enforces this.
BOARD_RAMDISK_USE_LZ4 := true

ifeq ($(wildcard $(TARGET_PREBUILT_KERNEL)),)
  $(error spes: $(TARGET_PREBUILT_KERNEL) is missing. Extract it from the stock boot.img of the installed firmware with tools/extract-stock-kernel.sh (see docs/BUILD.md))
endif

# Recovery-in-boot (no dedicated recovery partition on spes)
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BOOTIMAGE_PARTITION_SIZE := 134217728

# ---------------------------------------------------------------------------
# A/B, Virtual A/B and dynamic partitions
# ---------------------------------------------------------------------------
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    vendor_boot \
    vbmeta \
    vbmeta_system \
    system \
    system_ext \
    product \
    vendor

BOARD_DTBOIMG_PARTITION_SIZE := 25165824
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_FLASH_BLOCK_SIZE := 262144

BOARD_SUPER_PARTITION_SIZE := 9126805504
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 9122611200
# From the EvolutionX payload manifest (MIUI additionally carries mi_ext)
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext product vendor

# File systems
BOARD_USES_METADATA_PARTITION := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
# Logical partitions are ext4 (first-stage fstab.qcom); never built here
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ROOT_EXTRA_FOLDERS := firmware persist

# Verified boot (bootloader must be unlocked to boot/flash a custom image)
BOARD_AVB_ENABLE := true

# Properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop

# ---------------------------------------------------------------------------
# Recovery
# ---------------------------------------------------------------------------
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
RECOVERY_SDCARD_ON_DATA := true
TARGET_RECOVERY_QCOM_RTC_FIX := true

# Crypto: FBE v2 + metadata encryption with wrapped keys (stock fstab), served
# by QTI Keymaster 4.1 + Gatekeeper 1.0 + qseecomd (stock VINTF manifest).
AERA_INCLUDE_CRYPTO := true
AERA_INCLUDE_CRYPTO_FBE := true
AERA_INCLUDE_FBE_METADATA_DECRYPT := true
AERA_USE_FSCRYPT_POLICY := 2
AERA_DEFAULT_KEYMASTER_VERSION := 4.1
AERA_FORCE_KEYMASTER_VER := true
BOARD_USES_QCOM_FBE_DECRYPTION := true
# Keymaster binds keys to the OS version / patch level it sees. Recovery
# reports a far-future value so stock keys are never treated as from a newer
# OS (standard TWRP practice; it does not weaken userdata encryption).
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)

# Display (1080x2400 AMOLED, 90 Hz)
AERA_THEME := portrait_hdpi
AERA_FRAMERATE := 90
# Render at the panel's own metrics (AERA_SCREEN_H/AERA_STATUS_H in
# aera_spes.mk, width defaults to 1080). Without it AERA uses a fixed
# 3168-high canvas scaled to 2400 lines: on hardware the decrypt screen's
# "Skip" control was covered by the keypad and the UI felt slow.
AERA_UI_ADAPTIVE_RESOLUTION := true
AERA_BRIGHTNESS_PATH := "/sys/class/backlight/panel0-backlight/brightness"
# Both spes panels in the installed dtbo (k7_38_0c_0a / k7_38_0c_0b) declare
# qcom,mdss-dsi-bl-max-level = qcom,mdss-brightness-max-level = 2047
AERA_MAX_BRIGHTNESS := 2047
AERA_DEFAULT_BRIGHTNESS := 1200
AERA_NO_SCREEN_BLANK := true
AERA_INPUT_BLACKLIST := "hbtp_vm"

# Haptics: the PMIC vibrator is exposed as an LED-class device
# (/sys/class/leds/vibrator: duration + activate), which minui drives directly
# without the AIDL vibrator HAL. Verified on hardware (2026-11-21).

# USB is configured by recovery/root/init.recovery.usb.rc
AERA_EXCLUDE_DEFAULT_USB_INIT := true

# Tools
AERA_INCLUDE_REPACKTOOLS := true
AERA_INCLUDE_RESETPROP := true
AERA_INCLUDE_LIBRESETPROP := true
AERA_INCLUDE_LPDUMP := true
AERA_INCLUDE_LPTOOLS := true
AERA_INCLUDE_NTFS_3G := true
AERA_INCLUDE_FASTBOOTD := true
AERA_USE_TOOLBOX := true
AERA_EXCLUDE_APEX := true
AERA_EXTRA_LANGUAGES := true
AERA_DEFAULT_LANGUAGE := en

# Ramdisk size: the spes bootloader does not start a ramdisk larger than
# ~41.5 MB (docs/evidence/hw-abl-ramdisk-limit.txt). Use AERA's own mechanism
# (also used by official trees with 4.19 kernels): XZ-pack the recovery runtime
# inside the ramdisk; early init unpacks it into RAM.
AERA_USE_EXTREME_COMPRESSION := 1
# The only files dropped are the CJK fallback fonts and the lpdump CLI with its
# 2.1 MB libprotobuf-cpp-full, which no AERA code uses
# (AERA_ENABLE_ALL_PARTITION_TOOLS forces it; lptools, lpmake, lpunpack,
# lpflash and bootctl remain). No trailing ';': bootable/recovery appends its
# own "; rm -f ..." entry to BOARD_RECOVERY_IMAGE_PREPARE.
SPES_DROPPED_FILES := twres/fonts/wqy-microhei.ttf twres/fonts/NotoSansCJKjp-Regular.ttf \
    system/bin/lpdump system/bin/lpdumpd system/etc/init/lpdumpd.rc \
    system/lib64/liblpdump.so system/lib64/liblpdump_interface-V1-cpp.so \
    system/lib64/liblpdump_interface-cpp.so system/lib64/libprotobuf-cpp-full.so
BOARD_RECOVERY_IMAGE_PREPARE += rm -f $(addprefix $(TARGET_RECOVERY_ROOT_OUT)/,$(SPES_DROPPED_FILES))

# Debug
TARGET_USES_LOGD := true
AERA_INCLUDE_LOGCAT := true
