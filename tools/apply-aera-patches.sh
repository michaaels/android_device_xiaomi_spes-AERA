#!/bin/bash
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# Applies the generic AERA fixes kept in patches/bootable_recovery/ (proposed
# upstream, not part of the device tree) to a synced source tree, in order,
# and regenerates the compiled translation catalog.
#   tools/apply-aera-patches.sh <AERA source root>
#
# Applied patches are recorded (name + SHA-256) in
# bootable/recovery/.aera-spes-patches, because later patches may change lines
# touched by earlier ones, which makes "git apply --reverse --check" unreliable.
# To start over: git -C bootable/recovery checkout . && rm .aera-spes-patches
set -euo pipefail

TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: $0 <AERA source root>}"
REC="$SRC/bootable/recovery"
STAMP="$REC/.aera-spes-patches"
[ -d "$REC/.git" ] || { echo "no bootable/recovery git tree under $SRC" >&2; exit 1; }
touch "$STAMP"

catalog_changed=0
for p in "$TREE"/patches/bootable_recovery/*.diff; do
    name="$(basename "$p")"; sum="$(sha256sum "$p" | cut -d' ' -f1)"
    if grep -qx "$name $sum" "$STAMP"; then
        echo "already applied: $name"; continue
    fi
    if git -C "$REC" apply --check "$p" 2>/dev/null; then
        git -C "$REC" apply "$p"
        echo "applied: $name"
    elif git -C "$REC" apply --reverse --check "$p" 2>/dev/null; then
        echo "already present (recorded now): $name"
    else
        echo "ERROR: $name neither applies nor is present; the tree is in an unknown state." >&2
        echo "Reset with: git -C $REC checkout . && rm $STAMP" >&2
        exit 1
    fi
    echo "$name $sum" >> "$STAMP"
    grep -q "catalog/catalog.json" "$p" && catalog_changed=1
done

if [ "$catalog_changed" = 1 ]; then
    (cd "$REC" && python3 -I aeraui/localization/catalog/generate_catalog.py \
        --recovery . --output aeraui/localization/catalog/catalog_generated.cpp)
fi
