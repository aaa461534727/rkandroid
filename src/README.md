# src/ — 只放**我改过的源码** (板级改动索引)

> 规矩出处: 顶层 `AGENTS.md` §23。**原厂 BSP 源码在仓外 SDK 树** (`~/linux/rk3576_android/work/radxa-rk3576-android14`, 见 `../sdk/README.md`), 这里只放**我加/改的文件**, 路径以 SDK 根为基准。

## 0. 一句话

- `src/<相对 SDK 根的路径>` = 我要装进 SDK 的文件; 用 `bash scripts/install_board.sh` 推进 SDK, 用 `--check` 验 md5。
- 改 SDK 里的**已跟踪文件** (例: 内核 dts `Makefile`) 由脚本按规则幂等打补丁, 不在 src 里存整份 Makefile。
- 🔴 **出固件前必须 `--check` 全绿** —— 否则编出来的固件缺这里的补丁 (WiFi 驱动 / 板级固件 / DTS), 只能又靠 `adb push` 补, 重烧就丢 (见 `../README.md` §6)。

## 1. 改动索引 (1 个应用: 板级适配 + 板载无线驱动)

| src 目录 / 文件 | 一句话作用 | 对应 SDK 路径 | 状态 |
|---|---|---|---|
| `kernel-6.1/arch/arm64/boot/dts/rockchip/` | LKB3576 (= neardi lz200) 的 13 个板级 fragment + `rk3576-lz200-android.dts` (Android 14 顶层 dts); `rk3576-neardi-lz200.dtsi` 里 `../rk3576-rk806.dtsi` 改成平铺 include, 且 `i2c1m0_xfer_pullup` 包进 `i2c1 { }` (否则 rk806 PMIC 不探测 → 无 `/dev/dri`) | `kernel-6.1/.../rockchip/` + 同目录 `Makefile` 加 1 行 dtb 登记 | ✅ 已在固件里验证 |
| `device/rockchip/rk3576/rk3576_lz200/` | 板级目录: `PRODUCT_KERNEL_DTS=rk3576-lz200-android` / `super=6GiB` / 去 `pcie_wifi.config` / 关 `MXC6655XA` / `PRODUCT_MODEL=LKB3576` / **5 条 `PRODUCT_COPY_FILES` 装板载无线固件** | `device/rockchip/rk3576/rk3576_lz200/` | ✅ |
| `firmware/swt6652x/` | 板载无线 (SeekWave SV6316 / SWT6652x) 全部运行期固件: CP 镜像 IRAM/DRAM、NV、校准 bin+ini。**源文件用厂商原名**, 由 `install_board.sh` 按驱动要求的名字装进板级 `firmware/` | `device/rockchip/rk3576/rk3576_lz200/firmware/` (`SWT6652_IRAM_SDIO.bin` → `ROM_EXEC_KERNEL_IRAM.bin` 等) | ✅ |
| `external/wifi_driver/ea6621q/` | 8 个驱动补丁 (6 个协议对齐 + 2 个「别把 CP 打死」, 见 §1.1/§1.2) | `external/wifi_driver/ea6621q/` 同名路径 | ✅ 前 6 个已在固件里验证; 后 2 个 2026-11-19 新增, 待烧录复验 |
| `frameworks/opt/net/wifi/libwifi_hal/rk_wifi_ctrl.cpp` | 芯片识别表加 SDIO `1ffe:6316` → ① WiFi HAL 按序 insmod skw 三模块 ② BT HAL 选 `libbt-vendor-seekwave.so` | `frameworks/opt/net/wifi/libwifi_hal/rk_wifi_ctrl.cpp` | ✅ |
| `packages/modules/Bluetooth/system/gd/stack_manager.cc` | BT 协议栈启动/关闭等待 3s/5s → **15s/15s** (见 §1.2) | `packages/modules/Bluetooth/system/gd/stack_manager.cc` | ✅ 已改, 待烧录复验 |

### 1.1 `external/wifi_driver/ea6621q/` 的 6 个补丁 (为什么板载 SV6316 不认原厂 ea6621q 驱动)

板载模块是 **NEARDI FD7352S = SWT6652x (SV6316/EA6316)**, SDIO `1FFE:6316`, CP 固件 `trunk_W23.20.2` (v20 协议)。原厂 `ea6621q` 驱动是给 EA6621Q(v19) 写的, 逐项对齐到 v20:

| 文件 | 改了什么 | 不改的现象 |
|---|---|---|
| `drivers/seekwaveplatform/sdio/skw_sdio_main.c` | SDIO id 表加 `{SDIO_DEVICE(0x1ffe, 0x6316)}` | `skw_sdio` 不 probe → `skw.ko` 起不来 |
| `drivers/seekwaveplatform/sdio/skw_sdio_rx.c` | `trunk_W...` 就绪包也 `complete(&download_done)` + 解析 `slp=` + `host_state=0` | `skw_check_cp_ready` 必超时 → `wifi boot failed` |
| `drivers/skwifi/skw_core.c` | `SKW_CMD_SET_SPD_ACTION` V2→V1 | 版本门禁 `-EINVAL` → `skw_stop_wifi_service` (WiFi 起来又停) |
| `include/linux/platform_data/skw6160_config.h` | `CONFIG_SKW_CHIP_ID "EA6316"` | `skw_get_chip_id()` `-ENOTSUPP` (原表只认 EA6621Q/EA6521Q) |
| `drivers/skwifi/skw_cfg80211.h` | ① `struct skw_scan_chan_info{chan_num,band,scan_flags}` ② `SKW_SCAN_FLAG_PASSIVE` BIT(15)→BIT(7) ③ `skw_join_param` 加 `u8 band` ④ `skw_join_resp` 扩到 4 字节 | ① 多信道扫描必撞 CP 断言 `BSPASSERT:...mms_interface.c-376` ② 关联 ack `status=7` → `skw_cmd_join ret:-7` |
| `drivers/skwifi/skw_cfg80211.c` | `skw_scan()` / `skw_sched_scan_start()` 改按三元组填信道; `skw_cmd_join()` 传 `to_skw_band(bss->channel->band)` | 同上 |

### 1.2 2026-11-19 新增: 别让「一次抖动」把整颗 CP 打死 (WiFi+BT 一起挂)

现象: 烧录后跑了 23 分钟, WiFi 一开始能用, 之后扫描全 `-5 (EIO)` / `wlan0 NO-CARRIER` / BT `state: OFF`,
必须重启板子才能恢复。根因**三条**, 都属「原厂默认行为在 sv6316 上太激进」:

| 文件 | 改了什么 | 不改的现象 |
|---|---|---|
| `drivers/skwifi/skw_rx.c` | 事件序列号对不上时: 原来 `skw_hw_assert(skw)` (直接给 CP 发 assert) → 改成 **按收到的 seq 重新对齐 + 丢弃这一个事件包** (`resync (no assert)`) | SDIO 单总线 WiFi+BT 共用, 丢一个事件包就 `send_modem_assert_command` → CP 断言 → WiFi+BT 全挂; `skw flags 0x8301` 之后所有命令 `mask 0x0` / `-EIO`, 只能重启板子 |
| `drivers/skwifi/skw_msg.c` | 命令超时 (2s): 原来**立刻** `set BLOCK_TX` + `skw_assert_schedule()` → 改成**连续 3 次**才断言; 前 2 次只丢这一条命令并清 `BLOCK_TX`; 收到正常 ACK 即清零计数 | 一次命令超时 = CP 被断言 + `BLOCK_TX` 永久置位 ⇒ 之后所有命令 `-EIO`, 同样只能重启 |
| `packages/modules/Bluetooth/system/gd/stack_manager.cc` | `StartUp` 等 3s → **15s**; `ShutDown` 5s → 15s | BT HAL `initialize()` 要跑 `skw_start_bt_service` (CP 需要重下固件时约 **2.0s**), 加开销必超 3s ⇒ `assertion 'init_status == std::future_status::ready' failed - Can't start stack, last instance: starting HciHalHidl` ⇒ 进程崩 ⇒ HAL `close()` 又 `skw_stop_bt_service` **把整颗 CP 停掉** (WiFi 一起死) ⇒ 与「CP 重启要 2s」形成死循环 (现场 30 次成对 start/stop) |

> 三条合起来 = ① 不再因为丢一个包就自杀 ② 真超时也先忍 2 次 ③ 即使要重下 CP 固件, BT 也来得及起来, 不再把自愈中的 CP 停掉。
> 现场证据: `logs/20261119-0252-rk3576-skw-cp-assert-wifi-dead.log` + `docs/PROGRESS.md` 2026-11-19 条目。


### 1.3 2026-11-19 新增: WiFi STA 关联打通 (CP 的 TX 帧起点 / RX 描述符布局与驱动假设不符)

现象: 能扫描、能 auth/assoc, 但 4-way 握手 / DHCP 全死 —— 2/4 到不了 AP; 3/4 到了不收; 拿到 `CTRL-EVENT-CONNECTED`
之后 DHCPOFFER 反复上空口而 `wlan0 RX packets = 0`。根因**四条**, 全部 `mon0` 空口 + dmesg hexdump 实证:

| 文件 | 改了什么 | 不改的现象 |
|---|---|---|
| `drivers/skwifi/skw_core.c` | 特殊直发路径 (`is_prot_filter` / `is_udp_filter` / `is_802_3_frame`, EAPOL 走这条): **实际推 2 字节把帧顶到偏移 8, 但 `desc_hdr->padding_gap` 声明 0**(新变量 `desc_gap`) | CP 的帧起点 = `8 + 驱动声明的 padding_gap`, **与实推字节数无关** ⇒ 帧、A3、ethertype 整体错位 2 字节 (空口: `DA:c9:27:1e:46:24:ef / 0x0103` 而非 `DA:68:8f:c9:27:1e:46 / 0x888e`) ⇒ 2/4 永远到不了 AP |
| `drivers/skwifi/skw_rx.c` | 新增 `SKW_LKB_RX_FRAME_OFF 18` / `SKW_LKB_RX_LEN_ADJ 6` + `skw_rx_eth_sane()` (目的地址是本站或组播 + ethertype 白名单 + 源非零) + `skw_rx_deliver_eth()` (丢自发回环 + `netif_receive_skb` 直投); 该分支放在 **peer/tid 判断之前** | 本板 CP 的以太网帧**固定偏移 18**、长度 `msdu_len+6`, desc 18 字节之后的 `tid/peer/sn/snap/eapol` 全落在载荷里 (实测 `tid=11/15`、`peer` 随机) ⇒ reorder / replay / iface 把数据帧整片丢掉 ⇒ DHCP 拿不到 IP |
| `drivers/skwifi/skw_rx.c` | 新增 `skw_eapol_iface()`: `desc->inst_id` 越界 (实测 3) 时回退到已注册的 STA/AP iface | `to_skw_iface(3)` 返回 NULL ⇒ `-EINVAL` ⇒ AP 的 3/4 被当垃圾丢, 握手停在 2/4 |
| `drivers/skwifi/skw_msg.c` | `skw_rx_eapol_deliver()` 同时兼容 **802.3 / 802.11** 两种形态 | PTK 未装时 CP 交上来的是**已转换的 802.3** 帧, 只认 802.11 会拒收 ⇒ 1/4 收不到 |

> 验收: `wlan0 192.168.50.42/24` + `ping 223.5.5.5` 2/2 (24ms) + DNS 解析 `www.baidu.com` 并通 + `eth0` 并存 + BT `state: ON`; 12/12 浸泡全绿。
> 现场证据: `captures/20261119-0616-*.pcap` / `-0623-*.pcap` / `-0626-*.pcap` / `-0635-*.pcap` + `logs/20261119-0633-rk3576-hostapd-4way-handshake.log` + `docs/PROGRESS.md` 2026-11-19 条目。


## 2. 目录约定

- 路径**照抄 SDK** (SDK 根为基准), 这样 `install_board.sh` 就是一对一拷贝。
- 过程备份 / 旧版本进 `../archive/`; 补丁思路写 `../docs/`。
- **u-boot 不动** (`PRODUCT_UBOOT_CONFIG ?= rk3576_defconfig`), 所以这里没有 `u-boot/`。
- 内核 config 暂不动 (`rockchip_defconfig` + `rk3576.config` 已含 binder/ashmem); 需要加外设开关时新建 `kernel-6.1/arch/arm64/configs/rk3576_lz200.config` 并登记到 `BoardConfig.mk`。
- **新增补丁文件只改 `scripts/install_board.sh` 里的 `FILE_MAP` / `FW_MAP` 两个数组**, 不用改脚本逻辑。

## 3. 每次改完必须做

```bash
bash scripts/install_board.sh          # src → SDK
bash scripts/install_board.sh --check  # md5 必须全一致 (否则编出来还是旧东西)
```
