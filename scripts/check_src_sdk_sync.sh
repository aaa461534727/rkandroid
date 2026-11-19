#!/bin/bash
# =============================================================================
# check_src_sdk_sync.sh — 校验 src/<应用>/ 与 sdk/ 是否逐文件一致
#
# 规矩: 顶层 AGENTS.md §23.5
#   编译和出固件只在 sdk/ 里做 ⇒ src/ 改了 sdk/ 没改 = 编出来还是旧的;
#   在 sdk/ 里调试改了不回写 src/ = 换机器就丢。
#
# 用法:
#   bash scripts/check_src_sdk_sync.sh              # 校验全部应用
#   bash scripts/check_src_sdk_sync.sh <应用名>      # 只校验一个
#
# 退出码: 0 = 全部一致; 1 = 有不一致 (或 sdk 缺文件); 2 = 用法/环境错误
# =============================================================================
set -uo pipefail

PROJ_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC_DIR="$PROJ_DIR/src"
SDK_DIR="$PROJ_DIR/sdk"

[ -d "$SRC_DIR" ] || { echo "ERR 找不到 $SRC_DIR"; exit 2; }
[ -d "$SDK_DIR" ] || { echo "ERR 找不到 $SDK_DIR (SDK 还没拉? 见 sdk/README.md)"; exit 2; }

# 本项目 SDK 是【仓外挂载】 (100G 量级 Android 树, 见 sdk/README.md) ⇒ sdk/ 下没有实体目录,
# 逐文件对齐由 install_board.sh 负责 (它知道 SDK 树在哪 + 会补内核 Makefile 的 dtb 行)。
if [ -x "$PROJ_DIR/scripts/install_board.sh" ] && [ -z "$(ls -d "$SDK_DIR"/*/ 2>/dev/null)" ]; then
    echo "sdk/ 无实体目录 ⇒ 走仓外 SDK 校验: scripts/install_board.sh --check"
    exec bash "$PROJ_DIR/scripts/install_board.sh" --check
fi

APPS=()
if [ $# -ge 1 ]; then
    APPS=("$1")
else
    for d in "$SRC_DIR"/*/; do
        [ -d "$d" ] && APPS+=("$(basename "$d")")
    done
fi

[ ${#APPS[@]} -gt 0 ] || { echo "ERR $SRC_DIR 下没有任何应用目录"; exit 2; }

total=0; bad=0
for app in "${APPS[@]}"; do
    adir="$SRC_DIR/$app"
    if [ ! -d "$adir" ]; then
        echo "MISS  应用目录不存在: src/$app"
        bad=$((bad+1)); continue
    fi

    files=0; oos=0
    while IFS= read -r -d '' f; do
        rel=${f#./}
        files=$((files+1)); total=$((total+1))
        a=$(md5sum "$adir/$rel" 2>/dev/null | cut -d' ' -f1)
        b=$(md5sum "$SDK_DIR/$rel" 2>/dev/null | cut -d' ' -f1)
        if [ -z "$b" ]; then
            echo "MISSING-IN-SDK  $app/$rel   (src=${a:0:8}  sdk=不存在)"
            oos=$((oos+1)); bad=$((bad+1))
        elif [ "$a" != "$b" ]; then
            echo "OUT-OF-SYNC     $app/$rel   (src=${a:0:8}  sdk=${b:0:8})"
            oos=$((oos+1)); bad=$((bad+1))
        fi
    done < <(cd "$adir" && find . -type f ! -path './bak/*' ! -name 'README.md' -print0)

    if [ "$files" -eq 0 ]; then
        echo "EMPTY  $app — 没有任何待同步文件 (只放了 README/bak?)"
    elif [ "$oos" -eq 0 ]; then
        echo "OK     $app — $files 个文件全部一致"
    else
        echo "FAIL   $app — $oos/$files 个文件不一致"
    fi
done

echo "----"
echo "合计: $total 个文件, 不一致/缺失 $bad 处"
if [ "$bad" -gt 0 ]; then
    echo "❌ 未通过 — 先判定哪边是权威 (通常 src 以提交历史为准), 同步后再跑一次"
    echo "   src → sdk : rsync -a --exclude=bak/ --exclude=README.md src/<应用>/ sdk/"
    echo "   sdk → src : rsync -a --exclude=bak/ sdk/<相对路径> src/<应用>/<相对路径>"
    exit 1
fi
echo "✅ 全部一致 (src ↔ sdk)"
exit 0
