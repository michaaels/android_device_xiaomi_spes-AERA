#
# Copyright (C) 2021 The LineageOS Project
# Copyright (C) 2026 AERA Recovery Project contributors
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/xiaomi/spes

$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)

# spes launched with Android 11, Virtual A/B and a vendor_boot ramdisk
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/launch_with_vendor_ramdisk.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

# Recovery build system
$(call inherit-product, vendor/twrp/config/common.mk)

# AERA product settings for spes / spesn
$(call inherit-product, $(LOCAL_PATH)/aera_spes.mk)

# API (ro.product.first_api_level / ro.board.first_api_level = 30)
PRODUCT_SHIPPING_API_LEVEL := 30
BOARD_SHIPPING_API_LEVEL := 30

# Dynamic partitions (super is not built; recovery only reads its metadata)
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_BUILD_SUPER_PARTITION := false

# Qualcomm FBE decryption scripts/services from device/qcom/twrp-common
PRODUCT_PACKAGES += \
    qcom_decrypt \
    qcom_decrypt_fbe

# FUSE passthrough
PRODUCT_SYSTEM_PROPERTIES += \
    persist.sys.fuse.passthrough.enable=true

PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)
