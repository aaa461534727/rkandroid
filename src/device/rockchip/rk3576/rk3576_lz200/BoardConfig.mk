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
BUILD_WITH_GO_OPT := false
BOARD_BUILD_GKI := false

BOARD_GRAVITY_SENSOR_SUPPORT := true
BOARD_COMPASS_SENSOR_SUPPORT := true
BOARD_SENSOR_COMPASS_AK8963-64 := true
BOARD_GYROSCOPE_SENSOR_SUPPORT := true
BOARD_PROXIMITY_SENSOR_SUPPORT := true
BOARD_LIGHT_SENSOR_SUPPORT := true

# NEARDI LKB3576 (board level = neardi lz200)
# DTS 见 kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-lz200-android.dts
PRODUCT_KERNEL_DTS := rk3576-lz200-android
# 板载无线是 SeekWave SV6160 (SDIO), 不是 EVB 的 M.2 PCIe 网卡 ⇒ 不引 pcie_wifi.config
# 缺外设时再新增 arch/arm64/configs/rk3576_lz200.config 并在此 += 之
# eMMC 实测 29G 可用: super 给 6GiB (AOSP 14 tablet userdebug 约 4G), 其余留给 userdata
# 不设则 Partitions.mk 默认 3263168512 (~3.04G), userdebug 容易不够
BOARD_SUPER_PARTITION_SIZE := 6442450944

BOARD_HS_ETHERNET := true
BOARD_CAMERA_SUPPORT_EXT := true
# lz200 板上没有 MXC6655XA 加速度计 (DTS 里无对应节点)
BOARD_GSENSOR_MXC6655XA_SUPPORT := false

# 存储介质: 板载 eMMC (sdhci@2a330000, 29G), 无 UFS / 无 SPI-NVMe
# 这两个变量必须显式给 false/emmc (不能留空):
#   1) RebuildParameter.mk:8 的 `ifeq ($(strip $(BOARD_USES_SPI_NVME_BOOT)), false)` 判空串不成立
#      ⇒ parameter.txt 会生成 NVMe 布局 (缺 uboot:4M / trust:4M, misc 落在 0x4000 覆盖 uboot)
#   2) build.sh:378 同样判空串不成立 ⇒ 走 mkupdate_nvme.sh, 只打 PCIE + SPINOR 两段
#      ⇒ upgrade_tool uf 报 "Failed to get EMMC update in the firmware"
BOARD_USES_SPI_NVME_BOOT := false

ifeq ($(strip $(BOARD_USES_SPI_NVME_BOOT)), false)
BOARD_ROCKCHIP_FLASH_TYPE := emmc    # scsi(ufs) emmc(emmc)
PRODUCT_BOOT_DEVICE := 2a330000.mmc,2a310000.mmc
PRODUCT_UBOOT_CONFIG := rk3576_defconfig
endif

BOARD_SEPOLICY_DIRS += $(TARGET_DEVICE_DIR)/sepolicy

include device/rockchip/rk3576/BoardConfig.mk
