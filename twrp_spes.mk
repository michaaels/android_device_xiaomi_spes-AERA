#
# Copyright (C) 2021 The LineageOS Project
# Copyright (C) 2026 AERA Recovery Project contributors
#
# SPDX-License-Identifier: Apache-2.0
#

# Hardware-specific configuration (inherits vendor/twrp and aera_spes.mk)
$(call inherit-product, device/xiaomi/spes/device.mk)

## Device identifier. One image serves both variants; spes/spesn props are set
## at runtime from ro.boot.product.hardware.sku (recovery/root/system/bin/variant-script.sh).
PRODUCT_DEVICE := spes
PRODUCT_NAME := twrp_spes
PRODUCT_BRAND := Redmi
PRODUCT_MODEL := Redmi Note 11
PRODUCT_MANUFACTURER := Xiaomi
