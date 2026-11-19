#!/usr/bin/env bash
# =============================================================================
# check_firmware_content.sh — 编译铁律的机器门禁: 核对"编出来的镜像内容 == 主仓 src/"
#
# 为什么需要:
#   §23 说 SDK 只是编译场, 主仓 src/ 才是唯一可信副本。但 `update.img` 是黑盒,
#   历史上就踩过坑: 板级 PRODUCT_COPY_FILES 装的 SWT6652x 固件被
#   vendor/rockchip/common/wifi/wifi.mk 里同名的 EA6621Q 版覆盖 —— 编译全绿、
#   烧完 `wifi boot failed`。所以出固件前必须用本脚本验一遍 out/ 里的实际 md5。
#
# 用法:
#   bash scripts/check_firmware_content.sh          # 校验 (exit 1 = 不许出固件)
#   SDK=/path/to/tree bash scripts/check_firmware_content.sh
#
# 机器: 本机 dengbaowen-ubuntu (需要已编译过, out/ 存在)
# 依赖: bash / md5sum / grep
# 产出: 只读校验, 不写任何文件
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
PROJ="$(pwd)"
SDK="${SDK:-$HOME/linux/rk3576_android/work/radxa-rk3576-android14}"
T="${T:-rk3576_lz200}"
O="$SDK/out/target/product/$T"

[ -d "$O" ] || { echo "ERR 没有编译产物目录: $O"; exit 2; }

bad=0
chk() { # chk <说明> <期望 md5> <实际文件>
    local desc="$1" want="$2" f="$3"
    if [ ! -f "$f" ]; then echo "  MISS $desc ($f 不存在)"; bad=$((bad+1)); return; fi
    local got; got=$(md5sum "$f" | cut -d' ' -f1)
    if [ "$got" = "$want" ]; then
        echo "  OK   $desc  md5=$got  ($(stat -c%s "$f")B)"
    else
        echo "  FAIL $desc  md5=$got  期望=$want  ($(stat -c%s "$f")B)"
        bad=$((bad+1))
    fi
}
md5of() { md5sum "$1" | cut -d' ' -f1; }

echo "== check_firmware_content: $O"
echo "-- 1) /vendor/etc/firmware 四个运行期固件 (必须来自 src/firmware/swt6652x/)"
F="$PROJ/src/firmware/swt6652x"
chk "vendor/etc/firmware/ROM_EXEC_KERNEL_IRAM.bin (=SWT6652_IRAM_SDIO.bin)" \
    "$(md5of "$F/SWT6652_IRAM_SDIO.bin")" "$O/vendor/etc/firmware/ROM_EXEC_KERNEL_IRAM.bin"
chk "vendor/etc/firmware/RAM_RW_KERNEL_DRAM.bin  (=SWT6652_DRAM_SDIO.bin)" \
    "$(md5of "$F/SWT6652_DRAM_SDIO.bin")" "$O/vendor/etc/firmware/RAM_RW_KERNEL_DRAM.bin"
chk "vendor/etc/firmware/SEEKWAVE_NV_SWT6652_SHARE.bin" \
    "$(md5of "$F/SEEKWAVE_NV_SWT6652_SHARE.bin")" "$O/vendor/etc/firmware/SEEKWAVE_NV_SWT6652_SHARE.bin"
chk "vendor/etc/firmware/EA6316_SEEKWAVE_R00006.bin" \
    "$(md5of "$F/EA6316_SEEKWAVE_R00006.bin")" "$O/vendor/etc/firmware/EA6316_SEEKWAVE_R00006.bin"
chk "vendor/etc/firmware/EA6316_SEEKWAVE_R00006.ini" \
    "$(md5of "$F/EA6316_SEEKWAVE_R00006.ini")" "$O/vendor/etc/firmware/EA6316_SEEKWAVE_R00006.ini"

echo "-- 2) vendor_dlkm 三个 skw 模块 (必须来自 SDK 刚编的 external/wifi_driver)"
for ko in skw.ko skw_bootcoms.ko skw_sdio.ko; do
    src=$(find "$SDK/external/wifi_driver" -name "$ko" -type f | head -1)
    if [ -z "$src" ]; then echo "  MISS SDK 里找不到 $ko"; bad=$((bad+1)); continue; fi
    chk "vendor_dlkm/lib/modules/$ko" "$(md5of "$src")" "$O/vendor_dlkm/lib/modules/$ko"
done

echo "-- 3) WiFi HAL 含 SKW6160 (板载 SV6316 识别表)"
for so in "$O/vendor/lib64/librkwifi-ctrl.so" "$O/vendor/lib/librkwifi-ctrl.so"; do
    if [ ! -f "$so" ]; then echo "  MISS $so"; bad=$((bad+1)); continue; fi
    if grep -qa "SKW6160" "$so" && grep -qa "1ffe:6316" "$so"; then
        echo "  OK   ${so#$O/}  含 SKW6160 + 1ffe:6316"
    else
        echo "  FAIL ${so#$O/}  缺 SKW6160 或 1ffe:6316 字符串 (= HAL 没带上补丁)"
        bad=$((bad+1))
    fi
done

echo "-- 4) skw.ko 芯片标识必须是 EA6316"
if [ -f "$O/vendor_dlkm/lib/modules/skw.ko" ] && grep -qa "EA6316" "$O/vendor_dlkm/lib/modules/skw.ko"; then
    echo "  OK   skw.ko 含 EA6316"
else
    echo "  FAIL skw.ko 不含 EA6316 (= CONFIG_SKW_CHIP_ID 补丁没进固件)"
    bad=$((bad+1))
fi

echo "-- 5) wifi.load 里必须列出三个 skw 模块"
if [ -f "$O/vendor/etc/wifi/wifi.load" ]; then
    n=$(grep -c "skw" "$O/vendor/etc/wifi/wifi.load")
    if [ "$n" -ge 3 ]; then echo "  OK   wifi.load 含 $n 个 skw 模块"; else
        echo "  FAIL wifi.load 只含 $n 个 skw 模块 (应为 3)"; bad=$((bad+1)); fi
else
    echo "  MISS vendor/etc/wifi/wifi.load"; bad=$((bad+1))
fi

echo "== 结果: 不一致 $bad 项"
[ "$bad" = 0 ] && { echo "== OK (可以出 update.img / 烧录)"; exit 0; } || { echo "== FAIL (先修 src→SDK 或重编, 不许出固件)"; exit 1; }
