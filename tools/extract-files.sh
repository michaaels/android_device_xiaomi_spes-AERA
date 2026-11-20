#!/bin/bash
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# Copies the blobs listed in proprietary-files.txt into recovery/root/.
#   tools/extract-files.sh --adb           # from a connected spes (read-only adb pull of /vendor)
#   tools/extract-files.sh --dump <dir>    # from an extracted stock vendor image
# Writes tools/blobs.sha256 so the exact blob set is reproducible.
set -euo pipefail

TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$TREE/proprietary-files.txt"
DEST="$TREE/recovery/root"
MODE="${1:-}"
SRC="${2:-}"

case "$MODE" in
    --adb)  adb wait-for-device
            dev="$(adb shell getprop ro.product.vendor.device | tr -d '\r')"
            case "$dev" in spes|spesn) ;; *) echo "connected device is '$dev', not spes/spesn" >&2; exit 1 ;; esac ;;
    --dump) [ -d "$SRC" ] || { echo "dump dir '$SRC' not found" >&2; exit 1; } ;;
    *)      echo "usage: $0 --adb | --dump <vendor dir>" >&2; exit 2 ;;
esac

missing=0
: > "$TREE/tools/blobs.sha256.tmp"
while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs)"
    [ -z "$line" ] && continue
    src="${line%%:*}"; dst="${line#*:}"; [ "$dst" = "$line" ] && dst="vendor/$src"
    mkdir -p "$(dirname "$DEST/$dst")"
    if [ "$MODE" = "--adb" ]; then
        adb pull "/vendor/$src" "$DEST/$dst" >/dev/null 2>&1 || { echo "MISSING /vendor/$src"; missing=$((missing+1)); continue; }
    else
        cp -f "$SRC/$src" "$DEST/$dst" 2>/dev/null || { echo "MISSING $src"; missing=$((missing+1)); continue; }
    fi
    (cd "$DEST" && sha256sum "$dst") >> "$TREE/tools/blobs.sha256.tmp"
done < "$LIST"

mv "$TREE/tools/blobs.sha256.tmp" "$TREE/tools/blobs.sha256"
echo "done, missing=$missing (checksums in tools/blobs.sha256)"
[ "$missing" -eq 0 ]
