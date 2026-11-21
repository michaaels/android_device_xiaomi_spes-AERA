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
	# AERA downloads plugins, updates and fonts with "busybox wget"
	export AERA_USE_BUSYBOX_BINARY=1

	# Same convention as the official AERA Xiaomi 15 tree (FBE + metadata
	# encryption): /data cannot be mounted before the decryption screen, so
	# settings that must apply before it (e.g. the UI language) live in /persist.
	export AERA_SETTINGS_ROOT_DIRECTORY=/persist
	export AERA_ALLOW_EARLY_SETTINGS_LOAD=1

	# Flashlight: the torch is TLMM GPIO85 (no LED class in the EvolutionX
	# kernel); spes-torch-setup.sh links /tmp/spes-torch/brightness to it.
	export AERA_FL_PATH1=/tmp/spes-torch

	# Both variants share one image
	export TARGET_DEVICE_ALT="spesn"
	export AERA_TARGET_DEVICES="spes,spesn"

	unset AERA_VARIANT
	unset AERA_MAINTAINER_PATCH_VERSION
fi
