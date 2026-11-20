# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# AERA product settings for Redmi Note 11 / 11 NFC (spes / spesn).
# Only AERA_* names are used; aera_config.mk translates them internally.

AERA_MAINTAINER := spes porting (unofficial)

# Screen: 1080x2400 panel, waterdrop notch at the top centre
AERA_SCREEN_H := 2400
AERA_STATUS_H := 100
AERA_STATUS_INDENT_LEFT := 48
AERA_STATUS_INDENT_RIGHT := 48
AERA_HIDE_NOTCH := 1
AERA_CLOCK_POS := 1
AERA_ALLOW_DISABLE_NAVBAR := 0

# Boot design: Virtual A/B, recovery-in-boot (no recovery partition).
# AERA_AB_DEVICE_WITH_RECOVERY_PARTITION is intentionally NOT set.
AERA_FORCE_PREBUILT_KERNEL := 1
AERA_NO_TREBLE_COMPATIBILITY_CHECK := 1
AERA_DYNAMIC_FULL_SIZE := 9126805504
AERA_QUICK_BACKUP_LIST := /boot;/data;
# The ramdisk is LZ4 (BOARD_RAMDISK_USE_LZ4 in BoardConfig.mk, which also
# sets AERA's internal LZ4 option); see BoardConfig.mk for the constraints.

# Data handling (stock userdata is f2fs)
AERA_FORCE_DATA_FORMAT_F2FS := 1
AERA_UNBIND_SDCARD_F2FS := 1
AERA_BIND_MOUNT_SDCARD_ON_FORMAT := 1
AERA_UNMOUNT_SDCARDS_BEFORE_REBOOT := 1

# Partition tooling
AERA_ENABLE_ALL_PARTITION_TOOLS := 1
AERA_ENABLE_LPTOOLS := 1
AERA_USE_DMCTL := 1
AERA_LOOP_DEVICE_ERRORS_TO_LOG := 1

# Wi-Fi (on demand; the device-side bring-up is in init.recovery.wifi.rc)
AERA_ENABLE_WLAN := 1
