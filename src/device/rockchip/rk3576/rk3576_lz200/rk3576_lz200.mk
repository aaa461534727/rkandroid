#
# Copyright 2023 The Android Open-Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# First lunching is U, api_level is 34
PRODUCT_SHIPPING_API_LEVEL := 34
PRODUCT_DTBO_TEMPLATE := $(LOCAL_PATH)/dt-overlay.in

include device/rockchip/common/build/rockchip/DynamicPartitions.mk
include device/rockchip/rk3576/rk3576_lz200/BoardConfig.mk
include device/rockchip/common/BoardConfig.mk
$(call inherit-product, device/rockchip/rk3576/device.mk)
$(call inherit-product, device/rockchip/common/device.mk)
$(call inherit-product, frameworks/native/build/tablet-10in-xhdpi-2048-dalvik-heap.mk)

DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/../overlay

PRODUCT_CHARACTERISTICS := tablet

PRODUCT_NAME := rk3576_lz200
PRODUCT_DEVICE := rk3576_lz200
PRODUCT_BRAND := rockchip
PRODUCT_MODEL := LKB3576
PRODUCT_MANUFACTURER := rockchip
PRODUCT_AAPT_PREF_CONFIG := mdpi
#
## add Rockchip properties
#
PRODUCT_PROPERTY_OVERRIDES += ro.sf.lcd_density=320
PRODUCT_PROPERTY_OVERRIDES += ro.wifi.sleep.power.down=true
PRODUCT_PROPERTY_OVERRIDES += persist.wifi.sleep.delay.ms=0
PRODUCT_PROPERTY_OVERRIDES += persist.bt.power.down=true
PRODUCT_PROPERTY_OVERRIDES += vendor.hwc.device.primary=DSI
PRODUCT_PROPERTY_OVERRIDES += vendor.hwc.device.extend=HDMI-A,eDP

# ---- 板载无线 (SeekWave SV6316 / SWT6652x) 固件 ----
# 驱动请求的固件名是硬编码 (ROM_EXEC_KERNEL_IRAM.bin / RAM_RW_KERNEL_DRAM.bin),
# 不支持通过 DT 改路径 => 必须按此名装进 /vendor/etc/firmware/。
# 这些文件由 scripts/install_board.sh 从 src/firmware/swt6652x/ 生成到本目录 firmware/。
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/firmware/ROM_EXEC_KERNEL_IRAM.bin:$(TARGET_COPY_OUT_VENDOR)/etc/firmware/ROM_EXEC_KERNEL_IRAM.bin \
    $(LOCAL_PATH)/firmware/RAM_RW_KERNEL_DRAM.bin:$(TARGET_COPY_OUT_VENDOR)/etc/firmware/RAM_RW_KERNEL_DRAM.bin \
    $(LOCAL_PATH)/firmware/SEEKWAVE_NV_SWT6652_SHARE.bin:$(TARGET_COPY_OUT_VENDOR)/etc/firmware/SEEKWAVE_NV_SWT6652_SHARE.bin \
    $(LOCAL_PATH)/firmware/EA6316_SEEKWAVE_R00006.bin:$(TARGET_COPY_OUT_VENDOR)/etc/firmware/EA6316_SEEKWAVE_R00006.bin \
    $(LOCAL_PATH)/firmware/EA6316_SEEKWAVE_R00006.ini:$(TARGET_COPY_OUT_VENDOR)/etc/firmware/EA6316_SEEKWAVE_R00006.ini
