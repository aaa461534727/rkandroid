#!/usr/bin/env bash
# =============================================================================
# sync.sh — 一键把「源码定义」变成「能编译的源码树」
#
# 用途: repo init (读本仓 default.xml) → repo sync (1234 project, ~109G) → 应用 src/ 板级叠加层
# 在哪跑: 任意装好 repo/git 的 Linux (本机 dengbaowen-ubuntu / 服务器 220 都行), 普通用户, 不要 sudo
# 用法:
#   WS=~/rk3576_android14_ws JOBS=8 bash scripts/sync.sh          # 全量: 首次用
#   bash scripts/sync.sh --no-sync                                # 只 init + 叠加 src (源码已在本地时)
#   WS=/已有/源码树 bash scripts/sync.sh --no-sync --skip-board    # 只重读 manifest
#   WS=... bash scripts/sync.sh --force-sync                      # 源码树有脏改动时强制重置 (慎用)
# 依赖: git / repo / rsync / python3 / md5sum ; 磁盘 ≥ 260G (源码 109G + 产物 115G)
# 危险: repo sync 会按 manifest 重置各 project (未提交改动会丢); install_board.sh 会覆盖同名板级文件
# =============================================================================
set -euo pipefail

BOARD="${BOARD:-$(cd "$(dirname "$0")/.." && pwd)}"
WS="${WS:-$HOME/rk3576_android14_ws}"
JOBS="${JOBS:-8}"
DO_SYNC=1
SKIP_BOARD=0
FORCE=()

for a in "$@"; do
    case "$a" in
        --no-sync)    DO_SYNC=0 ;;
        --skip-board) SKIP_BOARD=1 ;;
        --force-sync) FORCE+=(--force-sync) ;;
        -j*)          JOBS="${a#-j}" ;;
        -h|--help)    sed -n '3,16p' "$0"; exit 0 ;;
        *) echo "未知参数: $a (看 --help)" >&2; exit 2 ;;
    esac
done

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ---- 0. 环境 ----------------------------------------------------------------
say "环境自检"
for t in git rsync python3 md5sum; do command -v "$t" >/dev/null || die "缺命令: $t"; done
command -v repo >/dev/null || die "缺 repo 工具: mkdir -p ~/bin && curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo && chmod a+x ~/bin/repo && export PATH=~/bin:\$PATH"
[ -f "$BOARD/default.xml" ] || die "本仓不完整: 找不到 $BOARD/default.xml (是不是 clone 错了目录?)"
mkdir -p "$WS"
echo "  定义仓 : $BOARD"
echo "  源码树 : $WS"
echo "  磁盘   : $(df -h "$WS" | tail -1 | awk '{print $4" 可用 / "$2}')"
echo "  内存   : $(free -g | awk 'NR==2{print $2"G total, "$7"G 可用"}')"
echo "  CPU    : $(nproc) 核, repo sync -j$JOBS"

# ---- 1. repo init (幂等; 读的是本仓 default.xml) -----------------------------
say "repo init (manifest = $BOARD/default.xml)"
cd "$WS"
if [ -d .repo ]; then
    echo "  已有 .repo, 重新指向本仓并重读 manifest"
fi
repo init -u "file://$BOARD" -b main 2>&1 | tail -3

# ---- 2. repo sync ----------------------------------------------------------
if [ "$DO_SYNC" = 1 ]; then
    say "repo sync -j$JOBS (1234 project, ~109 GB, 首次很久, 断了重跑即可续传)"
    repo sync -j"$JOBS" --no-clone-bundle "${FORCE[@]}"
else
    say "跳过 repo sync (--no-sync)"
fi

# ---- 3. 应用板级叠加层 -------------------------------------------------------
if [ "$SKIP_BOARD" = 1 ]; then
    say "跳过 src 叠加层 (--skip-board)"
else
    say "应用板级叠加层 (src/ → 源码树)"
    SDK="$WS" bash "$BOARD/scripts/install_board.sh" --push
fi

# ---- 4. 自检 + 下一步 --------------------------------------------------------
say "自检"
bash "$BOARD/scripts/verify_tree.sh" || echo "  (自检有告警, 看上面几行; 不影响继续)"

cat <<EOS

== 下一步 (编译) ==
  cd $WS
  source build/envsetup.sh
  lunch rk3576_lz200-userdebug
  ./build.sh -A -u -J6                  # 首次全量; 改了内核/DTS 用 ./build.sh -K -A -u -J6
  bash $BOARD/scripts/check_firmware_content.sh   # 出固件前门禁 (必须全 OK)
  bash $BOARD/scripts/flash_update.sh --wait 60   # USB 烧录
EOS
