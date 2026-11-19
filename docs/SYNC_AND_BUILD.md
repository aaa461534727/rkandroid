# SYNC_AND_BUILD — 从零把源码同步下来并编出 LKB3576 固件

> 本文是**唯一操作手册**。任何 AI / 任何人按这里从头走一遍，能得到与本机 2026-11-18 那套**逐字节一致**的源码，并编出同一个 `update.img`。
> 全部命令都在 **Ubuntu 22.04 普通用户**下执行（**不要 root 编译**）。
> 时间参考（本机 8 vCPU / 16 G 内存，实测）：`repo sync` 首轮 **≈ 3.5 小时**、全量编译 **≈ 6 小时 14 分**（`耗时=22429s`）、增量 Android **≈ 28 分钟**、只编 WiFi 驱动 **≈ 50 秒**。

---

## 0. 名词对齐（先看清"仓库"和"源码"是两件事）

```
本仓 rkandroid (4 MB, GitHub)                源码树 (109 GB, 本机磁盘)
├── default.xml       ─── repo init 读它 ───► .repo/  (裸仓 36 GB)
├── manifests/  (对照用)                       ├── build/ kernel-6.1/ external/ ...  (1234 个 git 仓)
├── src/              ─── install_board.sh ──► └── 被覆盖的板级文件 / DTS / 驱动补丁
└── scripts/ docs/
```

- **源码本体一律不进仓**：由 `repo sync` 按 `default.xml` 里锁死的 commit 从公开镜像 `https://gitlab.com/rockchip_android14_rk3576` 拉。
- **我们自己的改动只有 `src/`**（2.4 MB）：`repo sync` 不会带上它，必须靠 `install_board.sh` 铺进去。**忘了这步 = 编出来的固件缺 WiFi 驱动补丁 / 板级固件 / 板级 DTS。**

---

## 1. 一次性环境准备

```bash
# 1.1 依赖包
sudo apt-get update
sudo apt-get install -y git repo curl rsync python3 bc build-essential zip unzip \
    libssl-dev libncurses5 libncurses5-dev libxml2-utils lz4 zlib1g-dev \
    gcc-multilib g++-multilib device-tree-compiler

# 1.2 repo 工具（apt 的 repo 版本可能太老；用官方脚本更稳）
mkdir -p ~/bin
curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=~/bin:$PATH          # 建议写进 ~/.bashrc

# 1.3 git 身份（repo init / commit 都要用）
git config --global user.name  "你的名字"
git config --global user.email "你的邮箱"

# 1.4 硬指标
df -h   # 目标盘 ≥ 260 GB（源码 109G + out/ 115G），推荐 300G
free -g # 8G 能编（-J4）；16G 舒服（-J6，实测峰值 ~8G）
nproc   # 核数决定 -J
```

---

## 2. 同步源码（三步）

```bash
# 2.1 取本仓（4 MB，几秒）
git clone https://github.com/aaa461534727/rkandroid.git ~/rkandroid

# 2.2 一键：repo init + repo sync + 应用 src 叠加层
WS=~/rk3576_android14_ws JOBS=8 bash ~/rkandroid/scripts/sync.sh
```

`sync.sh` 内部等价于：

```bash
mkdir -p $WS && cd $WS
repo init -u file://$HOME/rkandroid -b main      # 读本仓 default.xml (1234 project)
repo sync -j8 --no-clone-bundle                  # 拉 109 GB，断了直接重跑（续传）
SDK=$WS bash ~/rkandroid/scripts/install_board.sh --push   # src/ → 源码树
```

### 2.1 只重读 manifest / 源码已在本地

```bash
WS=/已有/源码树 bash ~/rkandroid/scripts/sync.sh --no-sync
```
（本机可直接复用：`WS=$HOME/linux/rk3576_android/work/radxa-rk3576-android14`）

### 2.2 只要源码、不要板级改动

```bash
WS=... bash ~/rkandroid/scripts/sync.sh --skip-board
```
（会得到一个**纯原厂**树，`lunch` 里没有 `rk3576_lz200`）

### 2.3 更新本仓后（我们改了 `src/` 或 manifest）

```bash
git -C ~/rkandroid pull --ff-only
WS=$WS bash ~/rkandroid/scripts/sync.sh --no-sync      # 只重读 manifest + 重铺 src
```
> `repo init -u file://~/rkandroid` 指向本地 clone，所以**别删 `~/rkandroid`**；删了重跑 `sync.sh` 就能修回来。

### 2.4 同步完自检（必跑）

```bash
WS=$WS bash ~/rkandroid/scripts/verify_tree.sh
```
判据：`FAIL=0`，且能看到
`PASS manifest 已在位, project = 1234` / `PASS lunch 目标在位` / `PASS src ⇄ 源码树 全部一致`。

---

## 3. 板级叠加层到底改了什么（`install_board.sh`）

`src/` 里的改动分 5 类，`install_board.sh` 逐类铺进源码树，并**幂等**打两处补丁：

| # | `src/` 路径 | 落到源码树 | 说明 |
|---|---|---|---|
| 1 | `kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-neardi*.dtsi`、`rk3576-lz200-*.dts` | 同名路径 | 板级 DTS；同时往 `Makefile` **幂等**追加 `dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3576-lz200-android.dtb`（不追加 → 编 dtb 报"无此目标"） |
| 2 | `device/rockchip/rk3576/rk3576_lz200/` | **整目录镜像**（`rsync -a --delete`，排除 `firmware/`） | 板级 product 配置：`AndroidProducts.mk` / `BoardConfig.mk` / `rk3576_lz200.mk` / `config.cfg` / `dt-overlay.in` …；**这就是 `lunch rk3576_lz200-userdebug` 的来源** |
| 3 | 12 个单文件（`FILE_MAP`） | 同名路径 | WiFi 驱动 6 处补丁 + SDIO 2 处 + `skw6160_config.h` + WiFi HAL `rk_wifi_ctrl.cpp` + BT `stack_manager.cc` + `ClientModeImpl.java` |
| 4 | `firmware/swt6652x/*` | 板级 `firmware/`，**含改名** | 驱动里固件名硬编码：`SWT6652_IRAM_SDIO.bin → ROM_EXEC_KERNEL_IRAM.bin`、`SWT6652_DRAM_SDIO.bin → RAM_RW_KERNEL_DRAM.bin`（其余同名） |
| 5 | （脚本内联补丁，不在 `src/`） | `vendor/rockchip/common/wifi/wifi.mk` | **必须**给 `WifiFirmwareFile` 加 `filter-out ROM_EXEC_KERNEL_IRAM.bin RAM_RW_KERNEL_DRAM.bin`，否则原厂 EA6621Q 版同名固件会覆盖我们的 SWT6652x 版 → 烧完 `wifi boot failed` |

三种模式：

```bash
SDK=$WS bash ~/rkandroid/scripts/install_board.sh --push    # src → 源码树（默认）
SDK=$WS bash ~/rkandroid/scripts/install_board.sh --check   # 只比 md5，不一致 exit 1
SDK=$WS bash ~/rkandroid/scripts/install_board.sh --pull    # 源码树 → src（调试改通了回收）
```

**铁律**：在源码树里调通的改动，**必须** `--pull` 回 `src/` 并提交本仓，否则换机器 / 下次 `repo sync` 就丢了。
`--pull` 不回收 `wifi.mk` 的 filter-out（那是脚本维护的补丁，`--push` 会自动补）。

---

## 4. 编译

```bash
cd $WS
source build/envsetup.sh
lunch rk3576_lz200-userdebug

# 4.1 全量（首次）：编 Android + 打包 update.img
./build.sh -A -u -J6
#   本机实测: 22429 s ≈ 6 h 14 min (8 vCPU / -J6 / 峰值内存 ~8G)
#   产物: $WS/rockdev/Image-rk3576_lz200/update.img  (约 2.1 GB)

# 4.2 改了内核 / DTS（必须先清内核再编，否则 dtb 不重生成）
./build.sh -K -A -u -J6

# 4.3 只编内核 + wifi ko
./build.sh -K

# 4.4 只编 Android（脚本内部自带 make installclean）
./build.sh -A

# 4.5 只重新打包 update.img（Android 已编好）
./build.sh -u
```

`build.sh` 参数速查：`-U` uboot · `-K` kernel（`-C` 用 clang）· `-A` android · `-p` 打包进 IMAGE · `-o` OTA · `-u` update.img · `-d <dts>` 指定 dts · `-J<n>` 并行度 · `-v user|userdebug`。

### 4.1 单模块（改一个 app / so，比全量快得多）

```bash
source build/envsetup.sh && lunch rk3576_lz200-userdebug
m <module_name> -j6          # 例: m librkwifi-ctrl -j6
```

### 4.2 只编 WiFi 驱动（开发 `skw.ko` 时最快，约 50 秒）

```bash
cd $WS/external/wifi_driver
./build_wifi_ko.sh ea6621q
# 产物: $WS/external/wifi_driver/ea6621q/drivers/skwifi/skw.ko 等
```
调试期临时验证可以 `adb push` 到 `/vendor/lib/modules` + `/vendor_dlkm/lib/modules` 后重启
（**不需要** `rmmod/insmod`）；但**交付必须整包重编 + 烧录**，`adb push` 只算调试。

---

## 5. 出固件前的机器门禁（**不许跳过**）

```bash
bash ~/rkandroid/scripts/check_firmware_content.sh
```

它核对 `out/` 里**真正会被打进镜像**的东西是否 == `src/`：

| 核什么 | 判据 |
|---|---|
| 板载固件 5 个（IRAM/DRAM/NV/EA6316 bin+ini） | md5 == `src/firmware/swt6652x/md5.txt` |
| `skw.ko` / `skw_bootcoms.ko` / `skw_sdio.ko` | 含 `EA6316` 且 == 当前编译产物 |
| `librkwifi-ctrl.so` | 含 `SKW6160` / `1ffe:6316` 字样 |
| `wifi.load` 之类配置 | 3 个 skw 模块都在 |

**全 OK 才许出 `update.img`** —— 这一条是从"烧完 WiFi 起不来、查半天发现固件被 EA6621Q 版覆盖"那次事故里长出来的（见 `docs/PROGRESS.md`）。

登记 md5（本仓不入镜像，md5 记到主框架仓的 `build/MD5SUMS.txt`）：

```bash
md5sum $WS/rockdev/Image-rk3576_lz200/update.img
```

---

## 6. 烧录（只走 USB）

```bash
# 6.1 装工具（一次）
chmod +x upgrade_tool && sudo mv upgrade_tool /usr/local/bin/ && sudo chmod a+x /usr/local/bin/upgrade_tool

# 6.2 一键（脚本会先核 update.img 的 md5 == 登记值，再 adb reboot loader → uf）
bash ~/rkandroid/scripts/flash_update.sh --wait 60
```

成功判据：出现 `Upgrade firmware ok.` 且脚本 `FLASH_EXIT=0`。

手工路径（脚本挂了时的兜底）：

```bash
adb reboot loader          # 或断电 + 按住 RECOVERY 上电
sleep 10 && sudo upgrade_tool        # 看到 "DevNo=1 ... Loader" 即进 Loader
sudo upgrade_tool uf $WS/rockdev/Image-rk3576_lz200/update.img
# 失败先擦: sudo upgrade_tool ef update.img && sudo upgrade_tool uf update.img
# 再不行低级格式化: sudo upgrade_tool lf update.img
# 只刷单分区(调试快): sudo upgrade_tool di -b boot.img / -dtbo dtbo.img / -u uboot.img
```

> ⚠️ `uf` 整包会**按 `parameter.txt` 重建 GPT 并擦 userdata**。
> ⚠️ 串口控制台：`/dev/ttyUSB1` @ **1500000** 8N1（默认 115200 会全是乱码）。

---

## 7. 开机后冒烟检查（证明固件是活的）

```bash
adb wait-for-device
adb shell getprop sys.boot_completed                       # 1
adb shell cat /proc/modules | grep -c skw                  # 3 (skw / skw_bootcoms / skw_sdio)
adb shell ip link show wlan0                               # 存在, 有 MAC
adb shell cmd wifi status                                  # Wifi is enabled
adb shell cmd wifi list-scan-results | head               # 能扫到 BSS
adb shell dmesg | grep -c BSPASSERT                        # 0 (有 = CP 断言, 必须重启)
adb shell getprop bluetooth 2>/dev/null; adb shell settings get global bluetooth_on
```

---

## 8. 无屏远程桌面（不插 HDMI、不插鼠标）

原理：板子只跑 Android，桌面画面通过 **adb + scrcpy 的 Web 版（ws-scrcpy）**在 PC 浏览器里看和点。

```bash
# PC 侧（一次）
git clone https://github.com/NetrisTV/ws-scrcpy.git ~/ws-scrcpy
cd ~/ws-scrcpy && npm install && npm start        # 监听 0.0.0.0:8000
# 浏览器打开 http://<PC-IP>:8000 → 选设备 → 实时画面 + 触摸/滑动/按键
```
开机自启（可选）：`cp scripts/ws-scrcpy.service ~/.config/systemd/user/ && systemctl --user enable --now ws-scrcpy`
（本仓 `scripts/` 里没带这个 unit 时，用主框架仓 `rk3576_android14/scripts/ws-scrcpy.service`。）

---

## 9. 坑（都真踩过，按踩到的顺序）

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 内核起来了但 PMIC 不探测、没有 `/dev/dri`、显示黑 | 板级 DTS 把 `i2c1m0_xfer_pullup` 直接挂到 `pinctrl` 上，抢了 I2C1 的 pinmux | 按 `docs/ADAPT_ROCKCHIP_ANDROID.md` 里的最终 DTS，把 pull-up 放回 `pinctrl-0` 之外的独立节点 |
| 2 | 编出的 `update.img` 烧完内核是旧版 / 板子不认新 DTB | Android 里内核 DTB **不取** `boot.img` 的 dtb 段，而是取 `resource.img` 的 **`second` 段** | 改完 DTB 必须重打 `resource.img`（`scripts/install_board.sh` 只管源码，重打见 `docs/ADAPT_ROCKCHIP_ANDROID.md` §DTB） |
| 3 | 烧完 `wifi boot failed`，`/vendor/etc/firmware` 里固件 md5 不对 | `vendor/rockchip/common/wifi/wifi.mk` 把 `wifi/firmware/` 里**所有**文件拷进 vendor，其中 EA6621Q 版 `ROM_EXEC_KERNEL_IRAM.bin` 与我们同名撞车，ninja 只留一条 | `install_board.sh --push` 自动给该 mk 加 `filter-out`；`--check` 会报 `DIFF vendor wifi.mk` |
| 4 | WiFi 连上 5 秒被踢，logcat `handleLingerComplete for [102 WIFI]` | `eth0` 已 VALIDATED，framework 认为"有网了"，把 WiFi 判为不需要而 linger 掉 | 测试 WiFi 前先 `adb shell ip link set eth0 down`（板子重启后会恢复 up，要重做） |
| 5 | 编译中途 OOM / 机器卡死 | `-J` 开太大 | 内存 16G 用 `-J6`；8G 用 `-J4`，或加 swap（但会很慢） |
| 6 | `repo sync` 中途报错 | 网络抖动 | 直接重跑同一条命令（repo 会续传）；不要删 `.repo` |
| 7 | 编译报"没有 `rk3576-lz200-android.dtb` 目标" | 只放了 dts 没往 `Makefile` 登记 | 跑 `install_board.sh --push`（它幂等补 Makefile），或手工加 `dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3576-lz200-android.dtb` |
| 8 | `lunch` 列表里没有 `rk3576_lz200` | 板级叠加层还没铺进源码树 | 先 `install_board.sh --push`，再 `source build/envsetup.sh && lunch` |
| 9 | `sudo` 后环境变量丢，脚本行为变了 | `sudo` 默认重置环境 | 传参写成 `sudo HT=0 bash ...` 这种形式 |
| 10 | 编译产物占满盘 | `out/` 约 115 G | `make installclean` / 删 `out/target/product/rk3576_lz200/obj` 里旧模块；不要提交任何 `out/` 内容 |

---

## 10. 已知未结问题：WiFi 数据面（CP 固件侧）

- **现象**：STA 关联、4-way、DHCP 全通；ARP 帧空口完全正常；**IP 帧（IPv4/IPv6）在对端抓包呈畸形** —— 对端 mac80211 解析成 `802.3, length XX` + `LLC dsap 0x44`，表现为"能 ping 通前 2 包然后全丢"。
- **根因（已定性，证据见 `docs/PROGRESS.md` 2026-11-19 条目）**：厂商 **CP 固件**把每帧无条件包成**单子帧 A-MSDU 且不带 LLC/SNAP**，并把载荷长度写到 ethertype 位置。主机侧驱动逻辑（TX 描述符布局 `padding=2 / gap=0`、RX 固定偏移 18）已逐项验证正确。
- **结论**：这不是改 Linux 驱动能根治的；需要**厂商更新 CP 固件**或**换不同芯片方案的模组**。
- 相关旁证：`skw_tx.h` 里 `SKW_SNAP_HDR_LEN 8` 定义了但全仓无人使用，`skw_set_tx_desc_eth_type()` 是空函数 ⇒ 厂商漏做 SNAP 这步。

---

## 11. 换板 / 换芯片时要动哪里

| 换什么 | 动哪里 |
|---|---|
| 只换板、**仍是 RK3576 + 仍是 Android 14** | 复制 `src/device/rockchip/rk3576/rk3576_lz200/` 改名新板 → 改 `BoardConfig.mk` / `config.cfg` / DTS → `install_board.sh` 的 `DEV_REL`、`FILE_MAP` 跟着加 |
| 换 **RK3528** 等其它 SoC | 先确认 BSP 内核版本：Android 14 必须 **kernel 6.1**；RK3528 的 BSP 是 `linux-5.10.198-android` ⇒ 最高 Android 12/13，走 Android 14 这条路不通 |
| 换无线模组 | 换 `src/firmware/<新模组>/` + `FILE_MAP` 里的驱动 + `vendor` wifi.mk 的冲突名单 + HAL 芯片表（`rk_wifi_ctrl.cpp`） |

---

## 12. 验收 DoD（做完这些才算"同步+编译成功"）

1. `verify_tree.sh` → `FAIL=0`
2. `./build.sh -A -u -J6` → `BUILD_FULL_EXIT=0`，出 `rockdev/Image-rk3576_lz200/update.img`
3. `check_firmware_content.sh` → 全 OK
4. `flash_update.sh` → `Upgrade firmware ok.`
5. 第 7 节冒烟全过（`sys.boot_completed=1`、3 个 skw 模块、`wlan0` 在、能扫描、`BSPASSERT=0`）
6. `update.img` 的 md5 已登记（主框架仓 `build/MD5SUMS.txt`）
7. `docs/WORKLOG.md` / `docs/PROGRESS.md` 已更新
