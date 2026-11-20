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

	export AERA_USE_BASH_SHELL=1
	export AERA_USE_TAR_BINARY=1
	export AERA_USE_SED_BINARY=1
	export AERA_USE_LZ4_BINARY=1
	export AERA_USE_ZSTD_BINARY=1
	export AERA_USE_GREP_BINARY=1
	export AERA_USE_XZ_UTILS=1
	export AERA_USE_NANO_EDITOR=1

	# Both variants share one image
	export TARGET_DEVICE_ALT="spesn"
	export AERA_TARGET_DEVICES="spes,spesn"

	unset AERA_VARIANT
	unset AERA_MAINTAINER_PATCH_VERSION
fi
