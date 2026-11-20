#!/bin/bash
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# Extracts the kernel from the STOCK boot.img of the firmware installed on the
# device and installs it as prebuilt/kernel. Also records the header so the
# BoardConfig values can be checked against it.
#
#   tools/extract-stock-kernel.sh <stock boot.img> [<AOSP source root>]
#
# The boot.img must come from the exact firmware running on the phone (from
# the official fastboot/recovery ROM package of that version, or read back
# from the device). Never use another device's boot image.
set -euo pipefail

TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${1:?usage: $0 <stock boot.img> [aosp root]}"
AOSP="${2:-$(cd "$TREE/../../.." 2>/dev/null && pwd)}"
UNPACK="$AOSP/system/tools/mkbootimg/unpack_bootimg.py"
[ -f "$UNPACK" ] || { echo "unpack_bootimg.py not found under $AOSP" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
python3 "$UNPACK" --boot_img "$IMG" --out "$WORK" > "$WORK/info.txt"
cat "$WORK/info.txt"

hv="$(awk -F': ' '/boot image header version/ {print $2}' "$WORK/info.txt")"
[ "$hv" = "3" ] || { echo "ERROR: header version '$hv', spes expects 3" >&2; exit 1; }
[ -s "$WORK/kernel" ] || { echo "ERROR: no kernel in image" >&2; exit 1; }

mkdir -p "$TREE/prebuilt"
cp "$WORK/kernel" "$TREE/prebuilt/kernel"
{
    echo "source_image_sha256=$(sha256sum "$IMG" | cut -d' ' -f1)"
    echo "kernel_sha256=$(sha256sum "$TREE/prebuilt/kernel" | cut -d' ' -f1)"
    echo "kernel_format=$(file -b "$TREE/prebuilt/kernel")"
    grep -aoE 'Linux version [^ ]+ [^)]+\)' "$WORK/kernel" 2>/dev/null | head -1 \
        || (gzip -dc "$WORK/kernel" 2>/dev/null | grep -aoE 'Linux version [^ ]+' | head -1) || true
    sed 's/^/header: /' "$WORK/info.txt"
} > "$TREE/prebuilt/kernel.info"
echo "installed prebuilt/kernel; details in prebuilt/kernel.info"
