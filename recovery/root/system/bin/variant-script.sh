#!/system/bin/sh
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# spes and spesn share one firmware. The stock vendor selects
# /vendor/build_${ro.boot.product.hardware.sku}.prop, so the SKU (not the
# region in ro.boot.hwc) is the authoritative variant switch:
#   k7t   -> spes  2201117TG     k7tin -> spes  2201117TI
#   k7tl  -> spes  2201117TL     k7tn  -> spesn 2201117TY (NFC)

set_device() {
    for p in ro.product.device ro.product.vendor.device ro.product.system.device \
             ro.product.odm.device ro.product.product.device ro.build.product \
             ro.product.board; do
        resetprop "$p" "$1"
    done
    resetprop ro.product.name "$1_global"
    resetprop ro.product.model "$2"
    resetprop ro.product.vendor.model "$2"
}

sku="$(getprop ro.boot.product.hardware.sku)"
case "$sku" in
    k7tn)  set_device spesn 2201117TY ;;
    k7tin) set_device spes 2201117TI ;;
    k7tl)  set_device spes 2201117TL ;;
    k7t)   set_device spes 2201117TG ;;
    *)     echo "variant-script: unknown sku '$sku', keeping build defaults" > /dev/kmsg
           exit 0 ;;
esac

echo "variant-script: sku=$sku -> $(getprop ro.product.device)" > /dev/kmsg
exit 0
