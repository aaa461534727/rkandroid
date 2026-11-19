# rk3576_android14/docs/BUILD_ANDROID.md — LKB3576 Android 14 源码获取 / 编译 / 烧录 / 无屏远程桌面

> **权威来源**: NEARDI 官方 wiki **LKB3576** 分册 (2026-11-17 抓取, 英文原页) + 本机实测 + 主人 2026-11-17 口述.
> - 编译页: `wiki.neardi.net/docs/rockchip-rk3576/LKB3576/android/build_android`
> - 规格页: `wiki.neardi.net/docs/rockchip-rk3576/LKB3576/gettings-started/specs`
> - 烧录页: `wiki.neardi.net/docs/rockchip-rk3576/LKB3576/upgrade-firmwave/upgraded`
> - 必读页: `wiki.neardi.net/docs/developers-must-read`
>
> 状态/待办看 `docs/project.json`, 现场看 `docs/WORKLOG.md`, 板子细节看 `docs/BOARD.md`.
>
> 🔀 **路线说明 (2026-11-17)**: 本文件是 **路线 A = NEARDI 官方整包** (兜底)。
> **当前主选 = 路线 B**: 拉瑞芯微官方 Android 14 BSP (公共 GitLab 镜像) + 用 Ubuntu SDK 的 lz200 板级自适配, 见
> **`docs/ADAPT_ROCKCHIP_ANDROID.md`** (含源码来源实测、repo 工具坑、DTS/config/板级目录改法)。

---

## 1. 板子是 LKB3576 (关键, 已核对)

| 项 | 值 | 来源 |
|---|---|---|
| **产品型号** | **NEARDI LKB3576** (RK3576 开发板, 载板式) | 主人 2026-11-17 指认 + 官方 wiki |
| **同平台同 DTS 的板名** | `Rockchip RK3576 NEARDI LZ200 Board` | 串口 `cat /proc/device-tree/model` |
| **为何板名不一致** | LKB3576 的核心板沿用 `lz200` 板级配置; 官方 **Android target 就叫 `rk3576_neardi_lz200-userdebug`**, Ubuntu defconfig 叫 `rockchip_rk3576_neardi_lz200_defconfig` | 官方 wiki 原文 |

> ✅ **结论: 不需要移植板级**. 之前担心的"官方 lb200 vs 本板 lz200 要对不上"是 **LPR3576 / Neardi-PI3 的 lb200**, 与本板无关;
> LKB3576 官方给的 target 就是 **lz200**, 与串口 device-tree model 完全吻合.

### LKB3576 硬件规格 (官方规格页)

| 项 | 规格 |
|---|---|
| 供电 | DC 12V (过压/过流/浪涌/防反接保护) |
| USB | 3× USB 3.0 HOST (Type-A) + 1× 全功能 Type-C |
| 显示 | **1× HDMI 2.0 + 1× MIPI-DSI** |
| 视频输入 | 3 路 MIPI-CSI |
| 扩展 | 1× mini-PCIe (4G/5G 模块 或 RK1808 NPU 卡) + 1× M.2 M-KEY (SSD/HDD, 2242) |
| 音频 | φ3.5 输出 + MIC 输入, 可带 10W@8Ω 立体声 |
| 网络 | **2× 千兆以太网** + 双频 **WiFi 6** (802.11 a/b/g/n/ac/ax), 可选 4G/5G |
| 数据口 | UART + RS485 |
| 系统 | Android 14 / Ubuntu / Debian / Buildroot / OpenEuler / Kylin |
| 尺寸 | 150 × 100 × 12.6 mm |

### 本机串口实测 (2026-11-17)

| 项 | 值 |
|---|---|
| 串口 | **`/dev/ttyUSB1` @ 1500000** (`/dev/ttyUSB0` 无输出, 是另一颗芯片) |
| 账号 | `root` / `root` (板内 Ubuntu 免密登录) |
| 当前系统 | Ubuntu, hostname `openiot`, kernel `6.1.118` |
| 内存 / 存储 | RAM **3.8 GiB** / eMMC **29 G** (已用 5.4G) |
| 当前网络 | **只有 `usb0` 192.168.2.1/24** (USB gadget); eth0/wlan0 无 IP |

## 2. 本机编译环境 (已就绪, 2026-11-17)

| 项 | 值 | 是否达标 |
|---|---|---|
| 系统 | **Ubuntu 22.04.5 LTS (jammy)** | ✅ 官方要求 22.04, 不要 WSL |
| 内存 | **19 GiB** (available 16G) | ✅ 官方要求 16G+ |
| swap | **25 GiB** (`~/linux/rk3576_android/.swapfile` 24G + `/swapfile` 2G) | ✅ 兜编译峰值 |
| CPU | 8 vCPU | ✅ (`-J6` 控内存) |
| 编译盘 | `/dev/sdb` 300G ext4 → **`~/linux/rk3576_android`**, 可用 **268 G** | ⚠️ 官方要求 250G, **只剩 18G 余量, 偏紧** |
| 用户 | `dengbaowen` (普通用户) | ✅ 官方明确不要 root |

### 目录约定

```
~/linux/rk3576_android/          ← /dev/sdb 300G 唯一挂载点 (fstab UUID 单行)
├── pkgs/                        ← 放 neardi-3576-android-14.tar.gz + md5 (解压后删除)
├── work/                        ← 解压出来的源码树 (neardi-3576-android-14/) + 编译 out
├── tmp/                         ← 临时
└── .swapfile                    ← 24G swap (fstab 已登记)
```

> `/data` 已取消挂载; 整块盘只挂 `~/linux/rk3576_android` 一个点 —— 以后想回收空间直接删/缩 vmdk 即可.
> ⚠️ **磁盘余量风险**: 268G vs 250G 需求. 缓解办法 (按优先级):
> 1. 解压完立刻删 `pkgs/*.tar.gz` (省 30~40G);
> 2. 需要并行多 target 时再临时把 vmdk 扩到 400G;
> 3. 不开 ccache (没有余量), `out/` 只留当前 target.

## 3. 获取 Android 14 SDK (路线 A, 兜底; 当前主选见 `ADAPT_ROCKCHIP_ANDROID.md`)

| 项 | 内容 |
|---|---|
| 包名 | **`neardi-3576-android-14.tar.gz`** |
| 校验文件 | **`neardi-3576-android-14-tar.gz.md5sum`** (官方 wiki 原文写法) |
| 渠道 | **发邮件 `support@neardi.com`** 申请 (必读页 §4: SDK 包/原理图/PCB 属受限资料, 只走邮件) |
| 邮件里要写 | ① 型号 **LKB3576** + 硬件版本 ② 要 **Android 14** ③ 购买渠道/订单号 ④ 用途 (Android 桌面 + 远程显示) |
| 公开渠道? | ❌ 无. `github.com/neardi` 只公开 `buildroot` / `neardi-3588-sdk-linux` / `neardi-cross` / `neardi_cam_demo`, **没有 Android 树**; 220/223/224 也没有 |
| 落点 | `~/linux/rk3576_android/pkgs/` |
| 禁止 | ❌ 在 Windows 解压再拷进 Ubuntu (官方明确: 会丢文件属性/权限) |

```bash
# 拿到包后第一件事: 校验 (必须在解压前)
cd ~/linux/rk3576_android/pkgs
md5sum neardi-3576-android-14.tar.gz
# 与 neardi-3576-android-14-tar.gz.md5sum 里的值逐字比对
```

## 4. 解压 + 同步源码

```bash
cd ~/linux/rk3576_android/pkgs
tar -zxf neardi-3576-android-14.tar.gz -C ../work/

cd ~/linux/rk3576_android/work/neardi-3576-android-14
.repo/repo/repo sync -l        # 用包内 .repo 补齐 git 对象 (不联网)
```

> 解压确认无误后再 `rm ../pkgs/neardi-3576-android-14.tar.gz` (省空间).

## 5. 板级 target — **已确认, 无需移植**

```bash
source build/envsetup.sh
lunch
# 选: rk3576_neardi_lz200-userdebug      ← LKB3576 官方 target (wiki 原文)
```

| 对照项 | 值 |
|---|---|
| Android lunch target | **`rk3576_neardi_lz200-userdebug`** |
| Ubuntu SDK defconfig | `rockchip_rk3576_neardi_lz200_defconfig` |
| 内核 DTS 目录 (Linux SDK 侧) | `kernel/arch/arm64/boot/dts/rockchip/RK3576/neardi/` |
| 串口 device-tree model | `Rockchip RK3576 NEARDI LZ200 Board` |

> 三者一致 ⇒ **LKB3576 = lz200 板级**. ✅ 之前文档里"要按 lb200 移植"的说法作废 (lb200 属于 LPR3576/Neardi-PI3).

## 6. 编译

> 🔴 **铁律 (2026-11-18)**: 出固件前**必须**先 `bash scripts/install_board.sh --check` 全绿；
> SDK 编出来的固件**必须自带主仓 `src/` 的全部功能** (驱动补丁 / 板级固件 / DTS)。
> 只靠 `adb push` 验过的板子**不算交付** —— 重烧就丢。详见 `../README.md`「🔴 编译铁律」。

```bash
# 0) 先对齐 src → SDK (必须 == OK)
cd <仓库根>/rk3576_android14 && bash scripts/install_board.sh --check

# 1) 进源码树 (路线 B: 瑞芯微官方 Android 14 BSP + 自建 lz200 板级)
cd ~/linux/rk3576_android/work/radxa-rk3576-android14
source build/envsetup.sh
lunch rk3576_lz200-userdebug

# 2) 编 Android + 打包 + 出 update.img
./build.sh -A -u -J6           # -J6 = 本机 19G 内存的上限, 官方示例不带 -J
# 改了内核 / DTS: ./build.sh -K -A -u -J6   (-K 先 make clean 内核, 约 25 分钟)
```

| 参数 | 含义 |
|---|---|
| `-A` | 编 Android |
| `-K` | 编 kernel (+ 顺带重编 `external/wifi_driver/*.ko`) |
| `-U` | 编 u-boot (本项目不动, 一般不编) |
| `-p` | 打包分区 |
| `-u` | 生成 `update.img` |
| `-J6` | 并行 6 (官方无此参数; 本机内存有限才加) |

**分步编 (开发期更省时间)**

```bash
./build.sh -K                   # kernel (+ external wifi ko)
./build.sh -A                   # Android (脚本内部自带 make installclean)
./build.sh -u                   # 只打包 update.img
```

**改完 `.ko` / HAL / 板级固件时的最短路径**: 内核不动就不用 `-K`；
`./build.sh -A -u -J6` 会把 `external/wifi_driver/*.ko` 装进 `vendor_dlkm`、把板级 `firmware/` 装进
`/vendor/etc/firmware/`、把 `librkwifi-ctrl.so` 重新装进 `vendor`，再重新打 `super.img` + `update.img`。

**监控 (另一个终端)**

```bash
watch -n 30 'df -h ~/linux/rk3576_android; free -h'
dmesg -w | grep -i "killed process"      # OOM 就降到 -J4 重跑 (增量续编)
grep -nE "^error:|^FAILED: |ninja: build stopped|fatal error:" build/logs/<日志>
```

**产物**: `rockdev/Image-rk3576_lz200/update.img` (每次编译新建一个 Image-* 目录, 自动备份历史)

| 分区映像 | 内容 |
|---|---|
| `boot.img` | 内核 + **resource.img(second 段, 内含内核真正使用的 DTB)** |
| `super.img` | 动态分区 (system/vendor/product 等, Android 14 用 super) |
| `kernel.img` / `resource.img` | 内核 + DTB/logo |
| `uboot.img` / `trust.img` | U-Boot / ATF |
| `misc.img` / `dtbo.img` / `vbmeta.img` / `parameter.txt` | 启动模式 / dtbo / 校验 / 分区表 |

| 分区映像 | 内容 |
|---|---|
| `boot.img` | Android initramfs |
| `super.img` | 动态分区 (system/vendor/product 等, Android 14 用 super) |
| `kernel.img` / `resource.img` | 内核 + DTB/logo |
| `uboot.img` / `trust.img` | U-Boot / ATF |
| `misc.img` / `dtbo.img` / `vbmeta.img` / `parameter.txt` | 启动模式 / dtbo / 校验 / 分区表 |

## 7. 烧录 (无 HDMI 也能烧, 也不需要屏幕)

### 7.1 装工具 (Linux, 无驱动)

```bash
# Linux_Upgrade_Tool (官方 Google Drive 链接见 wiki 烧录页)
unzip Linux_Upgrade_Tool_*.zip && cd Linux_UpgradeTool_*
sudo mv upgrade_tool /usr/local/bin && sudo chown root:root /usr/local/bin/upgrade_tool && sudo chmod a+x /usr/local/bin/upgrade_tool
```

### 7.2 进 Loader 模式 (二选一)

| 方式 | 步骤 |
|---|---|
| 软件 (当前有 Ubuntu, 最方便) | Type-C 接 PC → 串口/adb 里敲 **`reboot loader`** |
| 硬件 | 断电 → 按住 **Update** 键 → 插 Type-C → 上电 |

```bash
sudo upgrade_tool            # 出现 "DevNo=1 ... Loader" 即成功
```

进不去 Loader 再走 **MaskROM** (`upgrade_tool db` + `maskrom_mode` 页).

### 7.3 烧整包

```bash
sudo upgrade_tool uf update.img
# 失败就先擦: sudo upgrade_tool ef update.img && sudo upgrade_tool uf update.img
# 再不行低级格式化: sudo upgrade_tool lf update.img
```

### 7.4 只烧单分区 (开发调试更快)

```bash
sudo upgrade_tool di -b  boot.img
sudo upgrade_tool di -dtbo dtbo.img
sudo upgrade_tool di -u  uboot.img
sudo upgrade_tool di -p  parameter.txt
```

### 7.5 官方 Android 分区表 (LKB3576, 供核对)

| NO | LBA | Size | Name |
|---|---|---|---|
| 01 | 0x00002000 | 0x00002000 | security |
| 02 | 0x00004000 | 0x00002000 | uboot |
| 03 | 0x00006000 | 0x00002000 | trust |
| 04 | 0x00008000 | 0x00002000 | misc |
| 05 | 0x0000a000 | 0x00002000 | dtbo |
| 06 | 0x0000c000 | 0x00000800 | vbmeta |
| 07 | 0x0000c800 | 0x00014000 | boot |
| 08 | 0x00020800 | 0x00030000 | recovery |
| 09 | 0x00050800 | 0x000c0000 | backup |
| 10 | 0x00110800 | 0x000c0000 | cache |
| 11 | 0x001d0800 | 0x00008000 | metadata |
| 12 | 0x001d8800 | 0x00000800 | baseparameter |
| 13 | 0x001d9000 | 0x00614000 | super |
| 14 | 0x007ed000 | 0x06b4efdf | userdata |

> 烧整包会**覆盖板上现有 Ubuntu**; 回滚要重烧 Ubuntu `update.img` (220 上 `rk3576_linux` 可编).
> 固件本体不进仓 (§12.8); `md5sum update.img` + 大小记 `build/logs/`.

## 8. 无屏远程桌面 (不插 HDMI / 不插鼠标)

### 8.1 原理

Android 的显示由 **SurfaceFlinger** 输出, 只要 DTS 里有可用 display (LKB3576 有 HDMI 2.0 + MIPI-DSI 两路, 官方固件默认就有主显示), 即使**不接屏**也有主显示缓冲.
`scrcpy` 通过 **adbd** 抓 H.264 流 + 注入触摸/按键事件 ⇒ **不需要 HDMI, 不需要鼠标**.

### 8.2 方案 A (推荐, 最稳): PC 跑 ws-scrcpy, 浏览器访问 PC

```bash
# 1) 板子 Android 起来后, Type-C 接 PC (USB 调试)
adb devices
adb shell setprop service.adb.tcp.port 5555
adb shell stop adbd; adb shell start adbd
# 网络可达时可 adb connect <板IP>:5555 (板子有 2×GbE + WiFi6)

# 2) PC 跑 ws-scrcpy
cd ~/linux/ws-scrcpy && npm install && npm start
# 浏览器打开 http://<PC-IP>:8000 → 实时画面 + 触摸/滑动/按键
```

> 本机已装 `/usr/bin/adb`, `~/linux/scrcpy` 已有源码, `~/linux/srcpy.sh` 可参考.

### 8.3 方案 B (浏览器直接访问板子 IP): 板内跑 ws-scrcpy

- 板内放 **arm64 Node + ws-scrcpy** (推到 `/data/local/tmp` 或用 Magisk 模块)
- 板内 `adb connect 127.0.0.1:5555` → ws-scrcpy 起在 8000
- 浏览器打开 `http://<板IP>:8000`

> 前提: 板子网络可达 (LKB3576 有 2×GbE + WiFi6, 插网线或有线 DHCP 即可; 现在是 Ubuntu 且只有 usb0).

### 8.4 备选

| 方案 | 说明 | 能操控? |
|---|---|---|
| `droidVNC-NG` APK (需 root) | 板内 VNC server + noVNC 网页 | ✅ |
| MJPEG 网页投屏 | 只能看 | ❌ |
| HDMI 采集卡 | 硬件方案, 违背"不插 HDMI" | ✅ (需鼠标) |

## 9. 风险 / 坑

| # | 坑 | 处理 |
|---|---|---|
| 1 | SDK 只走邮件, 不能直接 wget | 主人发 `support@neardi.com` 申请 (唯一阻塞) |
| 2 | **268G 余量 vs 官方 250G 需求** | 解压后立刻删 tar.gz; 必要时 vmdk 扩到 400G; 不开 ccache |
| 3 | 19G 内存全编会 OOM | `-J6` + 25G swap; OOM 降 `-J4` 增量重跑 |
| 4 | 无 HDMI 且 DTS 无 panel → SurfaceFlinger 起不来 | 官方 lz200 target 默认有主显示; 若黑屏查 `dumpsys SurfaceFlinger --display-id` / `wm size` |
| 5 | 烧 Android 覆盖板上 Ubuntu | 回滚 = 重烧 220 上编的 Ubuntu `update.img` |
| 6 | 板上当前只有 `usb0` 网络 | 先走 USB adb; 要板子 IP 直连就插网线 (2×GbE) |
| 7 | 串口设备名随插拔变 | 用 `/dev/ttyUSB1` @1500000; `ttyUSB0` 无输出 |
| 8 | 官方 target 名易记错 (`lb200` vs `lz200`) | **本板是 `rk3576_neardi_lz200-userdebug`** |
