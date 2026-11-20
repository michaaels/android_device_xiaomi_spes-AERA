#!/bin/bash
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build-time environment for spes / spesn. Select it with
#   export AERA_BUILD_DEVICE=spes   (or source build/envsetup.sh after cd'ing here)

FDEVICE="spes"

aera_get_target_device() {
	local script_path
	script_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
	case "$script_path" in
		*/"$FDEVICE") AERA_BUILD_DEVICE="$FDEVICE" ;;
	esac
}

if [ -z "$AERA_BUILD_DEVICE" ]; then
	aera_get_target_device
fi

if [ "$1" = "$FDEVICE" ] || [ "$AERA_BUILD_DEVICE" = "$FDEVICE" ]; then
	export LC_ALL="C"
	export AERA_AB_DEVICE=1
	export AERA_VIRTUAL_AB_DEVICE=1
	export AERA_VANILLA_BUILD=1
	export AERA_PRODUCT_PREFIX=AERA
	export AERA_BUILD_STATUS=Unofficial
	export AERA_BUILD_TYPE=Beta
	export AERA_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
	export AERA_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"

	# Archive tools needed for backups/restores. The optional GNU bash, tar,
	# sed, grep and nano are not added: the bootloader limits the ramdisk
	# size (see BoardConfig.mk); toybox/mksh provide the basic versions.
	export AERA_USE_LZ4_BINARY=1
	export AERA_USE_ZSTD_BINARY=1
	export AERA_USE_XZ_UTILS=1
	# vendor/twrp always packages GNU bash; drop it (mksh stays as /system/bin/sh)
	export AERA_REMOVE_BASH=1

	# Both variants share one image
	export TARGET_DEVICE_ALT="spesn"
	export AERA_TARGET_DEVICES="spes,spesn"

	unset AERA_VARIANT
	unset AERA_MAINTAINER_PATCH_VERSION
fi
