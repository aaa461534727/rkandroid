#!/usr/bin/env bash
# 用途: 把 rockdev/Image-rk3576_lz200/update.img 整包烧进板子 eMMC (rockusb/loader 模式), 烧前先核 md5
# 机器: 本机 dengbaowen-ubuntu (VM); 脚本内用 sudo -n, 需该用户免密 sudo
# 用法: bash scripts/flash_update.sh [--wait 分钟] [--reboot-loader] [--sdk <SDK 路径>]
# 依赖: SDK 内 RKTools/linux/Linux_Upgrade_Tool/upgrade_tool_v2.30_for_linux/upgrade_tool, lsusb, adb(可选)
# 危险: 会按 update.img 里的 parameter.txt **重建 GPT 并重写 eMMC 全部分区**, 板上现有数据全没; 烧录中不许断电
set -uo pipefail
cd "$(dirname "$0")/.."
PROJ="$(pwd)"

WAIT_MIN=0
REBOOT_LOADER=0
SDK="${RK3576_SDK:-$HOME/linux/rk3576_android/work/radxa-rk3576-android14}"
BOARD_ADB="${BOARD_ADB:-10.0.102.185:5555}"

while [ $# -gt 0 ]; do
  case "$1" in
    --wait)          WAIT_MIN="${2:-0}"; shift 2 ;;
    --reboot-loader) REBOOT_LOADER=1; shift ;;
    --sdk)           SDK="$2"; shift 2 ;;
    -h|--help)       sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "未知参数: $1"; exit 2 ;;
  esac
done

UT_DIR="$SDK/RKTools/linux/Linux_Upgrade_Tool/upgrade_tool_v2.30_for_linux"
UT="$UT_DIR/upgrade_tool"
IMG="$SDK/rockdev/Image-rk3576_lz200/update.img"

echo "== flash_update: $(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ) =="
echo "SDK : $SDK"
echo "IMG : $IMG"
[ -x "$UT" ] || { echo "✗ 找不到 upgrade_tool: $UT"; exit 1; }
[ -f "$IMG" ] || { echo "✗ 找不到 update.img: $IMG"; exit 1; }

# ---- 1) md5 门禁: 与 build/MD5SUMS.txt 登记值比对 ----
ACTUAL_MD5=$(md5sum "$IMG" | cut -d' ' -f1)
EXPECT_MD5=$(grep -E "^[0-9a-f]{32}  update\.img" "$PROJ/build/MD5SUMS.txt" 2>/dev/null | tail -1 | cut -d' ' -f1)
echo "md5 实际 : $ACTUAL_MD5"
echo "md5 登记 : ${EXPECT_MD5:-（MD5SUMS.txt 里没有 update.img 条目）}"
if [ -n "$EXPECT_MD5" ] && [ "$ACTUAL_MD5" != "$EXPECT_MD5" ]; then
  echo "✗ md5 与登记值不一致 —— 拒绝烧录（先确认产物或更新 build/MD5SUMS.txt）"
  exit 1
fi

# ---- 2) 等设备 (可选): 轮询 upgrade_tool ld ----
list_dev() { ( cd "$UT_DIR" && sudo -n ./upgrade_tool ld 2>&1 ); }
found=0
deadline=$(( $(date +%s) + WAIT_MIN * 60 ))
rebooted=0
while : ; do
  out=$(list_dev)
  if echo "$out" | grep -qE "connected\([1-9]"; then found=1; echo "$out" | tail -3; break; fi
  if [ "$WAIT_MIN" -le 0 ] || [ "$(date +%s)" -ge "$deadline" ]; then break; fi
  if lsusb | grep -qiE "18d1|2207|rockchip"; then
    echo "[$(date -u +%H:%M:%S)] lsusb 已看到 18d1/2207/rockchip, 但 upgrade_tool 还没认到"
    # 若此时是 Android adb 模式 (USB 口上的 adb 设备), 让它进 loader 再等
    if [ "$rebooted" -eq 0 ]; then
      SER=$(adb devices 2>/dev/null | awk '!/^List/ && $2=="device" && $1 !~ /:/ {print $1; exit}')
      if [ -n "$SER" ]; then
        echo "[$(date -u +%H:%M:%S)] 检测到 USB adb 设备 $SER, 执行 reboot loader"
        adb -s "$SER" shell reboot loader >/dev/null 2>&1 || true
        rebooted=1
      fi
    fi
  fi
  sleep 3
done

if [ "$found" != 1 ]; then
  echo "✗ 没有 rockusb 设备 (upgrade_tool ld = connected(0))"
  echo "  物理侧检查: ① 板子 Type-C **数据**线接到电脑 ② VMware → Removable Devices → 把 Rockchip/LKB3576 连到虚机"
  echo "  板上侧检查: 板子在 Android 时要先 'adb shell reboot loader' (本脚本可加 --reboot-loader)"
  exit 3
fi

# ---- 3) 烧 ----
echo "== 开始烧录: upgrade_tool uf update.img =="
( cd "$UT_DIR" && sudo -n ./upgrade_tool uf "$IMG" 2>&1 )
RC=$?
echo "FLASH_EXIT=$RC"

# ---- 4) 结果摘要 ----
if [ "$RC" -eq 0 ]; then
  echo "== 烧录返回 0; 等板子重启后按 docs/SESSION_HANDOFF.md §2 第 3 步验收 (不做任何 adb push) =="
else
  echo "== 烧录失败 (rc=$RC); 兜底: 先 'sudo ./upgrade_tool ef update.img' 再 'uf'; 再不行走 MaskROM (断电按住 MASKROM/UPDATE 键再上电, 枚举 2207:350e) =="
fi
exit "$RC"
