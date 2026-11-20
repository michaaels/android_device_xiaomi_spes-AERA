#!/bin/bash
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# Packs selected large recovery executables with UPX (LZMA) so the ramdisk
# fits the spes bootloader limit (docs/evidence/hw-abl-ramdisk-limit.txt)
# without dropping AERA features. Called from BOARD_RECOVERY_IMAGE_PREPARE:
#   compress-ramdisk-bins.sh <recovery root> <upx binary>
#
# Only binaries on the explicit list below are touched. Never add init,
# linker64, toybox, sh or vendor blobs: they must stay byte-identical.
set -u

ROOT="${1:?recovery root}"
UPX="${2:?upx binary}"
MIN=131072

LIST="
system/bin/recovery
system/bin/wpa_supplicant
system/bin/update_engine_sideload
system/bin/keystore2
system/bin/7za
system/bin/fastbootd
system/bin/adbd
system/bin/minadbd
system/bin/ttyd
system/bin/aera-netfs
system/bin/aera-otaripper
system/bin/aera-browser-jail
system/bin/aera-audio-null-bridge
system/bin/fsck.f2fs
system/bin/sload_f2fs
system/bin/make_f2fs
system/bin/e2fsck
system/bin/exfat-fuse
system/bin/sgdisk
system/bin/avbctl
system/bin/lzma
system/bin/logcat
system/bin/wpa_cli
system/bin/toolbox
system/bin/awk
system/bin/nano
system/bin/htop
system/bin/lpdump
system/bin/lpdumpd
sbin/bash
sbin/gnutar
sbin/gnused
"

[ -x "$UPX" ] || { echo "compress-ramdisk-bins: $UPX not found" >&2; exit 1; }

packed=0; skipped=0
for rel in $LIST; do
    f="$ROOT/$rel"
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    [ "$(stat -c %s "$f")" -gt "$MIN" ] || { skipped=$((skipped+1)); continue; }
    # ELF64 little-endian for AArch64 (e_machine 0xb7). `file` is not on the
    # AOSP build PATH, so read the header directly.
    [ "$(od -An -tx1 -N5 "$f" | tr -d ' \n')" = "7f454c4602" ] || continue
    [ "$(od -An -tx1 -j18 -N2 "$f" | tr -d ' \n')" = "b700" ] || continue
    if head -c 4096 "$f" | grep -q "UPX!"; then continue; fi
    chmod u+w,a+x "$f"
    if "$UPX" -q --lzma "$f" >/dev/null 2>&1; then
        if "$UPX" -q -t "$f" >/dev/null 2>&1; then
            packed=$((packed+1))
        else
            echo "compress-ramdisk-bins: upx self-test failed for $rel" >&2
            exit 1
        fi
    else
        echo "compress-ramdisk-bins: upx refused $rel (left unpacked)"
    fi
done
echo "compress-ramdisk-bins: packed $packed binaries ($skipped below ${MIN} B)"
