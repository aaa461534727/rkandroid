#!/usr/bin/env bash
# =============================================================================
# verify_tree.sh — 同步/叠加完之后的机器自检 (只读, 不改任何文件)
#
# 用途: 确认「源码树真的是本仓 default.xml 拉出来的 + 板级叠加层已生效」,
#       给换机器/换 AI 接手一个 0 成本的对错判据 (PASS/WARN/FAIL 计数)
# 在哪跑: 任意 Linux, 在源码树里或外面都行 (用 WS=... 指定源码树)
# 用法: WS=/path/to/源码树 bash scripts/verify_tree.sh   |   bash scripts/verify_tree.sh --help
# 依赖: git / python3 / md5sum (install_board.sh --check 走 install_board.sh 自己的依赖)
# 危险: 否 (纯只读; 不联网, 不动源码)
# =============================================================================
set -uo pipefail

BOARD="${BOARD:-$(cd "$(dirname "$0")/.." && pwd)}"
WS="${WS:-$HOME/rk3576_android14_ws}"
[ "${1:-}" = "--help" ] && { sed -n '3,10p' "$0"; exit 0; }

P=0; W=0; F=0
ok()   { P=$((P+1)); printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
warn() { W=$((W+1)); printf '  \033[33mWARN\033[0m  %s\n' "$*"; }
bad()  { F=$((F+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }

echo "== verify_tree  BOARD=$BOARD  WS=$WS"

# ---- 1. manifest 解析 --------------------------------------------------------
# 正常情况: .repo/manifests 就是本仓 (default.xml = 1234 project 快照)
# 特殊情况: 源码树是用原厂多文件 manifest 建的 (project 数不在 default.xml 里) ⇒ WARN, 不判 FAIL
if [ -f "$WS/.repo/manifests/default.xml" ]; then
    N=$(grep -c '<project' "$WS/.repo/manifests/default.xml" || true)
    EXPECT=$(grep -c '<project' "$BOARD/default.xml" 2>/dev/null || echo 1234)
    if [ "$N" = "$EXPECT" ]; then ok "manifest 已在位, project = $N (与本仓 default.xml 一致)"
    elif [ "$N" -gt 1000 ]; then warn "manifest project = $N (本仓 $EXPECT, 本仓可能更新过)"
    else warn "manifest project = $N —— 这棵树不是按本仓 default.xml 建的 (原厂多文件 manifest? 数不出来是正常的); 要按本仓复现请重跑 sync.sh"
    fi
else
    bad "没有 $WS/.repo/manifests/default.xml (还没 repo init)"
fi

# ---- 2. 关键目录 (源码真的在) -------------------------------------------------
for d in build/make kernel-6.1 external/wifi_driver device/rockchip \
         vendor/rockchip/common frameworks/base frameworks/opt/net/wifi packages/modules/Wifi; do
    [ -d "$WS/$d" ] && ok "源码目录在: $d" || bad "缺源码目录: $d (repo sync 没跑完?)"
done

# ---- 3. 板级叠加层 ------------------------------------------------------------
BT="$WS/device/rockchip/rk3576/rk3576_lz200"
if [ -f "$BT/AndroidProducts.mk" ] && [ -f "$BT/rk3576_lz200.mk" ]; then
    ok "lunch 目标在位: device/rockchip/rk3576/rk3576_lz200/"
    grep -q "rk3576_lz200-userdebug" "$BT/AndroidProducts.mk" \
        || warn "AndroidProducts.mk 里没有 rk3576_lz200-userdebug 字样"
else
    bad "缺板级目录 $BT (install_board.sh --push 没跑?)"
fi
[ -f "$WS/kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-lz200-android.dts" ] \
    && ok "内核 DTS 在位: rk3576-lz200-android.dts" || bad "缺 rk3576-lz200-android.dts"
grep -qF 'rk3576-lz200-android.dtb' "$WS/kernel-6.1/arch/arm64/boot/dts/rockchip/Makefile" 2>/dev/null \
    && ok "kernel Makefile 已登记 rk3576-lz200-android.dtb" \
    || bad "kernel Makefile 没登记 dtb (编译会报无此目标)"

# ---- 4. src 与源码树一致 (调 install_board.sh --check) -------------------------
if [ -x "$BOARD/scripts/install_board.sh" ] || [ -f "$BOARD/scripts/install_board.sh" ]; then
    if out=$(SDK="$WS" bash "$BOARD/scripts/install_board.sh" --check 2>&1); then
        ok "src ⇄ 源码树 全部一致 (install_board.sh --check == OK)"
    else
        bad "src 与源码树不一致 —— 跑: SDK=$WS bash $BOARD/scripts/install_board.sh --push"
        printf '%s\n' "$out" | grep -E 'DIFF|MISS' | head -8 | sed 's/^/         /'
    fi
else
    warn "找不到 scripts/install_board.sh, 跳过一致性检查"
fi

# ---- 5. 磁盘 / 产物 -----------------------------------------------------------
AVAIL=$(df -BG --output=avail "$WS" 2>/dev/null | tail -1 | tr -dc '0-9')
if [ -n "${AVAIL:-}" ]; then
    if [ "$AVAIL" -ge 130 ]; then ok "磁盘剩余 ${AVAIL}G (够编 out/, 约需 115G)"
    elif [ "$AVAIL" -ge 60 ];  then warn "磁盘剩余 ${AVAIL}G (不够全量编, 可先删 out/ 里旧产物)"
    else bad "磁盘剩余 ${AVAIL}G (编不了, 清理或换盘)"; fi
fi
IMG="$WS/rockdev/Image-rk3576_lz200/update.img"
if [ -f "$IMG" ]; then
    ok "已有产物 $(du -h "$IMG" | cut -f1)  $IMG  md5=$(md5sum "$IMG" | cut -d' ' -f1)"
else
    echo "  ----   还没有 update.img (未编译过, 正常)"
fi

# ---- 汇总 --------------------------------------------------------------------
echo
echo "== 汇总: PASS=$P  WARN=$W  FAIL=$F"
if [ "$F" -gt 0 ]; then
    echo "   ❌ 有 FAIL —— 先修上面 FAIL 项再编译 (否则编出来的固件缺功能)"
    exit 1
fi
echo "   ✅ 可以编译: cd $WS && source build/envsetup.sh && lunch rk3576_lz200-userdebug && ./build.sh -A -u -J6"
exit 0
