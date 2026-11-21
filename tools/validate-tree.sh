#!/bin/bash
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# Static checks for the spes AERA device tree.
#   tools/validate-tree.sh [<AOSP/AERA source root>]
# With a source root it also checks every AERA_* flag against
# bootable/recovery/aera_config.mk and, if a build exists, the boot image.
set -uo pipefail

TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-}"
fail=0; warn=0
ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=$((fail+1)); }
note() { printf 'WARN  %s\n' "$*"; warn=$((warn+1)); }

cd "$TREE"

# 1. Required files
for f in Android.bp Android.mk AndroidProducts.mk BoardConfig.mk device.mk \
         aera_spes.mk twrp_spes.mk vendorsetup.sh system.prop recovery.fstab \
         proprietary-files.txt recovery/root/init.recovery.qcom.rc \
         recovery/root/init.recovery.usb.rc recovery/root/system/etc/twrp.flags \
         recovery/root/system/bin/variant-script.sh; do
    [ -f "$f" ] && ok "exists $f" || bad "missing $f"
done

# 2. Product wiring
grep -q 'twrp_spes.mk' AndroidProducts.mk && ok "AndroidProducts -> twrp_spes.mk" || bad "AndroidProducts.mk does not list twrp_spes.mk"
grep -q '^PRODUCT_NAME := twrp_spes' twrp_spes.mk && ok "PRODUCT_NAME twrp_spes" || bad "PRODUCT_NAME mismatch"
grep -q '^PRODUCT_DEVICE := spes' twrp_spes.mk && ok "PRODUCT_DEVICE spes" || bad "PRODUCT_DEVICE mismatch"
grep -q '^DEVICE_PATH := device/xiaomi/spes' BoardConfig.mk && ok "DEVICE_PATH" || bad "DEVICE_PATH"

# 3. Shell syntax
for s in vendorsetup.sh recovery/root/system/bin/*.sh tools/*.sh tools/docker/*.sh; do
    bash -n "$s" 2>/dev/null && ok "sh -n $s" || bad "syntax error in $s"
done

# 4. Make syntax (parse only, no AOSP needed): unbalanced ifeq/endif
for m in BoardConfig.mk device.mk aera_spes.mk twrp_spes.mk Android.mk AndroidProducts.mk; do
    o=$(grep -cE '^\s*if(eq|neq|def|ndef)\b' "$m"); c=$(grep -cE '^\s*endif\b' "$m")
    [ "$o" = "$c" ] && ok "conditionals balanced $m" || bad "$m: $o if* vs $c endif"
done

# 5. fstab: 5 columns, known types, no duplicate mount points
awk '!/^#/ && NF { if (NF != 5) { print "FAIL  recovery.fstab line " NR ": " NF " fields"; e=1 } m[$2]++ }
     END { for (k in m) if (m[k] > 1) { print "FAIL  duplicate mount point " k; e=1 } exit e }' recovery.fstab \
    && ok "recovery.fstab structure" || fail=$((fail+1))
grep -q 'fileencryption=aes-256-xts:aes-256-cts:v2' recovery.fstab && ok "FBE v2 policy on /data" || bad "/data FBE policy missing"
grep -q 'metadata_encryption=' recovery.fstab && ok "metadata encryption on /data" || bad "/data metadata encryption missing"
awk '!/^#/ && NF { m[$1]++ } END { for (k in m) if (m[k] > 1) { print "FAIL  twrp.flags duplicate " k; e=1 } exit e }' \
    recovery/root/system/etc/twrp.flags && ok "twrp.flags unique mount points" || fail=$((fail+1))

# 6. rc services point at files that exist in the tree or are provided by the build
build_provided="android.hardware.boot@1.1-service android.hardware.boot@1.2-service android.hardware.health@2.1-service sh"
while read -r _ name path _; do
    b="$(basename "$path")"
    if [[ "$path" == /mnt/vendor_stock/* ]]; then ok "service $name -> $path (installed vendor, mounted read-only at runtime)"
    elif [ -f "recovery/root$path" ] || [[ " $build_provided " == *" $b "* ]]; then ok "service $name -> $path"
    else bad "service $name: $path not in recovery/root and not build-provided"; fi
done < <(grep -hE '^service ' recovery/root/*.rc)

# 7. Blobs listed vs present
total=0; present=0
while IFS= read -r l; do
    l="${l%%#*}"; l="$(echo "$l" | xargs)"; [ -z "$l" ] && continue
    total=$((total+1)); d="${l#*:}"; [ -f "recovery/root/$d" ] && present=$((present+1))
done < proprietary-files.txt
[ "$present" = "$total" ] && ok "blobs present $present/$total" || note "blobs present $present/$total (run tools/extract-files.sh)"

# 8. Kernel
if [ -f prebuilt/kernel ]; then ok "prebuilt/kernel present ($(file -b prebuilt/kernel | cut -c1-60))"
else note "prebuilt/kernel missing (BoardConfig.mk stops the build until it is provided)"; fi

# 9. No foreign-device leftovers
if grep -rqiwE 'garnet|dada|infiniti|peridot|sm8750|parrot|adrastea' --exclude-dir=docs --exclude-dir=patches --exclude-dir=.git --exclude=validate-tree.sh --exclude=README.md .; then
    bad "references to other devices found"; grep -rniwE 'garnet|dada|infiniti|peridot|sm8750|parrot|adrastea' --exclude-dir=docs --exclude-dir=patches --exclude-dir=.git --exclude=validate-tree.sh --exclude=README.md . | head
else ok "no references to other devices"; fi

# 10. Licence headers on tree sources
for f in BoardConfig.mk device.mk aera_spes.mk twrp_spes.mk AndroidProducts.mk Android.mk Android.bp vendorsetup.sh recovery/root/*.rc recovery/root/system/bin/*.sh tools/*.sh; do
    grep -qE 'SPDX-License-Identifier|Redistribution and use' "$f" && ok "licence header $f" || bad "no licence header in $f"
done

# 11. AERA flags exist upstream
if [ -n "$SRC" ] && [ -f "$SRC/bootable/recovery/aera_config.mk" ]; then
    cfg="$SRC/bootable/recovery/aera_config.mk"; bld="$SRC/bootable/recovery/aera_build.mk"
    for v in $(grep -hoE '^\s*(export\s+)?AERA_[A-Z0-9_]+' BoardConfig.mk aera_spes.mk vendorsetup.sh | sed -E 's/^\s*(export\s+)?//' | sort -u); do
        short="${v#AERA_}"
        if grep -qwE "$short|$v" "$cfg" "$bld" 2>/dev/null || grep -rqw "$v" "$SRC/vendor/twrp" "$SRC/vendor/recovery" "$SRC/bootable/recovery" --include=*.mk --include=*.sh --include=*.go 2>/dev/null; then
            ok "flag $v known upstream"
        else
            bad "flag $v not found in AERA sources"
        fi
    done
    # 12. Built image vs partition size
    img="${AERA_BOOT_IMG:-$SRC/${OUT_DIR_NAME:-out}/target/product/spes/boot.img}"
    if [ -f "$img" ]; then
        sz=$(stat -c %s "$img"); lim=$(awk -F':= ' '/^BOARD_BOOTIMAGE_PARTITION_SIZE/ {print $2}' BoardConfig.mk)
        [ "$sz" -le "$lim" ] && ok "boot.img $sz <= $lim bytes" || bad "boot.img $sz exceeds partition $lim"
        # 13. Bootloader ramdisk limit measured on hardware: >= 42.4 MB never
        # starts the kernel, 41.5 MB boots (any kernel). Require <= 41.5 MB (proven).
        ud="$(mktemp -d)"
        rd=$(python3 -I "$SRC/system/tools/mkbootimg/unpack_bootimg.py" --boot_img "$img" --out "$ud" 2>/dev/null | awk -F': ' '/^ramdisk size/ {print $2}')
        # 14. The installed vendor_boot ramdisk is LZ4 legacy; the boot ramdisk
        # appended after it must be LZ4 legacy too (magic 02 21 4c 18).
        if [ -f "$ud/ramdisk" ]; then
            [ "$(head -c4 "$ud/ramdisk" | od -An -tx1 | tr -d ' ')" = "02214c18" ] \
                && ok "ramdisk is LZ4 legacy (matches vendor_boot)" || bad "ramdisk is not LZ4 legacy: kernel will fail to unpack it after vendor_boot's"
        fi
        if [ -n "$rd" ]; then
            [ "$rd" -le 41500000 ] && ok "ramdisk $rd <= 41500000 bytes (largest size proven to boot)" || bad "ramdisk $rd > 41500000 bytes: spes bootloader will not start it"
        else note "could not read ramdisk size"; fi
    else note "no built boot.img yet"; fi
else
    note "no source root given: AERA flag and image checks skipped"
fi

echo "---- $fail failure(s), $warn warning(s)"
[ "$fail" -eq 0 ]
