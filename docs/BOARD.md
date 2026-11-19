# rk3576_android14/docs/BOARD.md — 板卡与硬件资源核对表

> **用途**: 上板前 30 秒核对"我连的是哪块板、用什么口、什么账号、烧的什么固件"。
> 与 README 信息卡的分工: 信息卡写"一句话/状态"; 本文件写**硬件细节 + 复现命令**。
> 换板 / 换固件 / 换 IP / 换串口 **必须同步本文件** (否则下个 AI 会连错板)。

---

## 1. 板卡清单

| # | 板 | 型号 / SoC | 内存/存储 | 用途 | 状态 |
|---|---|---|---|---|---|
| 1 | **LKB3576** | **NEARDI LKB3576** (RK3576) | 板载内存待核 (串口报 **3.8 GiB 可用**); eMMC **29 G** (已用 5.4G) | 本机唯一 RK3576 板, Android 14 目标 | ✅ 串口在线 (2026-11-17) |

> 产品页: `https://neardi.com/cms/index/productsd.html?id=90&title=LKB3576`
> 官方 wiki (LKB3576 分册): `https://wiki.neardi.net/docs/category/lkb3576`
> ⚠️ 串口 `cat /proc/device-tree/model` 报的是 **`Rockchip RK3576 NEARDI LZ200 Board`** —— 这是**正常的**:
> LKB3576 的核心板沿用 lz200 板级, 官方 Android target 正是 **`rk3576_neardi_lz200-userdebug`**. 不是错板.

## 2. 访问方式

| 项 | 值 (本机 `dengbaowen-ubuntu` 实测 2026-11-17) |
|---|---|
| **有线 IP** | ⏳ 未取 (板内当前 Ubuntu, 只看到 `usb0`; 板子有 2× 千兆网口, 插网线后 `udhcpc`/`dhclient` 取) |
| **无线 IP** | ⏳ 未连 (板载双频 WiFi 6) |
| **USB 网口** | `usb0` **192.168.2.1/24** (USB gadget, 板子侧) |
| **SSH 账号** | `root` / `root` (主人 2026-11-17 给出) |
| **串口** | **`/dev/ttyUSB1` @ 1500000** (`/dev/ttyUSB0` 无输出 = 另一颗 USB 串口芯片) |
| **串口芯片** | `lsusb` 可见 `0403:6001 FT232` + `1a86:7523 CH340`, 需逐个试 |
| **登录后第一件事** | `cat /proc/device-tree/model; uname -r; ip -4 -o a; free -h; df -h /` |
| **板内主机名** | `openiot` (2026-11-17, Ubuntu, kernel `6.1.118`) |

> ⚠️ 串口设备名**随插拔顺序变化**, 每次先 `ls -l /dev/ttyUSB*` + 试 1500000 看提示符, 别照抄.
> 密码只写本机 `machines/dengbaowen-ubuntu.json` 与本文件(项目内), **不许写进提交给外部的文档**.

## 3. 固件与烧录

| 项 | 内容 |
|---|---|
| **当前固件 (2026-11-19)** | **Android 14 userdebug** (lunch `rk3576_lz200-userdebug`, 路线B 瑞芯微官方 BSP + 自建板级), 整包 `update.img` 2,155,311,747B md5 **`07ba7631e2eee2909aba0558a4fce77d`** 已烧进 eMMC (`Upgrade firmware ok.` / `FLASH_EXIT=0`); 含 WiFi 驱动 8 补丁 + BT 栈启停超时 15s + 板载 5 固件 |
| **上一版固件** | Android 14 md5 `2c68b98adea30d3de8cc5fa667a11547` (2026-11-19 02:17 烧录验收过, 但跑 23 分钟后 CP 断言挂死 ⇒ 被本版替换) |
| **原始固件 (回滚参考)** | Ubuntu (hostname `openiot`, kernel `6.1.118`), 来源 `bob@10.0.100.220:~/rk3576/rk3576_linux` |
| **烧录模式** | **Loader** (软件: 串口 `reboot loader`; 硬件: 断电按住 Update 键 + 插 Type-C 上电) / **MaskROM** (兜底) |
| **烧录命令** | `sudo upgrade_tool uf update.img` (整包); 单分区 `sudo upgrade_tool di -b boot.img` / `-dtbo` / `-p` |
| **擦除/低级格式化** | `sudo upgrade_tool ef update.img` / `sudo upgrade_tool lf update.img` |
| **回滚固件** | 重烧 Ubuntu `update.img` (220 `rk3576_linux` 编 `./build.sh updateimg` → `rockdev/update.img`); **烧前先确认镜像在** |
| **镜像内核对** | `md5sum update.img`; 分区地址用 `upgrade_tool` → `Device Partition Table` 核对 |
| **固件入仓?** | ❌ 不进仓 (`AGENTS.md` §12.8); 只记 md5 + 大小到 `build/logs/` |
| **gpt.img** | 7.5G, **USB 烧录不需要**(只有 SD 卡升级用), 打完包可直接删省盘 |

> **USB 直通实测 (2026-11-19)**: 板子 Android 态枚举 `2207:0006`, `adb reboot loader` 后变 `2207:350e`;
> 这一版 VMware **自动**接住了新身份(不需要再手动 connect), 但**不保证每次都这样** —— 若 `upgrade_tool ld` 报 `connected(0)`,
> 就在 VMware → Removable Devices 里把 Rockchip 设备再连一次, `flash_update.sh --wait 60` 会一直等。

### 3.1 Android 分区表 (官方 LKB3576, 核对用)

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

## 4. 硬件资源 / 引脚 (官方规格页)

| 资源 | 值 / 说明 |
|---|---|
| 供电 | **DC 12V**, 带过压/过流/浪涌/防反接保护 |
| 显示 | **1× HDMI 2.0 + 1× MIPI-DSI** —— 本机无 HDMI 显示器, Android 走远程桌面 (scrcpy 不依赖物理屏) |
| USB | **3× USB 3.0 Type-A (HOST) + 1× 全功能 Type-C** (Type-C 兼烧录/ADB/DP) |
| 视频输入 | 3 路 MIPI-CSI |
| 扩展槽 | 1× mini-PCIe (4G/5G / RK1808 NPU) + 1× **M.2 M-KEY 2242** (SSD/HDD) |
| 音频 | φ3.5 输出 + MIC 输入, 可带 10W@8Ω 立体声 |
| 网络 | **2× 千兆以太网** + 双频 **WiFi 6** (a/b/g/n/ac/ax), 可选 4G/5G |
| 数据口 | UART + RS485 |
| 尺寸 | 150 × 100 × 12.6 mm |
| 复位 | ⏳ 待核对 (板上有 Update 键; 复位键位置见硬件手册) |

## 5. 常用板上命令

```bash
# 版本 / 运行时长 / 硬件信息
cat /proc/device-tree/model; uname -r; uptime
free -h; df -h /
# 网络
ip -4 -o a; ip route
# Android 起来后
getprop ro.build.version.release; getprop ro.product.device; getprop ro.build.fingerprint
wm size; dumpsys SurfaceFlinger --display-id      # 无屏时确认显示已起来
# Android adb over TCP (远程桌面用)
setprop service.adb.tcp.port 5555; stop adbd; start adbd
# 进烧录模式
reboot loader
```

## 6. 参考 DTS / 内核配置 (Linux 侧, 来自 bob-220)

| 项 | 路径 |
|---|---|
| Ubuntu SDK 板级 defconfig | **`rockchip_rk3576_neardi_lz200_defconfig`** |
| 主人给的 defconfig 名 | `cs_lz200_linux_defconfig` (carystudio 定制变体; 与 neardi 原生同名板级) |
| 板级 DTS 目录 | `kernel/arch/arm64/boot/dts/rockchip/RK3576/neardi/` |
| 主 DTS | `rk3576-neardi-lz200.dtsi` (含 cam / hdmi / mipi-dsi / wifibt / gmac / usb 等 fragment) |
| u-boot | 同一 SDK 内, `rk3576` 板级配置 |
| Android 侧 | lunch **`rk3576_neardi_lz200-userdebug`** (官方, 与上面同板级) |

## 7. 无线 (SeekWave **SWT6652x / SV6316**, SDIO) — 现状 (2026-11-18 实测全通)

> 模块真身: 板载 **NEARDI FD7352S = SeekWave SV6316 (SWT6652x)**, SDIO func1 `1FFE:6316`, 主机 `2a320000.mmc`。
> 之前文档里写成 "SV6160" 是猜测 (驱动里 id 表有 `3607:6160`), 实测 SDIO id 是 `1ffe:6316`。

| 项 | 实测结论 |
|---|---|
| 硬件 | ✅ `/sys/bus/sdio/devices/mmc1:0001:1/uevent` = `SDIO_ID=1FFE:6316`; 驱动 `skw*` 匹配后 `wlan0` 出现 |
| 固件版本 | ✅ CP `trunk_W23.20.2-rev34632-rev34672-rev34436 20250318-02:11:08, slp=3` (v20 协议) |
| 扫描 | ✅ `scan_chn_num:39` → `scan result: 38`, 零断言 → `logs/20261118-1136-rk3576-skw-scan-ok.log` |
| 关联/认证 | ✅ `wpa_state=COMPLETED` / `Connected to e8:07:79:3d:5d:71` / `40MHz HE-MCS3 HE-NSS2` 137.6Mbit/s → `logs/20261118-1202-rk3576-skw-wifi-assoc-ok.log` (md5 `da26b20169e5331885e2c730d0ac3425`) |
| 蓝牙 | ✅ `state: ON` / `address 24:EF:B4:55:C2:41` / `name LKB3576`; HAL `[SKWBT]:scomm[1] read:820 ... pkt_type:7` 持续收发 |
| 开机自动 | ✅ 重启后不发任何命令: `skw/skw_bootcoms/skw_sdio` 三模块在 `/proc/modules`、`wlan0` 在、`cmd wifi status` = `Wifi is enabled`、BT `state: ON` |
| 依赖的 7 处改动 | 驱动 6 处 (`skw_sdio_main.c`/`skw_sdio_rx.c`/`skw_core.c`/`skw6160_config.h`/`skw_cfg80211.{c,h}`) + HAL 1 处 (`rk_wifi_ctrl.cpp`) —— 明细与"不改会怎样"见 `../src/README.md` §1.1 |
| 固件安装 | `src/firmware/swt6652x/` 5 个 → `install_board.sh` 改名成驱动硬编码名 → 板级 `firmware/` → 板级 mk 5 条 `PRODUCT_COPY_FILES` → `/vendor/etc/firmware/` |
| ⚠️ 坑 (已修) | `vendor/rockchip/common/wifi/wifi.mk` 会把**同名 EA6621Q 固件**也装到同一个 `/vendor/etc/firmware/` ⇒ 编出来的固件其实是错的 (499,196B/235,044B); 已由 `install_board.sh` 幂等 `filter-out` 修掉, 并用 `scripts/check_firmware_content.sh` 机器核 md5 |
| 框架 `cmd wifi connect-network` 不动 | 有以太网默认网时 AOSP 14 不下发未满足请求 (`hasConnectionRequests()`=false), 与驱动无关; WiFi 用 `wpa_cli` 验证 |
| 固件状态 | ✅ **已烧录验收 (2026-11-19 02:17 UTC)**: `update.img` 2,155,315,843B md5 `2c68b98adea30d3de8cc5fa667a11547` 经 `upgrade_tool uf` 烧进 eMMC (MaskROM 模式, `Upgrade firmware ok.`), **烧后 0 次 adb push** 复验全绿: 三模块 / `wlan0` / `Wifi is enabled` / 扫描 12 BSS / BT `state: ON` / 板上 5 固件 md5 == `src/` |
| 擦盘后默认态 | ⚠️ GPT 重建会擦 userdata ⇒ 开机 `Wifi is disabled` + `bluetooth_on=0`, 需 `svc wifi enable` / `cmd bluetooth_manager enable` 一次 (与驱动无关) |
| 关联(连 AP) + 上网 | ✅ **2026-11-19 06:47 UTC 全链路打通** (自建热点 `LKB_AP_TEST` 验证): 4-way `Key negotiation completed [PTK=CCMP GTK=CCMP]` → DHCP `wlan0 192.168.50.42/24` → `ping 223.5.5.5` 2/2 (24ms) → DNS 解析 `www.baidu.com` → 与 `eth0` 并存; 12/12 浸泡全绿 (`BSPASSERT=0`, BT ON) → `logs/20261119-0647-rk3576-sta-wifi-clean-verify.log` / `logs/20261119-0648-rk3576-sta-wifi-soak.log`; 空口证据 `captures/20261119-06{16,23,26,35}-*.pcap` |
| 依赖的 4 处新改动 (STA) | `skw_core.c`(TX 帧起点 = `8+声明gap` ⇒ 实推 2 字节 + 声明 0) / `skw_rx.c`(`SKW_LKB_RX_FRAME_OFF 18` + 自检直投 + `skw_eapol_iface()` 回退) / `skw_msg.c`(EAPOL 802.3/802.11 双形态) —— 明细见 `../src/README.md` §1.3 |

> 结论速记: **STA 关联 + DHCP + 上网已全链路打通, SoftAP 仍被 CP 固件断言挡住(需厂商更新)**; 剩最后一步 = 把本轮 ko 烧进整包后零 push 复验。

## 维护规则

- 板子换 IP / 换固件 / 换串口 → **当天**改本文件 + README 信息卡「服务器 / 板子」
- 固件只记 **md5 + 大小 + 取回路径**, 镜像本身不进仓 (`AGENTS.md` §12.8)
