#!/bin/bash
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# Applies the generic AERA fixes kept in patches/bootable_recovery/ (proposed
# upstream, not part of the device tree) to a synced source tree and
# regenerates the compiled translation catalog.
#   tools/apply-aera-patches.sh <AERA source root>
# Idempotent: already-applied patches are skipped.
set -euo pipefail

TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: $0 <AERA source root>}"
REC="$SRC/bootable/recovery"
[ -d "$REC/.git" ] || { echo "no bootable/recovery git tree under $SRC" >&2; exit 1; }

catalog_changed=0
for p in "$TREE"/patches/bootable_recovery/*.diff; do
    name="$(basename "$p")"
    if git -C "$REC" apply --reverse --check "$p" 2>/dev/null; then
        echo "already applied: $name"
    else
        git -C "$REC" apply "$p"
        echo "applied: $name"
        grep -q "catalog/catalog.json" "$p" && catalog_changed=1
    fi
done

if [ "$catalog_changed" = 1 ] || ! git -C "$REC" diff --quiet -- aeraui/localization/catalog/catalog.json; then
    (cd "$REC" && python3 -I aeraui/localization/catalog/generate_catalog.py \
        --recovery . --output aeraui/localization/catalog/catalog_generated.cpp)
fi
