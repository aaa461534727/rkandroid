# rk3576_android14/docs/ADAPT_ROCKCHIP_ANDROID.md — 路线 B: 瑞芯微官方 Android 14 BSP + lz200 板级自适配

> **定稿**: 2026-11-17 (主人拍板: 「用瑞芯微官方给的安卓源码来结合当前 ubuntu 的源码来自己适配」)
> **姊妹篇**: `docs/BUILD_ANDROID.md` = **路线 A** (NEARDI 官方 Android 14 整包, 邮件申请), 保留作兜底
> **本文件每条"事实"都标了来源**: `实测` (本机/板子跑过) · `gitlab-api` (公共接口查到) · `wiki` (官方页面) · `待验证`
> 状态/待办看 `docs/project.json`; 现场流水看 `docs/WORKLOG.md`

---

## 1. 结论 (TL;DR)

| # | 结论 | 依据 |
|---|---|---|
| 1 | 主选 **路线 B**: 拉 Rockchip 官方 Android 14 BSP (Radxa 维护的公共 manifest), **自己建 lz200 板级** | 主人拍板 + 源码可匿名获取 (实测) |
| 2 | 板级只改 **3 处 + 1 个不动**: 内核 DTS / 内核 config (可选) / `device/rockchip/rk3576/rk3576_lz200/`; **u-boot 不动** | 见 §6 |
| 3 | 内核 DTS 是 **flat 布局** (`arch/arm64/boot/dts/rockchip/rk3576-*.dts`), 与 Ubuntu SDK 的 `RK3576/neardi/` 子目录不同 → 拷贝 + 改 1 处 include 路径 | gitlab-api + 实测 |
| 4 | BSP 的 `rockchip_defconfig` **已含 binder/ashmem** (`CONFIG_ANDROID_BINDER_IPC/BINDERFS/ASHMEM=y`) → **不需要** 额外的 `android-14.config` (该文件在此 BSP 里不存在) | gitlab-api 取原文 |
| 5 | **无线 (SeekWave SV6160) 没有驱动源码** → Android 首版按 **有线以太网 + USB adb** 交付; 无线需向 NEARDI 索取驱动 | 实测 + gitlab-api |
| 6 | 磁盘 268G 对 1234 个项目 + out **偏紧** → `repo init --depth=1`; 编译前留 ≥ 90G; 不够就扩 vmdk 到 400~500G | 实测 + 估算 |

---

## 2. 两条路线对比

| 维度 | **A: NEARDI 官方整包** (BUILD_ANDROID.md) | **B: Rockchip BSP 自适配** (本文件, 主选) |
|---|---|---|
| 源码来源 | `support@neardi.com` 邮件申请 `neardi-3576-android-14.tar.gz` | `gitlab.com/rockchip_android14_rk3576` (公共) + Radxa manifest |
| 板级 | 官方现成 target `rk3576_neardi_lz200-userdebug` | **自己建** `rk3576_lz200` (DTS/config/分区/板级 mk) |
| 获取确定性 | 等回信, 不确定 (无公开直链) | **已实测可匿名拉** (`git ls-remote` 通, manifest 已落盘) |
| 工作量 | 几乎零板级工作 | 同步 1234 个项目 (耗时/占盘) + 板级自测 |
| 风险 | 拿不到包就停摆 | 镜像/版本漂移、板级细节漏项 (WiFi/摄像头/屏) |
| 定位 | **兜底** (B 走不通就转 A) | **当前执行路线** |

> 两条路线产物一致: `rockdev/Image-<target>/update.img` → `upgrade_tool uf` 烧录。

---

## 3. 源码从哪来 (已核实, 不是猜测)

### 3.1 manifest 位置

```
仓库: radxa/manifests
分支: Android14_RK3576_Radxa_rk6
文件: rockchip-u-release.xml  (→ include Android14_RK3576_Radxa_rk6.xml
                              → include commit/manifest_rk3576_radxa_rkr6.xml)
```

- **下载方式**: `https://codeload.github.com/radxa/manifests/tar.gz/refs/heads/Android14_RK3576_Radxa_rk6` (实测 **200**, 221K)
  - 本机 `github.com` 的 git 协议**不通** (`GnuTLS -54`), 只能走 `codeload` / `api.github.com`
- **remote 全部指向** `https://gitlab.com/rockchip_android14_rk3576` (`<remote name="aosp|ohd|rk|rk29|rk78_mirror|rk_legacy" fetch="...">`)
- **仓库性质 (说清楚)**: 这是**社区镜像组** (GitLab 公共组, `visibility=public`), manifest 由 Radxa 维护; 代码内容 = **Rockchip 官方 Android 14 BSP** (AOSP 镜像 + Rockchip 中间件), **不含 NEARDI 定制层** (所以板级要自己适配)

### 3.2 匿名可达性 (实测)

```bash
# 内核 (大项目) — 实测有两条分支
$ git ls-remote --heads https://gitlab.com/rockchip_android14_rk3576/rk/kernel
343ed2c8...  refs/heads/master
343ed2c8...  refs/heads/radxa_android14_rkr6

# AOSP 镜像抽样 — 实测 OK
platform/build/build        → 4669f81b...  refs/heads/radxa_andorid14_rkr6
platform/frameworks/base    → 89259532...  refs/heads/radxa_android14_rkr6
platform/system/core        → 30c42784...  refs/heads/radxa_android14_rkr6
```

### 3.3 规模 (merged manifest 实测)

| 项 | 数值 | 说明 |
|---|---|---|
| 合并后 project 总数 | **1234** | `repo manifest -o` 输出里 `<project` 计数 |
| 源 manifest project 数 | 1291 | 顶层 58 + `commit/manifest_rk3576_radxa_rkr6.xml` 1233 |
| 关键项目 (pinned SHA) | 见下表 | manifest 锁定 revision, 可复现 |

| 路径 | gitlab 项目 | pinned revision | 用途 |
|---|---|---|---|
| `kernel-6.1` | `rk/kernel` | `343ed2c8a9b4b3817d99e5a1c34de61c69c3a7d8` | 内核 6.1 (Android) |
| `u-boot` | `rk/u-boot` | `bf2c7da538b0b46aea9512a10a6a23e92abf686d` | u-boot |
| `device/rockchip/common` | `rk/device/rockchip/rksdk` | `9e6765fddae867115406a90f7aa6ec0dace3ac7f` | 编译脚本 `build.sh` / 分区工具 |
| `device/rockchip/rk3576` | `rk/device/rockchip/rk3576/rk3576` | `e6f577e7e6efa0a47e29197641e0f6fe0b6f3ac8` | RK3576 板级目录 |

### 3.4 备选 manifest (Radxa 分支失效时)

- `jlckfb/TaishanPi-manifests` 分支 **`android14/tspi-3-260416`** (repo 存在, 默认分支 `main`; `api.github.com` 实测可查)
- 其它厂商 (ArmSoM 等) 的 RK3576 Android 14 manifest 也可作候选, 但都要**重新核对内核分支与板级目录**。

---

## 4. 本机落地状态 (2026-11-17 实测, 已做完的部分)

### 4.1 repo 工具 (有个坑: googlesource 不通)

| 问题 | 现象 (实测) | 解决 |
|---|---|---|
| `repo` 启动器要从 `gerrit.googlesource.com` 下载自身 | `curl` 该域名 **000 / 20s 超时**; `repo init` 报 `Cannot get .../clone.bundle` | 从 **GitHub codeload** 拉 `GerritCodeReview/git-repo` **tag v2.54** 源码, 本地建 git 仓后作为 `REPO_URL` |
| launcher 校验 tag 签名 | `no signature found` | `repo init --no-repo-verify` (本地 vendored 源码, 无签名) |

> 顺带记一笔: `apt install repo` (2.17.3) 装的**也是 launcher**, 一样会去 googlesource ⇒ 已弃用 (装着不影响)。

**已落盘**:

```
~/linux/rk3576_android/tmp/repo-src/          # vendored repo v2.54 (含 .git, 已打 annotated tag v2.54)
~/linux/rk3576_android/tmp/git-repo-v2.54.tgz # 原始包 (284K)
~/linux/rk3576_android/work/manifests/        # radxa manifest 快照 (本地 git 仓, main 分支)
~/linux/rk3576_android/work/radxa-rk3576-android14/   # 编译树 (repo init 已完成, 正在局部 sync)
```

**以后用这个 repo 命令** (别用 `/usr/bin/repo`, 它还是会去 googlesource):

```bash
export PATH=$HOME/linux/rk3576_android/tmp/repo-src:$PATH
cd ~/linux/rk3576_android/work/radxa-rk3576-android14
repo --version        # 应报 repo launcher version 2.54
```

### 4.2 `repo init` 实际用过的命令

```bash
W=$HOME/linux/rk3576_android
export PATH=$W/tmp/repo-src:$PATH
cd $W/work/radxa-rk3576-android14

# 说明: repo 2.54 的 `repo sync` 不再接受 --depth (实测报 "no such option: --depth")
#       深度必须写在 init 上
repo init --no-repo-verify --depth=1 \
  -u "file://$W/work/manifests" -b main -m rockchip-u-release.xml
```

> 为什么 `-u file://...`: manifest 走 codeload 快照, 避免 `github.com` git 协议不通; 里面的 remote 仍是 gitlab, 源码照常从 gitlab 拉。
> `rm -rf .repo` 重来也无所谓, 不会删已 checkout 的项目目录。

### 4.3 局部 sync 验证 (先小后大)

先只拉 3 个关键小项目, 验证 gitlab 拉取链路 + linkfile 是否正常:

```bash
repo sync -c --no-tags -j4 \
  device/rockchip/rk3576 device/rockchip/common u-boot
```

- 日志: `rk3576_android14/build/logs/20261117-1123-repo-sync-partial-ok.log`
- **结果 (实测)**: ✅ `EXIT=0`, 耗时 **63 秒**, 树体积 **221M**; `build.sh` / `device/rockchip/common/build/rockchip/build.sh` / `device/rockchip/rk3576/rk3576_u/BoardConfig.mk` / `u-boot/configs/rk3576_defconfig` 全部到位 (说明 gitlab 匿名拉取 + linkfile 正常)
- 首次失败记录 (留证): `build/logs/20261117-1121-repo-sync-partial-fail.log` → 原因 `--depth` 参数位置错, 已改 `repo init --depth=1`
- **全量同步已启动**: `build/logs/20261117-1123-repo-sync-full.log` (1234 个项目)

---

## 5. P0: 全量同步 (待执行)

```bash
W=$HOME/linux/rk3576_android
export PATH=$W/tmp/repo-src:$PATH
cd $W/work/radxa-rk3576-android14

# 全量: 1234 个项目, 预计 6~20 小时 (取决于 gitlab 匿名带宽)
# -j4 起 (匿名别开太大, gitlab API 已实测会 429; git 协议本身不 429 但并发大会拖慢)
repo sync -c --no-tags -j4 2>&1 | tee -a \
  /home/dengbaowen/freebuf/hclinux/rk3576_android14/build/logs/$(date -u +%Y%m%d-%H%M)-repo-sync-full.log
```

**中断/恢复**: 直接重跑同一条 `repo sync` (repo 增量续传, 已 checkout 的跳过)。

**验收 (全部满足才算同步完成)**:

| 检查 | 命令 | 期望 |
|---|---|---|
| 项目目录数 | `repo list 2>/dev/null \| wc -l` | 接近 1234 |
| 内核 DTS 模板 | `ls kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-evb1-v10.dts` | 存在 |
| 板级模板 | `ls device/rockchip/rk3576/rk3576_u/BoardConfig.mk` | 存在 |
| 编译脚本 | `ls build.sh device/rockchip/common/build/rockchip/build.sh` | 存在 (build.sh 是 linkfile) |
| lunch 可用 | `source build/envsetup.sh && lunch` | 列表含 `rk3576_u-userdebug` 等 |

**磁盘预算 (估算, 非实测)**:

| 阶段 | 估算占用 | 备注 |
|---|---|---|
| 源码树 (depth=1) | 90~120G | 全量历史会到 170G+; 所以必须 depth |
| `.repo` (depth=1) | 25~40G | 浅克隆对象库 |
| `out/` (userdebug 单 target) | 80~120G | 不开 ccache |
| 合计 | **195~280G** | 现有 **268G** → 临界; 编译前先看 `df`, 不够扩 vmdk |

---

## 6. P1: 板级适配 (3 处改动 + 1 处不动)

### 6.0 总表

| # | 位置 | 改什么 | 依据 |
|---|---|---|---|
| 1 | `kernel-6.1/arch/arm64/boot/dts/rockchip/` | 拷 12 个 lz200 fragment + 新建 `rk3576-lz200-android.dts` + Makefile 加 1 行 | 内核 DTS 是 flat 布局 (gitlab-api) |
| 2 | `kernel-6.1/arch/arm64/configs/` | 默认**不加**; 缺外设时新增 `rk3576_lz200.config` fragment | `rockchip_defconfig` 已含 binder/ashmem |
| 3 | `device/rockchip/rk3576/rk3576_lz200/` | **新建板级目录** (照 `rk3576_u/` 复制, 改名/改 DTS/改分区) | 板级目录决定 lunch 与出厂配置 |
| 4 | `u-boot/` | **不动** (用 `rk3576_defconfig`) | Ubuntu SDK u-boot 只有通用 dts (实测) |

### 6.1 内核 DTS (flat 布局)

**事实** (gitlab-api 实测):

- BSP 内核 DTS 在 `kernel-6.1/arch/arm64/boot/dts/rockchip/` **平铺**, 例如 `rk3576-evb1-v10.dts`、`rk3576-rk806.dtsi`、`rk3576-android.dtsi`
- **没有** `RK3576/neardi/` 子目录 (Ubuntu SDK 才有)
- `arch/arm64/boot/dts/rockchip/Makefile` **显式列 dtb** (240~259 行是 rk3576 段), 新 dts 必须登记

> ✅ **已落地 (2026-11-17)**: 13 个 `.dtsi` + 新 `rk3576-lz200-android.dts` 已在 `src/kernel-6.1/arch/arm64/boot/dts/rockchip/`,
> 13 个文件 md5 与 220 的 Ubuntu SDK **逐一核对一致**; `../rk3576-rk806.dtsi` 已改成平铺 `rk3576-rk806.dtsi`。
> 推进 SDK 树用 `bash scripts/install_board.sh` (会顺带幂等补内核 `Makefile` 的 dtb 行)。
> 下面的手工命令留作**来源说明 / 复现用**。

**做法**:

```bash
K=$HOME/linux/rk3576_android/work/radxa-rk3576-android14/kernel-6.1
D=$K/arch/arm64/boot/dts/rockchip

# 1) 从 220 的 Ubuntu SDK 拷 12 个 fragment 到 flat 目录 (保留原名, 减少改动)
rsync -av bob@10.0.100.220:~/rk3576/rk3576_linux/kernel/arch/arm64/boot/dts/rockchip/RK3576/neardi/rk3576-neardi-*.dtsi \
  $D/

# 2) 唯一需要改的 include: 子目录写法 ../rk3576-rk806.dtsi → 平铺写法
sed -i 's#\.\./rk3576-rk806\.dtsi#rk3576-rk806.dtsi#' $D/rk3576-neardi-lz200.dtsi

# 3) 新建 Android 顶层 dts (与 Ubuntu cs-lz200-linux.dts 的唯一区别: rk3576-linux.dtsi → rk3576-android.dtsi)
cat > $D/rk3576-lz200-android.dts <<'EOF'
// SPDX-License-Identifier: (GPL-2.0+ OR MIT)
/*
 * NEARDI LKB3576 (board level = neardi lz200) — Android 14
 * 来源: Ubuntu SDK cs-lz200-linux.dts, 把 rk3576-linux.dtsi 换成 rk3576-android.dtsi
 */

/dts-v1/;

#include "rk3576.dtsi"
#include "rk3576-neardi-lz200.dtsi"
#include "rk3576-android.dtsi"

#include "rk3576-neardi-lz200-hdmi.dtsi"
#include "rk3576-neardi-lz200-gmac.dtsi"
#include "rk3576-neardi-lz200-wifibt.dtsi"
#include "rk3576-neardi-lz200-sound-ctl.dtsi"
#include "rk3576-neardi-lz200-full-typec-phy.dtsi"
#include "rk3576-neardi-lz200-misc-devices.dtsi"
#include "rk3576-neardi-lz200-cam-dcphy0-comb.dtsi"
#include "rk3576-neardi-lz200-cam-dphy1-comb.dtsi"
#include "rk3576-neardi-lz200-cam-dphy3-comb.dtsi"
#include "rk3576-neardi-lz200-mipi-dsi-10.1-screen.dtsi"

/ {
	model = "Rockchip RK3576 NEARDI LZ200 Board (Android 14)";
	compatible = "rockchip,rk3576-neardi-lz200-v2", "rockchip,rk3576";
};
EOF

# 4) 登记 dtb: 在 rk3576 段任意位置加一行 (Makefile 240~259 行附近)
#    dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3576-lz200-android.dtb
#    ⚠️ 用编辑器改, 别用 sed 拼 (避免把 dtb- 拆坏); 写完核对:
grep -n "rk3576-lz200-android" $D/Makefile
```

> 为什么要登记: 内核 dts Makefile 是**显式列表** (`dtb-$(CONFIG_ARCH_ROCKCHIP) += ...`), 不登记则 `make rk3576-lz200-android.img` 直接报无此目标。

**fragment 事实 (实测, 来自 220)**:

| 事实 | 值 |
|---|---|
| fragment 总数 | **13 个 `.dtsi`**: `rk3576-neardi.dtsi`(主) + `-input-keymap` + `lz200.dtsi`(主) + `-hdmi` `-gmac` `-wifibt` `-sound-ctl` `-full-typec-phy` `-misc-devices` `-cam-dcphy0-comb` `-cam-dphy1-comb` `-cam-dphy3-comb` `-mipi-dsi-10.1-screen` |
| 体积 | 合计 **88K** |
| 内部 include | 只有 `"rk3576-neardi.dtsi"`、`"rk3576-neardi-input-keymap.dtsi"`、`"../rk3576-rk806.dtsi"` + `dt-bindings/*` |
| 覆盖 model/compatible | **没有** (所以顶层 dts 自己写) |

### 6.2 内核 config

**事实**: BSP 的板级默认配置链 = `rockchip_defconfig` + `rk3576.config` (gitlab-api 取 `BoardConfig.mk`):

```make
PRODUCT_KERNEL_CONFIG += rk3576.config
PRODUCT_KERNEL_ARCH ?= arm64
PRODUCT_KERNEL_DTS ?= rk3576-evb1-v10
PRODUCT_UBOOT_CONFIG ?= rk3576_defconfig
```

**Android 所需开关已在 `rockchip_defconfig`** (gitlab-api 实测行号):

```
CONFIG_ASHMEM=y                    (917)
CONFIG_ANDROID_BINDER_IPC=y        (988)
CONFIG_ANDROID_BINDERFS=y          (989)
```

→ **`android-14.config` 不存在也不必加** (该 BSP 里 `android-14/13/12/11.config` 全是 404)。

**板级外设策略**:

1. 首版直接 `rockchip_defconfig + rk3576.config` 编译 (不改 config);
2. 上板发现某外设不工作 (网口/USB/HDMI/DSI/摄像头/RTC/风扇), 再用 `scripts/diffconfig` 对 Ubuntu 的 `cs_lz200_linux_defconfig` 找出对应 `CONFIG_*`, 写进 **`arch/arm64/configs/rk3576_lz200.config`** (fragment), 在板级 `BoardConfig.mk` 里 `PRODUCT_KERNEL_CONFIG += rk3576_lz200.config`。

> 有线侧已有实证: 板上 dmesg 显示 `rk_gmac-dwmac` **eth0 (2a220000) + eth1 (2a230000) 均 probe 成功** (双千兆), 取证 `logs/20261117-1131-rk3576-lkb3576-wifi-eth-check.log` ⇒ 用 `rockchip_defconfig` 默认的 STMMAC 即可, 不需要额外 fragment。

> 不要把 Ubuntu 的 8088 行 defconfig 整个搬过来: Android 的内核配置基线不同 (GKI/ashmem/binder/DMABUF 等), 整搬会把 Android 必需项冲掉。

### 6.3 `device/rockchip/rk3576/rk3576_lz200/` (新建板级) — ✅ 已落地在 `src/`

**已做 (2026-11-17, 见 `rk3576_android14/src/device/rockchip/rk3576/rk3576_lz200/`)**:

```bash
cp -a device/rockchip/rk3576/rk3576_u  device/rockchip/rk3576/rk3576_lz200
mv rk3576_lz200/rk3576_u.mk rk3576_lz200/rk3576_lz200.mk
```

实际改动 (与模板 `rk3576_u` 的差异, 已核对):

| 文件 | 实际改成什么 | 为什么 |
|---|---|---|
| `BoardConfig.mk` | `PRODUCT_KERNEL_DTS := rk3576-lz200-android`; `BOARD_SUPER_PARTITION_SIZE := 6442450944` (6GiB); 删 `PRODUCT_KERNEL_CONFIG += pcie_wifi.config`; `BOARD_GSENSOR_MXC6655XA_SUPPORT := false` | DTS 名要对上 §6.1; 不设 super 则 `Partitions.mk` 默认 ~3.04G, AOSP14 userdebug 偏紧; 板载无线是 SDIO SV6160 不是 M.2 PCIe; 板上无 MXC6655XA |
| `AndroidProducts.mk` | `PRODUCT_MAKEFILES := $(LOCAL_DIR)/rk3576_lz200.mk`; `COMMON_LUNCH_CHOICES := rk3576_lz200-userdebug / rk3576_lz200-user` | lunch 名即 target 名 |
| `rk3576_lz200.mk` | `include device/rockchip/rk3576/rk3576_lz200/BoardConfig.mk`; `PRODUCT_NAME/DEVICE := rk3576_lz200`; `PRODUCT_MODEL := LKB3576` | 否则会 include 回 `rk3576_u` 的板级配置 |
| `config.cfg` | **原样照抄 `rk3576_u`** (二进制烧录配置, 里面的 `rockdev\Image-rk3566_rgo\...` 字符串只是 upgrade_tool 界面显示名) | 真正的分区大小来自构建期生成的 `parameter.txt` (见 §6.5) |
| 其余 (`sepolicy/` `bt_vendor.conf` `media_profiles_default.xml` `dt-overlay.in` `ota/`) | 原样继承 | 通用 |
| 传感器开关 (`BOARD_GRAVITY/COMPASS/GYROSCOPE/PROXIMITY/LIGHT_SENSOR_SUPPORT`) | 保持 true (与模板一致) | 顶层 `device/rockchip/rk3576/BoardConfig.mk:81` 会 `:= true` 覆盖, 强行改 false 没意义; 板子无 sensor 时 HAL 报错但不影响开机 |

**同步机制 (本项目硬规矩, §23)**: 改动只写在 `src/`, 由脚本推进 SDK 树:

```bash
bash scripts/install_board.sh          # src → SDK (拷 dts + 补 Makefile dtb 行 + rsync 板级目录)
bash scripts/install_board.sh --check  # 只比 md5, 不一致 exit 1  ← 每次编译前跑
bash scripts/install_board.sh --pull   # SDK 里调通了拉回 src
```

> **为什么不在 SDK 里直接改**: SDK 树在仓库根之外, `repo sync` 会覆盖已跟踪文件 (内核 `Makefile` 就是被跟踪的);
> `src/` 是唯一可信副本, SDK 只是编译场。

**git 管理**: SDK 树内**不 commit 不 push** (公共镜像, 只读用); 要留临时分支就 `repo start lz200 device/rockchip/rk3576 kernel-6.1`, 但以 `src/` 为准。

### 6.4 u-boot (不动)

**事实 (实测, 来自 220 的 Ubuntu SDK)**:

- `u-boot/arch/arm/dts/` 只有通用 `rk3576-evb.dts` / `rk3576-tb.dts` / `rk3576.dtsi` / `rk3576-u-boot.dtsi`
- `u-boot/configs/` 里有 `rk3576_defconfig` (+ 各种 `rk3576-*.config` 片段)
- 板级变量 `PRODUCT_UBOOT_CONFIG ?= rk3576_defconfig`

→ Android BSP 用同一套通用 u-boot 即可; **DDR/loader 用 `rkbin` 现成 bin**。只有开机 logo、特殊 DDR 颗粒或安全启动才需要动 u-boot。

### 6.5 分区表 / 存储

| 项 | 事实 | 影响 |
|---|---|---|
| 板子 eMMC | **29G 可用** (串口实测, 当前 Ubuntu 用 5.4G) | `super` 别按 64G/128G 配 |
| `parameter.txt` 从哪来 | **构建期生成**: `device/rockchip/common/build/rockchip/RebuildParameter.mk` 用 `scripts/parameter_tools/parameter.in` + 板级 `BoardConfig.mk` 的 `*_PARTITION_SIZE` 变量拼出 `mtdparts=rk29xxnand:...` | 所以**不用手写分区表**; 改 super 大小就改 `BOARD_SUPER_PARTITION_SIZE` |
| `config.cfg` 是什么 | upgrade_tool 的**烧录配置** (二进制, 列 image→分区映射); 内部路径字符串只是界面显示名 | 照抄 `rk3576_u` 即可; 真正的分区大小以 `parameter.txt` 为准 |
| super 默认值 (无 `parameter.txt`) | `Partitions.mk:63/65` → `BUILD_WITH_GO_OPT` 决定 **2516582400 / 3263168512** (~2.3G / ~3.04G) | 我们显式给 **6GiB**, AOSP14 tablet userdebug 约需 4G |
| 动态分区 | `BOARD_SUPER_PARTITION_GROUPS := rockchip_dynamic_partitions` (`DynamicPartitions.mk:33`), `BOARD_ROCKCHIP_DYNAMIC_PARTITIONS_SIZE = super - 4M` | super 不够时 `build_super_image` 直接报错 |
| 烧录会重写 GPT | `upgrade_tool uf update.img` 按 `parameter.txt` 重建分区 | **Ubuntu 会被覆盖**, 回滚只能重烧 Ubuntu `update.img` |

---

## 7. P2: 编译 / 烧录 / 验收

### 7.1 编译

```bash
W=$HOME/linux/rk3576_android
cd $W/work/radxa-rk3576-android14
source build/envsetup.sh
lunch rk3576_lz200-userdebug          # ← 本文件 §6.3 新建的 target
./build.sh -AKUpu -J6 2>&1 | tee -a \
  /home/dengbaowen/freebuf/hclinux/rk3576_android14/build/logs/$(date -u +%Y%m%d-%H%M)-build-rk3576_lz200.log
```

- `-A` Android / `-K` kernel / `-U` u-boot / `-p` 打包到 `IMAGE` / `-u` 生成 `update.img` (已核对 `build.sh` usage)
- **J 不超过 6** (本机 19G 内存); 另开终端盯 `df -h` 与 `free -h`, `dmesg -w | grep -i "killed process"` 防 OOM
- 产物: `rockdev/Image-rk3576_lz200/update.img` (+ `boot.img`/`super.img`/`dtbo.img` 等)

#### 7.1.1 编译环境四个坑 (2026-11-17 全部实测踩过并修好)

| # | 坑 | 症状 | 根因 | 修法 |
|---|---|---|---|---|
| 1 | **必须外层先 `lunch` 再调 `build.sh`** | `./build.sh -K` 报 `cd: kernel-: No such file or directory` | `build.sh` 用 `KERNEL_VERSION`/`PRODUCT_KERNEL_DTS` 拼路径, 这两个变量只由 `lunch` 注入 | `source build/envsetup.sh && lunch rk3576_lz200-userdebug` **之后**再 `./build.sh` |
| 2 | **内核工具链前缀是 `aarch64-none-linux-gnu-`** | 报找不到 `aarch64-linux-gnu-gcc` | BSP 只带 ARM 官方 `none` 前缀工具链 | 用脚本默认值, 不要手动传 `CROSS_COMPILE=aarch64-linux-gnu-`; `LLVM=1` 需 `prebuilts/clang/host/linux-x86/clang-r487747c/bin` 在 `PATH` |
| 3 | **git-lfs 指针没拉 → 各种离奇崩溃** | ① `clang: cannot execute binary` ② bazel 报 `java/lang/NoClassDefFoundError: java/lang/Object` / `SIGSEGV SharedClassPathEntry::validate` ③ `soong_build` 起不来 | `repo` 给各仓写了 `filter.lfs.smudge = git-lfs smudge --skip`, 预编译件全留成 134 字节指针 | 对每个带 `filter=lfs` 的仓单体 `git lfs pull`; 已实测修复清单见 §7.1.2 |
| 4 | **系统 JDK 版本对不上** | `build.sh:100` 写死 `JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64`, 本机 Ubuntu 22.04 无 java-8 | 脚本假设有 JDK 8 | `sudo ln -s /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/java-8-openjdk-amd64`; 树内 `prebuilts/jdk/jdk11` + `jdk17` 都要 LFS 拉全 |

> 判据: 修好后 `prebuilts/jdk/jdk17/linux-x86/bin/java -version` = `17.0.4.1 Android_PDK`, `jdk11` = `11.0.15`, 两者 `lib/modules` 都 > 100MB。

#### 7.1.2 全树 git-lfs 面 (实测清单)

找法: 扫所有含 `filter=lfs` 规则的 `.gitattributes`, 再 `grep -rl "git-lfs.github.com/spec"` 确认是否还是指针。

| 仓 | 是否必须 | 状态 (2026-11-17) |
|---|---|---|
| `prebuilts/clang/host/linux-x86` | ✅ 必须 | 已拉 (`clang-17` = 142,226,544 字节) |
| `prebuilts/clang-tools` / `prebuilts/misc` / `prebuilts/remoteexecution-client` | ✅ 必须 | 已拉 |
| `prebuilts/jdk/jdk17` | ✅ 必须 | 已拉 (`lib/modules` = 129,281,379) |
| `prebuilts/jdk/jdk11` | ✅ 必须 (bazel 用) | 已拉 (`lib/modules` = 142,479,402) |
| `prebuilts/android-emulator` / `tools/dexter` / `external/swiftshader` / `external/chromium-webview` / `external/camera_engine_rkaiq` | 视需求 | 已拉 |
| `prebuilts/module_sdk/art` | 中 | **3 个指针未拉** (整包前补) |
| `vendor/rockchip/common` | 高 | **1 个指针未拉** (整包前补) |
| `prebuilts/jdk/jdk9` | ❌ 不用 | 2 个指针, A14 不用 jdk9 |
| `packages/apps/Camera360` / `packages/services/Car` / `packages/modules/Virtualization` | ❌ 不用 | 实测 0 指针 |

### 7.2 烧录 (无屏也能烧)

```bash
# 板子进 Loader: 串口 root 下 `reboot loader` (或断电按住 Update 键插 Type-C; MaskROM 兜底)
sudo upgrade_tool uf update.img
# 失败先擦后烧:
# sudo upgrade_tool ef update.img && sudo upgrade_tool uf update.img
# 再不行: sudo upgrade_tool lf update.img
```

### 7.3 上板验收 (串口 `/dev/ttyUSB1` @1500000)

| # | 命令 | 通过标准 |
|---|---|---|
| 1 | `getprop ro.build.version.release` | `14` |
| 2 | `getprop ro.product.device` | `rk3576_lz200` (与板级名一致) |
| 3 | `getprop init.svc.bootanim` | `stopped` (开机动画结束) |
| 4 | `ip addr` | 有 `eth0` (插网线) 且能 `ping` 网关 |
| 5 | `dmesg -t \| grep -iE "stmmac\|dwmmc\|mmc0\|hdmi\|typec"` | 网口/eMMC/HDMI 控制器 probe 成功, 无连续报错 |
| 6 | `wm size` | 有分辨率 (HDMI 或 DSI 至少一个 online) |
| 7 | `dumpsys SurfaceFlinger --display-id` | 有显示设备 |
| 8 | `ls /dev/block/by-name/` | `boot` `super` `vendor_boot` `dtbo` `misc` 等齐全 |

### 7.4 无屏远程桌面 (与路线 A 通用)

见 `BUILD_ANDROID.md` §8。首选 **方案 A**: 板子 Type-C ↔ PC USB, `adb devices` → PC 跑 `ws-scrcpy` → 浏览器 `http://<PC-IP>:8000`。
> userdebug 版本默认 `adb root` 可用; 若浏览器要直连板子, 需先有 IP (有线) 并 `setprop service.adb.tcp.port 5555`。

---

## 8. 风险 / 坑 (都带依据; 标注待验证的不许当结论)

| # | 风险 | 依据 | 应对 |
|---|---|---|---|
| 1 | **googlesource 不可达** → 原生 repo 装不上 | 实测 `curl` 000/20s; `repo init` 报 clone.bundle 失败 | 已 vendored repo v2.54 (§4.1), 以后别用 `/usr/bin/repo` |
| 2 | **`repo sync --depth` 不存在** | 实测 `error: no such option: --depth` | `repo init --depth=1` (§4.2) |
| 3 | gitlab **API 限流 429** | 本轮实测出现 429 | 少用 API; sync 用 `-j4`, 失败重跑 |
| 4 | 全量同步耗时/断流 | 1234 个项目, 全走 HTTPS 匿名 | 后台跑 + 定时汇报 (§20); `repo sync` 可续传 |
| 5 | 磁盘临界 | 268G vs 估算 195~280G | 编译前 `df`; 不够扩 vmdk 到 400~500G (宿主机操作, 关虚拟机) |
| 6 | ~~无线无驱动~~ → **已推翻 (2026-11-17)**: Android BSP **自带** SeekWave SV6160 驱动 | 实测 `./build.sh -K` 日志 `Build exteranl wifi driver ok!`; 产出 `external/wifi_driver/ea6621q/drivers/skwifi/skw.ko` (599,688) / `seekwaveplatform/sdio/skw_sdio.ko` (152,864) / `seekwaveplatform/skwutil/skw_bootcoms.ko` (83,056); 头文件 `ea6621q/include/linux/platform_data/skw6160_config.h`; `wifi.load` 已列这三个 ko | 不再需要向 NEARDI 索驱动; 只需板级 DTS/`config.cfg` 把 SDIO WiFi 使能选对 (`skw*` 三模块 + 对应 sdio 节点), 首版起机后按 `dmesg \| grep -i skw` 验证 |
| 7 | 三路摄像头 fragment 可能 probe 失败 | fragment 默认启用 3 路 cam (`*-cam-*-comb.dtsi`); 无摄像头时 i2c 无应答 | 首版可先把 3 个 cam fragment 注释掉 (dts 里 `//#include`), 起机后再逐个加回 |
| 8 | MIPI-DSI 10.1 屏 fragment | 该 fragment 针对 10.1 寸屏, 不接屏时可能白屏/异常 | 首版注释掉 `mipi-dsi-10.1-screen` fragment, 只留 HDMI (待验证 fragment 内 status) |
| 9 | `super` 分区超 eMMC | 板 eMMC 29G 可用 | 用 `rk3576_u/config.cfg` 为底核对; 编译前 `get_partition_size.py` 检查 |
| 10 | 板级 `BoardConfig.mk` 遗留 EVB 外设开关 | 模板含 `BOARD_GSENSOR_MXC6655XA_SUPPORT` 等 | 按 LKB3576 实配删减 (lz200 无该加速度计) |
| 11 | 烧录覆盖 Ubuntu / GPT 重建 | upgrade_tool 按 parameter 重分区 | 回滚 = 重烧 220 上编的 Ubuntu `update.img` |
| 12 | 公共镜像版本漂移 | manifest 已 pin SHA, 但分支可变 | 以 manifest 快照 (`work/manifests` 的 commit) 为准, 不随手 `repo sync` 换 revision |

---

## 9. 回滚

| 层 | 操作 |
|---|---|
| 源码树 | 直接 `rm -rf ~/linux/rk3576_android/work/radxa-rk3576-android14` (磁盘腾空); manifest 快照保留 |
| 板级改动 | `git -C device/rockchip/rk3576 checkout . && git -C kernel-6.1 checkout .` (丢本地 commit 用 `git reset --hard <pinned sha>`) |
| 板子 | `sudo upgrade_tool uf <Ubuntu update.img>` (220:`~/rk3576/rk3576_linux/rockdev/...`) |
| 整盘 | 卸载 fstab 行 → `umount ~/linux/rk3576_android` → 宿主机关机缩小/删除 vmdk 磁盘 |

---

## 10. 记录 / 证据索引

| 内容 | 路径 |
|---|---|
| manifest 快照 (本地 git) | `~/linux/rk3576_android/work/manifests/` (main, commit `1677660`) |
| vendored repo | `~/linux/rk3576_android/tmp/repo-src/` (tag `v2.54`, commit `2f9253b`) |
| 局部 sync 日志 (成功) | `build/logs/20261117-1123-repo-sync-partial-ok.log` |
| 全量 sync 日志 (进行中/结果以文件为准) | `build/logs/20261117-1123-repo-sync-full.log` |
| 首次失败日志 (留证) | `build/logs/20261117-1121-repo-sync-partial-fail.log` |
| 板级来源 (Ubuntu) | 220:`~/rk3576/rk3576_linux/kernel/arch/arm64/boot/dts/rockchip/RK3576/neardi/` (12 文件, 88K) |
| 路线 A 文档 | `docs/BUILD_ANDROID.md` |

---

**维护约定**: 每完成一个阶段 (同步完成 / DTS 编过 / lunch 通过 / 镜像烧成) 都回本文件改对应状态, 并按 §3.5 写 `docs/PROGRESS.md` 标准条目。
