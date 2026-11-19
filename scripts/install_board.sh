#!/usr/bin/env bash
# =============================================================================
# install_board.sh — 把本项目 src/ 里的全部改动同步进路线B 的 Android 14 源码树
#
# 用途: src/ 是"我改过的源码"唯一可信副本 (§23); SDK 树在仓外
#       (~/linux/rk3576_android/work/radxa-rk3576-android14), 随时可能被 repo sync 覆盖,
#       所以每次改完 src/ 都跑本脚本推一次; 反过来在 SDK 里调试改通了, 用 --pull 拉回 src/。
#
# 🔴 编译铁律 (rk3576_android14/README.md §6): 出固件前**必须**先 `--check` 全绿,
#    否则编出来的固件缺 src/ 里的功能 (WiFi 驱动补丁 / 板级固件 / DTS 都会丢)。
#
# 同步四类内容:
#   1) 内核板级 DTS     src/kernel-6.1/.../*.dts*            → SDK kernel-6.1/...
#   2) 板级目录         src/device/.../rk3576_lz200/          → SDK 同目录 (镜像, firmware/ 除外)
#   3) 单文件           src/external/... src/frameworks/...   → SDK 同名路径 (驱动 + HAL)
#   4) 无线固件         src/firmware/swt6652x/*               → SDK 板级 firmware/ (含改名)
#   5) vendor wifi.mk   SDK `vendor/rockchip/common/wifi/wifi.mk` 幂等打 filter-out 补丁
#                       (否则该 mk 会用 EA6621Q 版同名固件覆盖板级固件 → WiFi 起不来)
#
# 机器: 本机 dengbaowen-ubuntu (普通用户, 不要 sudo)
# 用法:
#   bash scripts/install_board.sh            # src/ → SDK (推; 默认)
#   bash scripts/install_board.sh --check    # 只比对 md5, 不写 (不一致 exit 1)
#   bash scripts/install_board.sh --pull     # SDK → src/ (调试改通了回收)
#   SDK=/path/to/tree bash scripts/install_board.sh   # 换源码树
# 依赖: bash / rsync / python3 / md5sum
# 危险: 会覆盖 SDK 里的同名文件; 不碰 .repo, 不 git commit
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
PROJ="$(pwd)"

SDK="${SDK:-$HOME/linux/rk3576_android/work/radxa-rk3576-android14}"
MODE="push"
case "${1:-}" in
    ""|--push) MODE="push" ;;
    --check)   MODE="check" ;;
    --pull)    MODE="pull" ;;
    *) echo "用法: $0 [--check|--pull|--push]"; exit 2 ;;
esac

[ -d "$SDK" ] || { echo "ERR 源码树不存在: $SDK"; echo "    先按 docs/ADAPT_ROCKCHIP_ANDROID.md §5 拉源码, 或用 SDK=<路径> 指定"; exit 2; }

KSRC_REL="kernel-6.1/arch/arm64/boot/dts/rockchip"
DEV_REL="device/rockchip/rk3576/rk3576_lz200"
SRC_K="$PROJ/src/$KSRC_REL"
SRC_DEV="$PROJ/src/$DEV_REL"
SDK_K="$SDK/$KSRC_REL"
SDK_DEV="$SDK/$DEV_REL"

for d in "$SRC_K" "$SRC_DEV"; do
    [ -d "$d" ] || { echo "ERR src 里缺目录: $d"; exit 2; }
done
# ---- 1) 内核 DTS 目录 (lz200 fragment + rk3576-lz200-android.dts) ----
# 注意: 只拷 rk3576-neardi-* 和 rk3576-lz200-* 前缀, 不整目录覆盖 (避免删掉 BSP 自己的 dts)

push_kernel() {
    [ -d "$SDK_K" ] || { echo "ERR SDK 里没有 $SDK_K (内核还没 repo sync 完?)"; exit 2; }
    for f in "$SRC_K"/rk3576-neardi*.dtsi "$SRC_K"/rk3576-lz200-*.dts; do
        [ -f "$f" ] || continue
        cp -a "$f" "$SDK_K/"
        echo "  → kernel: $(basename "$f")"
    done
    # Makefile 登记 dtb (幂等; 不登记则 make rk3576-lz200-android.img 报无此目标)
    local mk="$SDK_K/Makefile" line='dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3576-lz200-android.dtb'
    if grep -qF 'rk3576-lz200-android.dtb' "$mk"; then
        echo "  = kernel Makefile 已登记 rk3576-lz200-android.dtb"
    else
        python3 - "$mk" "$line" <<'PY'
import sys
mk, line = sys.argv[1], sys.argv[2]
src = open(mk).read().splitlines(True)
out, done = [], False
for l in src:
    out.append(l)
    if not done and l.startswith('dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3576-'):
        out.append(line + '\n'); done = True
if done:
    open(mk, 'w').writelines(out)
print('  + kernel Makefile 已加: ' + line if done else '  ! 未找到 rk3576 dtb 段, 请手工加: ' + line)
PY
    fi
}

check_kernel() {
    local bad=0 n=0
    for f in "$SRC_K"/rk3576-neardi*.dtsi "$SRC_K"/rk3576-lz200-*.dts; do
        [ -f "$f" ] || continue
        n=$((n+1))
        local s; s=$(md5sum "$f" | cut -d' ' -f1)
        if [ -f "$SDK_K/$(basename "$f")" ]; then
            local d; d=$(md5sum "$SDK_K/$(basename "$f")" | cut -d' ' -f1)
            [ "$s" = "$d" ] || { echo "  DIFF kernel: $(basename "$f")  src=$s sdk=$d"; bad=$((bad+1)); }
        else
            echo "  MISS kernel: $(basename "$f")"; bad=$((bad+1))
        fi
    done
    grep -qF 'rk3576-lz200-android.dtb' "$SDK_K/Makefile" 2>/dev/null || { echo "  MISS kernel Makefile 未登记 rk3576-lz200-android.dtb"; bad=$((bad+1)); }
    echo "  kernel: 比对 $n 个文件, 不一致 $bad"
    return $((bad>0))
}

pull_kernel() {
    for f in "$SDK_K"/rk3576-neardi*.dtsi "$SDK_K"/rk3576-lz200-*.dts; do
        [ -f "$f" ] || continue
        cp -a "$f" "$SRC_K/"
        echo "  ← kernel: $(basename "$f")"
    done
    echo "  ! Makefile 的 dtb 行不回收 (它是构建列表, 由本脚本维护)"
}

# ---- 2) 板级目录 device/rockchip/rk3576/rk3576_lz200/ ----
# firmware/ 由下面第 4 步从 src/firmware/swt6652x/ 生成 ⇒ 这里排除, 免得互相删
push_dev() {
    [ -d "$SDK/device/rockchip/rk3576" ] || { echo "ERR SDK 里没有 device/rockchip/rk3576"; exit 2; }
    rsync -a --delete --exclude 'firmware/' "$SRC_DEV/" "$SDK_DEV/"
    echo "  → device: rk3576_lz200/ ($(find "$SDK_DEV" -type f | wc -l) 个文件)"
}

check_dev() {
    local bad=0
    while IFS= read -r f; do
        local rel="${f#$SRC_DEV/}"
        if [ -f "$SDK_DEV/$rel" ]; then
            [ "$(md5sum "$f" | cut -d' ' -f1)" = "$(md5sum "$SDK_DEV/$rel" | cut -d' ' -f1)" ] \
                || { echo "  DIFF device: $rel"; bad=$((bad+1)); }
        else
            echo "  MISS device: $rel"; bad=$((bad+1))
        fi
    done < <(find "$SRC_DEV" -type f)
    echo "  device: 不一致 $bad"
    return $((bad>0))
}

pull_dev() {
    mkdir -p "$SRC_DEV"
    rsync -a --delete --exclude 'firmware/' "$SDK_DEV/" "$SRC_DEV/"
    echo "  ← device: rk3576_lz200/ ($(find "$SRC_DEV" -type f | wc -l) 个文件)"
}

# ---- 3) 单文件映射: 驱动 + WiFi HAL (src 与 SDK 同名路径) ----
# 这些是相对 SDK 根的路径; 加新补丁文件时只改这里一处
FILE_MAP=(
    "external/wifi_driver/ea6621q/drivers/skwifi/skw_core.c"
    "external/wifi_driver/ea6621q/drivers/skwifi/skw_cfg80211.c"
    "external/wifi_driver/ea6621q/drivers/skwifi/skw_cfg80211.h"
    "external/wifi_driver/ea6621q/drivers/skwifi/skw_msg.c"
    "external/wifi_driver/ea6621q/drivers/skwifi/skw_rx.c"
    "external/wifi_driver/ea6621q/drivers/skwifi/skw_work.c"
    "external/wifi_driver/ea6621q/drivers/seekwaveplatform/sdio/skw_sdio_main.c"
    "external/wifi_driver/ea6621q/drivers/seekwaveplatform/sdio/skw_sdio_rx.c"
    "external/wifi_driver/ea6621q/include/linux/platform_data/skw6160_config.h"
    "frameworks/opt/net/wifi/libwifi_hal/rk_wifi_ctrl.cpp"
    "packages/modules/Bluetooth/system/gd/stack_manager.cc"
    "packages/modules/Wifi/service/java/com/android/server/wifi/ClientModeImpl.java"
)

push_files() {
    for rel in "${FILE_MAP[@]}"; do
        [ -f "$PROJ/src/$rel" ] || { echo "ERR src 里缺: src/$rel"; exit 2; }
        mkdir -p "$SDK/$(dirname "$rel")"
        cp -a "$PROJ/src/$rel" "$SDK/$rel"
        echo "  → file: $rel"
    done
}

check_files() {
    local bad=0
    for rel in "${FILE_MAP[@]}"; do
        if [ ! -f "$PROJ/src/$rel" ]; then echo "  MISS src: $rel"; bad=$((bad+1)); continue; fi
        if [ ! -f "$SDK/$rel" ]; then echo "  MISS sdk: $rel"; bad=$((bad+1)); continue; fi
        [ "$(md5sum "$PROJ/src/$rel" | cut -d' ' -f1)" = "$(md5sum "$SDK/$rel" | cut -d' ' -f1)" ] \
            || { echo "  DIFF file: $rel"; bad=$((bad+1)); }
    done
    echo "  files: 比对 ${#FILE_MAP[@]} 个, 不一致 $bad"
    return $((bad>0))
}

pull_files() {
    for rel in "${FILE_MAP[@]}"; do
        [ -f "$SDK/$rel" ] || { echo "  ! SDK 里没有 $rel, 跳过"; continue; }
        mkdir -p "$PROJ/src/$(dirname "$rel")"
        cp -a "$SDK/$rel" "$PROJ/src/$rel"
        echo "  ← file: $rel"
    done
}

# ---- 4) 无线固件: src/firmware/swt6652x/ → SDK 板级 firmware/ (驱动要求的名字) ----
# 驱动里固件名是硬编码的 (ROM_EXEC_KERNEL_IRAM.bin / RAM_RW_KERNEL_DRAM.bin),
# 不支持 DT 改路径 ⇒ 必须按这个名字装进 /vendor/etc/firmware/。
# 格式: "<src 里文件名>|<SDK 板级 firmware/ 里文件名>"
SRC_FW="$PROJ/src/firmware/swt6652x"
SDK_FW="$SDK_DEV/firmware"
FW_MAP=(
    "SWT6652_IRAM_SDIO.bin|ROM_EXEC_KERNEL_IRAM.bin"
    "SWT6652_DRAM_SDIO.bin|RAM_RW_KERNEL_DRAM.bin"
    "SEEKWAVE_NV_SWT6652_SHARE.bin|SEEKWAVE_NV_SWT6652_SHARE.bin"
    "EA6316_SEEKWAVE_R00006.bin|EA6316_SEEKWAVE_R00006.bin"
    "EA6316_SEEKWAVE_R00006.ini|EA6316_SEEKWAVE_R00006.ini"
)

push_fw() {
    [ -d "$SRC_FW" ] || { echo "ERR src 里缺固件目录: $SRC_FW"; exit 2; }
    mkdir -p "$SDK_FW"
    for m in "${FW_MAP[@]}"; do
        local s="${m%%|*}" d="${m##*|}"
        [ -f "$SRC_FW/$s" ] || { echo "ERR src 里缺固件: $SRC_FW/$s"; exit 2; }
        cp -a "$SRC_FW/$s" "$SDK_FW/$d"
        echo "  → firmware: $s → firmware/$d"
    done
}

check_fw() {
    local bad=0
    for m in "${FW_MAP[@]}"; do
        local s="${m%%|*}" d="${m##*|}"
        if [ ! -f "$SRC_FW/$s" ]; then echo "  MISS src firmware: $s"; bad=$((bad+1)); continue; fi
        if [ ! -f "$SDK_FW/$d" ]; then echo "  MISS sdk firmware: $d"; bad=$((bad+1)); continue; fi
        [ "$(md5sum "$SRC_FW/$s" | cut -d' ' -f1)" = "$(md5sum "$SDK_FW/$d" | cut -d' ' -f1)" ] \
            || { echo "  DIFF firmware: $d"; bad=$((bad+1)); }
    done
    echo "  firmware: 比对 ${#FW_MAP[@]} 个, 不一致 $bad"
    return $((bad>0))
}

pull_fw() {
    mkdir -p "$SRC_FW"
    for m in "${FW_MAP[@]}"; do
        local s="${m%%|*}" d="${m##*|}"
        [ -f "$SDK_FW/$d" ] || { echo "  ! SDK 板级固件里没有 $d, 跳过"; continue; }
        cp -a "$SDK_FW/$d" "$SRC_FW/$s"
        echo "  ← firmware: $d → $s"
    done
}

# ---- 5) WiFi 固件目的路径冲突: vendor/rockchip/common/wifi/wifi.mk 幂等补丁 ----
# 该 mk 第 23/25 行用 `$(shell ls $(CUR_PATH)/wifi/firmware)` 把目录内**所有**文件拷到
# $(TARGET_COPY_OUT_VENDOR)/etc/firmware/ —— 其中有与驱动硬编码名撞车的
# ROM_EXEC_KERNEL_IRAM.bin(499196B) / RAM_RW_KERNEL_DRAM.bin(235044B) 是 **EA6621Q** 版,
# 与板级 PRODUCT_COPY_FILES 目的路径完全相同 ⇒ ninja 只留一条 (实际留下它那条)
# ⇒ 编出来的 vendor 里固件是错的 ⇒ 烧完 `wifi boot failed`。
# 修法: filter-out 这两个名字, 让它们只由板级 firmware/ (SWT6652x) 提供。
VENDOR_WIFI_MK="$SDK/vendor/rockchip/common/wifi/wifi.mk"

patch_vendor_wifi() {
    [ -f "$VENDOR_WIFI_MK" ] || { echo "  ! 没有 $VENDOR_WIFI_MK, 跳过"; return 0; }
    python3 - "$VENDOR_WIFI_MK" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8', errors='replace').read()
mark = '# lz200: 这两个名字由板级 PRODUCT_COPY_FILES 提供'
if mark in s:
    print('  = vendor wifi.mk 已有 filter-out 补丁'); raise SystemExit(0)
old = 'WifiFirmwareFile := $(shell ls $(CUR_PATH)/wifi/firmware)\n'
if old not in s:
    print('  ! vendor wifi.mk 结构变了, 找不到 WifiFirmwareFile 定义 => 需人工确认'); raise SystemExit(3)
new = old + (
    mark + '\n'
    'WifiFirmwareFile := $(filter-out ROM_EXEC_KERNEL_IRAM.bin RAM_RW_KERNEL_DRAM.bin,$(WifiFirmwareFile))\n')
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
print('  + vendor wifi.mk 已加 filter-out (这两个固件名只由板级提供)')
PY
}

check_vendor_wifi() {
    if [ ! -f "$VENDOR_WIFI_MK" ]; then echo "  vendor wifi.mk: 不存在 (跳过)"; return 0; fi
    if grep -qF '$(filter-out ROM_EXEC_KERNEL_IRAM.bin RAM_RW_KERNEL_DRAM.bin,$(WifiFirmwareFile))' "$VENDOR_WIFI_MK"; then
        echo "  vendor wifi.mk: 已 filter-out 冲突固件名 (OK)"
        return 0
    fi
    echo "  DIFF vendor wifi.mk: 缺 filter-out 补丁 => 编出来的固件会被 EA6621Q 版覆盖 (WiFi 起不来)"
    return 1
}

echo "== install_board.sh mode=$MODE"
echo "   src : $PROJ/src"
echo "   SDK : $SDK"
rc=0
case "$MODE" in
    push)  push_kernel; push_dev; push_files; push_fw; patch_vendor_wifi
           echo "-- 推完, 跑一次 --check 核对:"
           check_kernel || rc=1; check_dev || rc=1; check_files || rc=1; check_fw || rc=1; check_vendor_wifi || rc=1 ;;
    pull)  pull_kernel; pull_dev; pull_files; pull_fw
           echo "  ! vendor wifi.mk 的 filter-out 补丁是脚本维护的, --pull 不回收" ;;
    check) check_kernel || rc=1; check_dev || rc=1; check_files || rc=1; check_fw || rc=1; check_vendor_wifi || rc=1 ;;
esac
[ "$rc" = 0 ] && echo "== OK" || { echo "== 不一致 (见上)"; }
exit "$rc"
