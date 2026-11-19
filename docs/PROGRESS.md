# rk3576_android14 — 详细进度 (L2 权威记录)

> **本项目每次改动 / 解决问题, 都在「进度日志」最上面追加一条标准条目** (九字段, 见顶层 `AGENTS.md` §3.5)。
> 状态只写 `docs/project.json`; README / INDEX 由 `python3 bin/render` 生成。

## 进度日志 (倒序, 最新在最上)

### 2026-11-19 — WiFi STA 关联打通 (4-way + DHCP + 上网全链路): 空口实证 CP 的 TX 帧起点与 RX 描述符布局都和驱动假设不符

- **问题现象**: WiFi 能扫描、能发 auth/assoc, 但连任何 AP 都停在 4-way 握手: ① 早期 `EAPOL-Key 2/4` 永远到不了 AP(AP 侧 `sending 1/4` 一直重发到 `EAPOL-Key timeout` → deauth reason 15); ② 2/4 能上去了以后, AP 回 3/4 而板子不收(`invlid peer: 1, tid: 15, eapol: 1`), 握手原地死掉; ③ 4-way 全过(`Key negotiation completed [PTK=CCMP GTK=CCMP]` / `CTRL-EVENT-CONNECTED`)之后 DHCP 仍拿不到 IP, 宿主 `dnsmasq` 反复 `DHCPOFFER 192.168.50.42` 而板子 `wlan0 RX packets` 一直是 0。**以太网 `eth0` 全程正常**。
- **根因 (为什么)**: 四处, 全部空口抓包(`mon0`) + dmesg hexdump 实证:
  1. **CP 的 TX 帧起点 = `8 + 驱动声明的 padding_gap`, 与驱动实际推入多少填充字节无关** —— `skw_ndo_xmit` 特殊直发路径(`is_prot_filter`/`is_udp_filter`/`is_802_3_frame`, EAPOL 走这条)载荷布局是 `[desc_hdr 4][padding N][desc_conf 2][eth]`; 原代码只把 `desc_hdr` 对齐(N=0) ⇒ eth 落在偏移 6, CP 从 8 读 ⇒ **A3 与 EAPOL 载荷整体错位 2 字节**。空口实测错位帧: `SA:24:ef:b4:55:c2:3f DA:c9:27:1e:46:24:ef ... ethertype Unknown (0x0103)`(应为 `DA:68:8f:c9:27:1e:46 ethertype 0x888e`)。改成"实际推 2 字节"后 A3 仍错 ⇒ 声明 `padding_gap=2` 时 CP 从 10 读 ⇒ **证明 CP 只看声明值**; 最终解 = **实际推 2 字节(把帧顶到 8) + 声明 gap 0**。
  2. **CP 的 RX 布局与 `struct skw_rx_desc` 不符**: 以太网帧**固定从缓冲区偏移 18 开始**, `desc->msdu_offset` 恒 0, 帧长 = `desc->msdu_len + 6`(107→113B EAPOL-Key, 334→340B DHCP)。desc 18 字节之后的 `tid/peer/sn/snap/eapol` **全部落在载荷里**, 实测 `tid = 11/15`(≥SKW_NR_TID=8)、`peer = 0/3/9/10/15` 随机、`eapol` 位乱置 ⇒ reorder / replay / iface 选择把这批帧整片丢掉, 所以 3/4 和 DHCPOFFER 都"到了却收不到"。
  3. **`desc->inst_id` 也可能越界**: 实测 1/4 是 0, 3/4 是 **3**(`SKW_NR_IFACE` 之外) ⇒ `to_skw_iface(3)` 返回 NULL ⇒ `skw_rx_eapol_deliver` 直接 `-EINVAL`, 3/4 被当垃圾丢。
  4. **CP 会把板子自己发出的帧回环成 RX**(`src == 本机 MAC`, 实测 DHCPDISCOVER 回声) ⇒ 不丢会自己打断自己。
- **关键参数**: `SKW_LKB_RX_FRAME_OFF = 18` · `SKW_LKB_RX_LEN_ADJ = 6` · 特殊直发 `padding = 2` / `desc_gap = 0` · `SKW_DATA_ALIGN_SIZE = 4`; 正式 ko md5 **`04db703d96b2a13702609598bf272f06`**(602,568B, `strings` 已无任何探针串); 板载 MAC `24:ef:b4:55:c2:3f`, AP MAC `68:8f:c9:27:1e:46`; 测试热点 `LKB_AP_TEST` / ch6 / 192.168.50.1。
- **修改位置**:
  - `src/external/wifi_driver/ea6621q/drivers/skwifi/skw_core.c`: 新增 `u8 desc_gap` var → 特殊直发路径 `padding = 2` 但 `desc_hdr->padding_gap = desc_gap = 0`(PCIe 同类分支同步); EAPOL 日志降为 `skw_dbg` 并带 `gap` 字段。
  - `src/.../skwifi/skw_rx.c`: 新增 `skw_eapol_iface()`(实例号无效时回退到已注册 STA/AP iface) / `skw_rx_eth_sane()`(目的地址必须本机或组播 + ethertype 白名单 + 源非零) / `skw_rx_deliver_eth()`(丢自发回环、`netif_receive_skb` 直投、计数) + `#define SKW_LKB_RX_FRAME_OFF/LEN_ADJ`, 并把"带自检的直接投递"**提到 peer/tid 判断之前**(否则 `tid=11` 先被 EAPOL 分支吃掉)。
  - `src/.../skwifi/skw_msg.c`: `skw_rx_eapol_deliver()` 兼容 802.3 / 802.11 两形态(PTK 未装时 CP 交上来的已是 802.3)。
- **做了什么**: ① 本机 USB 网卡(rl8821cu)自建热点 + `mon0` 空口抓包 → 逐帧对比"驱动认为的字节" vs "空口实际字节" ② 先修 TX 偏移(两轮迭代: 推 2 字节 → 推 2 + 声明 0) ③ 再修 RX EAPOL 定位 + iface 回退 → 2/4/3/4/4/4 全过 ④ DHCP 仍不通 ⇒ hexdump 发现 18 字节前缀全是载荷碎片 ⇒ 加自检直投路径 → 一次拿到 IP ⑤ 清掉全部临时探针重编 clean ko → 回归(连接+IP+ping+DNS) ⑥ 12 轮 3 分钟浸泡。
- **证据 (证明修好)**:
  - 空口(决定性): `captures/20261119-0626-rk3576-eapol-2of4-fixed-air.pcap` — 板子发出的 2/4 帧 `SA:24:ef:b4:55:c2:3f DA:68:8f:c9:27:1e:46 ... ethertype EAPOL (0x888e), length 121: EAPOL key (3) v1, len 117`, A3/ethertype 全对; 对照(`captures/20261119-0616-rk3576-eapol-tx-shift2-air.pcap`)同一帧是 `DA:c9:27:1e:46:24:ef / 0x0103`。
  - 握手: `logs/20261119-0633-rk3576-hostapd-4way-handshake.log` (40 行, md5 `5b881b4b5d578112e65a8de2dd7e5db8`) — `1/4 → 2/4 → 3/4 → 4/4` 全序列 + `AP-STA-CONNECTED`。
  - DHCP: `captures/20261119-0635-rk3576-dhcp-offer-air.pcap` — 空口上 `68:8f:c9:27:1e:46 > 24:ef:b4:55:c2:3f ... Data IV: 1 Pad 20`(加密 DHCPOFFER) 确认真到了空口; 修 RX 后板侧 `wlan0 192.168.50.42/24`, `RX packets 13 / bytes 3582` 从 0 变活。
  - 全链路: `logs/20261119-0647-rk3576-sta-wifi-clean-verify.log` — `Wifi is connected to "LKB_AP_TEST"` / `Supplicant state: COMPLETED` / `IP: /192.168.50.42` / `NetworkCapabilities: [Transports: WIFI ... INTERNET ...]` / `ping 223.5.5.5` **2/2 (24ms)** / `ping www.baidu.com` 解析 `103.235.47.188` 并通 / 扫描出 BSS / **eth0 + wlan0 同时在线**(不再出现 `onNetworkUnwanted` 拆网)。
  - 浸泡: `logs/20261119-0648-rk3576-sta-wifi-soak.log` — **12/12** 采样全部 `eth0+wlan0 UP` + ping 2/2 + `BSPASSERT` 计数 0 + `bluetooth_on=1`; BT 在 WiFi 连接下 `state: ON` / `address: 24:EF:B4:55:C2:41`。
- **结论 / 状态**: ✅ **已修复并实机全链路验收通过** (2026-11-19); 正重编整包以便烧录固化(本条目先记 adb push 阶段的验收, 烧录零 push 复验见后续条目)。
- **回滚方案**: ① 源码回滚 = `cd <SDK> && git checkout -- external/wifi_driver/ea6621q/drivers/skwifi/{skw_core.c,skw_rx.c,skw_msg.c}`(或从 `src/` 反向推回上一版) + `build_wifi_ko.sh ea6621q` + 重编 ② 固件回滚 = 重烧 `update.img` md5 `07ba7631e2eee2909aba0558a4fce77d`(WiFi 只能扫描、不能关联, 但 eth0 + BT 可用) ③ 板子临时退路 = 只用 `eth0` 以太网。
- **涉及文件**: `src/external/wifi_driver/ea6621q/drivers/skwifi/skw_core.c` / `skw_rx.c` / `skw_msg.c` / `scripts/lkb_test_ap.sh`(自建热点取证脚本, 本轮新增) / `captures/20261119-0616-rk3576-eapol-tx-shift2-air.pcap` / `captures/20261119-0623-rk3576-eapol-tx-pad2-gap2-air.pcap` / `captures/20261119-0626-rk3576-eapol-2of4-fixed-air.pcap` / `captures/20261119-0635-rk3576-dhcp-offer-air.pcap` / `logs/20261119-0633-rk3576-hostapd-4way-handshake.log` / `logs/20261119-0647-rk3576-sta-wifi-clean-verify.log` / `logs/20261119-0648-rk3576-sta-wifi-soak.log` / `docs/CAPTURES.md` / `docs/WORKLOG.md`

### 2026-11-19 — 修"跑一段时间 WiFi+蓝牙一起挂": 驱动不再因丢一个 SDIO 包把整颗 CP 断言打死, BT 栈超时 3s→15s

- **问题现象**: 上一版整包烧进 eMMC 后正常跑了 23 分钟（板子开机 1368s 起扫描数据开始错乱), 之后 **WiFi 与蓝牙同时永久挂死**: `cmd wifi start-scan` 全返回 `-5`, `wlan0 NO-CARRIER`, `cmd wifi status` 仍显示 enabled 但扫不到任何东西, `settings get global bluetooth_on` 一直 `0`/`state: OFF`; **只有重启板子才能恢复**。用户描述"WiFi 一开始能用, 后来就不能用了, 蓝牙也一样"。
- **根因 (为什么)**: 三条, 全部有代码 + dmesg/logcat 证据:
  1. **驱动自己把 CP 打死** — `external/wifi_driver/ea6621q/drivers/skwifi/skw_rx.c:1716` `case SKW_MSG_EVENT: if (++skw->skw_event_sn != msg->seq) skw_hw_assert(skw);` ⇒ WiFi 与蓝牙**共用同一条 SDIO 总线**, 偶发丢/重一个事件包 → 序列号不符 → `skw_hw_assert()` → `send_modem_assert_command()` → **整颗 CP 被断言**(WiFi+BT 一起死), 且 `SKW_FLAG_BLOCK_TX` 置位后 `skw_cmd_tx_allowed` 以 `mask: 0x0` 永久 `-EIO`。
  2. **单次命令超时也立刻断言** — `drivers/skwifi/skw_msg.c` `skw_cmd_timeout_fn()`: 单次 2s 超时即 `set_bit(SKW_FLAG_BLOCK_TX)` + `skw_assert_schedule()`, 同样永久封死。
  3. **BT 栈 3s 超时 → 崩 → 把自愈中的 CP 停掉, 形成死循环** — `packages/modules/Bluetooth/system/gd/stack_manager.cc:46` `future.wait_for(std::chrono::seconds(3))`; BT HAL `initialize()` 要跑 `skw_start_bt_service`, **CP 需要重下固件时约 2.0s**, 加开销必超 3s ⇒ logcat `02:50:15.214 BluetoothHci::initialize()` → `02:50:18.211 init_status == 1`(timeout) → `FATAL Can't start stack, last instance: starting HciHalHidl` ⇒ 进程崩 ⇒ HAL `close()` → `skw_stop_bt_service` **停整颗 CP** ⇒ 现场 `skw_start_bt_service` / `skw_stop_bt_service` 各 **30 次**。
  - **时间线校正** (此前判读反了): 板子 02:19:14 开机, `dmesg 1374.9s`(02:42:08) CP 断言, 最早 `tombstone_01` = **02:42:19**(晚 11s) ⇒ **先 CP 断言, 后 BT 崩**, 不是 BT 先崩。
  - **自愈本来有效**: `1375.99 DOWNLOAD BIN TO CP` → `1376.06 Recovery ok`, 但 1.6s 后 BT 的 `stop_bt_service` 把刚救回的 CP 停掉。
- **关键参数**: `SKW_CMD_TMO_RETRY=3`(连续 3 次命令超时才断言); BT `kStackStartTimeout=15s` / `kStackStopTimeout=15s`(原 3s/5s); 新整包 `update.img` 2,155,311,747B md5 `07ba7631e2eee2909aba0558a4fce77d`; 板上 `skw.ko` md5 `655739358d164146ae3898eb4e05e617`; 芯片 `check_chipid: SV6316 used SDIO20`。
- **修改位置**: ① `src/external/wifi_driver/ea6621q/drivers/skwifi/skw_rx.c`(seq 不符 → `skw->skw_event_sn = msg->seq` + 丢这一个包, 不再 `skw_hw_assert`) ② `src/.../drivers/skwifi/skw_msg.c`(`skw_cmd_timeout_fn` 前 2 次只清 `BLOCK_TX` 继续, `skw_cmd_ack_handler` 收到 ACK 清零) ③ `src/packages/modules/Bluetooth/system/gd/stack_manager.cc`(15s/15s) ④ `scripts/install_board.sh` `FILE_MAP` 增 `skw_msg.c`/`skw_rx.c`/`stack_manager.cc` ⑤ `src/README.md` §1.2 增三条补丁"不改会怎样"表。
- **做了什么**: ① 落盘现场 → 定位三条根因(代码 + dmesg + logcat 时间线对齐) ② 改 3 个文件 → `install_board.sh` 推 SDK → `--check` 10 个单文件全一致 ③ `build_wifi_ko.sh ea6621q` 重编 `skw.ko`, `strings` 确认两条新字符串进 ko ④ `./build.sh -A -u -J6` 出整包(24:14 + 打包) → `check_firmware_content.sh` 全 OK ⑤ 登记 `build/MD5SUMS.txt` → `flash_update.sh --wait 60` 烧录 ⑥ **零 adb push** 复验 + 压力复验(10 轮扫描 / 3 轮 BT 开关 / 10 分钟浸泡)。
- **证据 (证明修好)**:
  - 编译: `build/logs/20261119-0302-build-android-incremental-bt-timeout-wifi-resync.log` → `Build android ok!` (24:14) / `Make image ok!` / `Make update image ok!` / `BUILD_EXIT=0`; ko 重编日志 `build/logs/20261119-0301-build-wifi-ko-skwwifi-fix.log`
  - 烧录: `build/logs/20261119-0340-flash-update-BT15s-WiFiResync.log` → md5 实际==登记 / `Pid=0x350e Mode=Loader` / `Download Firmware Success` / **`Upgrade firmware ok.`** / `FLASH_EXIT=0`
  - 产物门禁: `bash scripts/check_firmware_content.sh` → **不一致 0 项**; 产物 `vendor_dlkm/skw.ko` 含 `resync (no assert)` + `cmd timeout %d/%d`
  - 板上是**新**固件: `/vendor_dlkm/lib/modules/skw.ko` md5 `655739358d164146ae3898eb4e05e617` == 刚编产物; 5 个板载固件 md5 全 == `src/firmware/swt6652x/md5.txt`
  - 🔴 **新补丁真的挡住了旧故障**(决定性): 压力测试中真实发生丢包 —— `[158.734153] skw_rx_cb: invalid event seq: 69, expect: 68, resync (no assert)` ⇒ 旧固件同一毫秒就会 `send_modem_assert_command`, 新版只丢该包继续; 压测后 `BSPASSERT=0` / `assert_schedule=0` / `cmd timeout=0` / `resync=1` / `mask: 0x0`=0, `skw_scan_done: scan result: 20`
  - BT 反复开关 3 轮: 每轮 `bluetooth_on 0→1`, WiFi 全程 `Wifi is enabled`; 关 BT 后扫描仍出 12 条结果(CP 未被停)
  - 详细日志: `logs/20261119-0346-rk3576-wifi-bt-stability-verify.log` (247 行, md5 `90cf22c79b0e771ded1416041700589d`)
  - 🔴 **长跑跨过旧故障点**: 第二轮浸泡 15 分钟跑到 **uptime 1938s (32 分钟)**, 旧固件在 **1374s** 就必挂; 值班点 1158s / 1313s / 1468s / 1627s / 1782s **全部** `Wifi is enabled` + `bluetooth_on=1`; 终验 `BSPASSERT=0` / `assert_schedule=0` / `resync=2` / `cmd timeout=0` / `mask: 0x0`=0 / 扫描 12 BSS; **第 2 次 `resync` 发生在 `uptime 1625.3s`, 已经在旧故障点之后** —— 同样的丢包时刻旧固件必打死 CP, 新版只重对齐继续
  - 浸泡日志: `logs/20261119-0346-rk3576-wifi-bt-10min-soak.log`(60 轮) + `logs/20261119-0358-rk3576-wifi-bt-15min-soak-past-23min.log`(90 轮) + 终验 `logs/20261119-0414-rk3576-after-23min-stability-final.log` (43 行, md5 `ac0ea81038257e4c50a05d236042fa58`)
- **结论 / 状态**: ✅ **已修复并烧录复验通过** (2026-11-19); 剩关联(连 AP)复验待主人给热点密码。
- **回滚方案**: ① 源码回滚 = `git checkout -- src/external/wifi_driver/ea6621q/drivers/skwifi/skw_rx.c src/.../skw_msg.c src/packages/modules/Bluetooth/system/gd/stack_manager.cc` + `install_board.sh` + 重编 ② 固件回滚 = 重烧上一版 `update.img` md5 `2c68b98adea30d3de8cc5fa667a11547`(把 `build/MD5SUMS.txt` 登记行改回旧 md5 让门禁放行) ③ 板子临时退路 = `eth0` 以太网一直可用
- **涉及文件**: `src/external/wifi_driver/ea6621q/drivers/skwifi/skw_rx.c` / `.../skw_msg.c` / `src/packages/modules/Bluetooth/system/gd/stack_manager.cc` / `scripts/install_board.sh` / `src/README.md` / `build/MD5SUMS.txt` / `docs/WORKLOG.md` / `docs/PROGRESS.md` / `docs/CAPTURES.md`(无需新增, 证据是文字日志) / `logs/20261119-0252-rk3576-skw-cp-assert-wifi-dead.log` / `logs/20261119-0346-rk3576-wifi-bt-stability-verify.log` / `build/logs/20261119-0301-build-wifi-ko-skwwifi-fix.log` / `build/logs/20261119-0302-build-android-incremental-bt-timeout-wifi-resync.log` / `build/logs/20261119-0340-flash-update-BT15s-WiFiResync.log`

### 2026-11-19 — 整包 update.img 烧进 eMMC 并"零 adb push"复验: WiFi/蓝牙功能确认来自固件本身

- **问题现象**: 2026-11-18 把 WiFi/蓝牙六补丁 + 五固件做进 `src/` 并重编出 `update.img`(md5 `2c68b98adea30d3de8cc5fa667a11547`), 但**一直没烧进板子** —— 缺的是物理侧 USB 直通: ① `adb reboot loader` 后 VMware 只记住旧设备身份 `2207:0006`(Android), U-Boot rockusb 是**新身份**, 不会自动接进虚机 ⇒ `upgrade_tool ld` = `connected(0)`; ② 板子侧 `UDC state=addressed`(不是 `configured`) + `sys.usb.state` 为空 = 宿主只给地址没接管。若跳过烧录, 只能说"adb push 过的板子上好用", 不等于交付 (§23.13)。
- **根因 (为什么)**: 不是软件问题, 是 **USB 设备身份在 mode 切换时变化** ⇒ VMware 的单设备记忆失效; 且 LKB3576 **没有 TF 卡槽**(板上只有 `mmcblk0` eMMC + `mmc1` SDIO WiFi), Rockchip "SD 升级卡"兜底路线不成立 ⇒ `super` 分区只能走 USB/MaskROM。
- **关键参数**: 烧录工具 `RKTools/linux/Linux_Upgrade_Tool/upgrade_tool_v2.30_for_linux/upgrade_tool`; 进虚机后枚举 `2207:0006`(Android) / 烧录模式 `2207:350e Mode=Maskrom`; `update.img` 2,155,315,843B md5 `2c68b98adea30d3de8cc5fa667a11547`; 板子 IP `10.0.102.185/20`, USB adb 序列号 `826226b8b84c7930`。
- **修改位置**: ① 新增 `scripts/flash_update.sh`(烧前核 `build/MD5SUMS.txt` 登记 md5、`--wait` 轮询 `upgrade_tool ld`、检测到 USB adb 就自动 `reboot loader`、烧完打印 `FLASH_EXIT`) ② `scripts/README.md` 增一行(标🔴会重建 GPT/重写 eMMC) ③ 本文件 + `docs/WORKLOG.md` + `docs/BOARD.md` + `docs/project.json` 记证据。
- **做了什么**: ① 主人在 VMware 里把 `2207:0006` 连到虚机 → `adb devices` 看到 USB 设备 ② 脚本自动 `reboot loader`(板子进 loader spinner), 再让主人 attach 新的 `2207:350e` ③ 脚本发现 `connected(1) Mode=Maskrom` 后执行 `upgrade_tool uf update.img`(md5 门禁先放行) ④ 烧完板子自启, **全程不做任何 adb push**, 直接跑验收命令。
- **证据 (证明修好)**:
  - 烧录日志 `build/logs/20261119-0217-flash-update-img-wifi-bt.log`: md5 实际==登记; `DevNo=1 Vid=0x2207,Pid=0x350e Mode=Maskrom`; `Download Boot Success` → `Test Device Success` → `Check Chip Success` → `Get FlashInfo Success` → `Prepare IDB Success` → `Download IDB Success` → `Download Firmware Success` → **`Upgrade firmware ok.`** → `FLASH_EXIT=0`
  - 复验日志 `logs/20261119-0222-rk3576-verify-after-flash-wifi-bt.log` (md5 `42ea98732b37ac2f2a34b884c837a6a9`, 88 行):
    - `getprop sys.boot_completed` = `1`; `ro.product.model` = `LKB3576`; `ro.build.version.release` = `14`
    - `/proc/modules`: `skw 380928` / `skw_bootcoms 45056 1 skw` / `skw_sdio 86016 1 skw_bootcoms`
    - `ip -br link show wlan0` → `UP` + MAC `24:ef:b4:55:c2:3f`
    - `cmd wifi status` → `Wifi is enabled`
    - `cmd wifi list-scan-results` → **12 个 BSS**(TOTOLINK_X5000R / carystudio-Meeting-2.4G / CMCC-0348 …)
    - `dmesg | grep -c BSPASSERT` = **0**; `skw_cmd *EIO` = **0**
    - `settings get global bluetooth_on` = `1`; `dumpsys bluetooth_manager` → `state: ON` / `address: 24:EF:B4:55:C2:41` / `name: LKB3576`; logcat 持续 `[SKWBT]:scomm[1] read:820 … pkt_type:7`
    - 板上 `md5sum /vendor/etc/firmware/*`: IRAM `1c2fd6cf6f701eb7db49ea9ab792fcb7` / DRAM `12d0dd187f7be56d75f30d7d48d302c1` / EA6316 bin `479045151f0ee09badb5bdfcb327c8e5` + ini `ad5c989b1fd4fab1bc952fba6c8429d9` / NV `441018525208457705bf09a8ee3c1093` —— **逐一 == `src/firmware/swt6652x/md5.txt`**, 证明镜像里不是 EA6621Q 错版(那次事故为 499,196B/235,044B)
- **结论 / 状态**: ✅ **烧录验收通过** (2026-11-19, 主人指令"烧完再复验"已闭环); 剩一项: **关联(连 AP)复验待补** —— `WiFi_3D5D71`(手机热点) 当时不在扫描列表且密码未随仓保存, 需热点打开 + 密码; 驱动侧关联参数(第 6 处补丁 `join_param.band`)已于 2026-11-18 实机 `wpa_state=COMPLETED` 验证过。
- **回滚方案**: ① 固件回滚 = 重烧旧整包(md5 `377c1fc7bd987dcaa38376d893bafcb8`), 把 `build/MD5SUMS.txt` 登记行改成旧 md5 即可让 `flash_update.sh` 放行 ② 板子侧退路 = 以太网 `eth0` 一直可用 ③ 源码回滚见 2026-11-18 条目。
- **涉及文件**: `scripts/flash_update.sh`(新) / `scripts/README.md` / `docs/PROGRESS.md` / `docs/WORKLOG.md` / `docs/BOARD.md` / `docs/project.json` / `build/logs/20261119-0217-flash-update-img-wifi-bt.log` / `logs/20261119-0222-rk3576-verify-after-flash-wifi-bt.log`

### 2026-11-18 — 板载 WiFi(SWT6652x/SV6316) + 蓝牙全部打通, 并把成果落进 SDK 重编整包固件

- **问题现象**: 板载 NEARDI FD7352S (SeekWave **SV6316 / SWT6652x**, SDIO `1FFE:6316` @ `2a320000.mmc`) 在 Android 14 下 `wlan0` 根本不存在: `skw.ko` 加载后 `wifi boot failed`; 扫描一开就撞 CP 断言 (`BSPASSERT:mms_interface.c-376` → 后续命令全 `-EIO`); 关联被拒 (`skw_cmd_join ret:-7`); 蓝牙 `state: OFF`。这些都是在板子上用 `adb push` 一个个试出来的, 重烧固件就丢。
- **根因 (为什么)**: 原厂 `ea6621q` 驱动是给 **EA6621Q(v19 协议)** 写的, 而板载固件是 **SWT6652x v20 (`trunk_W23.20.2-rev34632-rev34672-rev34436 20250318-02:11:08`)**, 协议差异逐条对上才通:
  1. **SDIO 匹配**: `skw_sdio_ids[]` 只有 `3607:6160` 等, 板子报 `1ffe:6316` ⇒ `skw_sdio` 不 probe, `sdio_dev_host` 永远 NULL。
  2. **CP 就绪包**: v20 的就绪包是 `trunk_W...` 前缀(不是老固件的 `WIFIREADY`), `skw_sdio2_handle_packet()` 里 `trunk_W` 分支只解析不回 `complete(&download_done)` ⇒ `skw_check_cp_ready()` 必超时 ⇒ `wifi boot failed`。
  3. **命令版本**: `SKW_CMD_SET_SPD_ACTION` 驱动按 V2 发, 固件只实现 V1 ⇒ 版本门禁 `-EINVAL` ⇒ `skw_stop_wifi_service`(WiFi 起来又停)。
  4. **芯片 ID**: `skw_get_chip_id()` 表里没有 EA6316 ⇒ `-ENOTSUPP`; 且 `CONFIG_SKW_CHIP_ID` 不是 `EA6316` 就匹配不上校准文件名。
  5. **扫描协议**: v20 每个信道是 `{u8 chan_num; u8 band; u8 scan_flags}` 三元组(不是 `u16` 信道号), 且 `SKW_SCAN_FLAG_PASSIVE` 在 **BIT(7)**(不是 BIT(15)) ⇒ 多信道扫描错位 ⇒ CP 断言。
  6. **关联参数**: `skw_join_param` 缺 `u8 band` 字段, ack `status=7`(参数非法)。
  7. **BT 不认**: `rk_wifi_ctrl.cpp` 的 `supported_wifi_devices[]` 没有 `1ffe:6316` ⇒ ① WiFi 三模块不被 HAL 按序 insmod ② BT HAL 不选 `libbt-vendor-seekwave.so`。
- **关键参数**: SDIO `1FFE:6316`; CP `trunk_W23.20.2-...` `slp=3`; 4 个运行期固件 IRAM `1c2fd6cf6f701eb7db49ea9ab792fcb7`(697,852B) / DRAM `12d0dd187f7be56d75f30d7d48d302c1`(397,068B) / `SEEKWAVE_NV_SWT6652_SHARE.bin`(20B) / `EA6316_SEEKWAVE_R00006.bin` `479045151f0ee09badb5bdfcb327c8e5`(5,234B)+`.ini`; 关联实测 `40MHz HE-MCS3 HE-NSS2` 137.6Mbit/s; BT `24:EF:B4:55:C2:41`。
- **修改位置**: (全部由 `scripts/install_board.sh` 从主仓 `src/` 推 SDK)
  - `src/external/wifi_driver/ea6621q/drivers/seekwaveplatform/sdio/skw_sdio_main.c` (SDIO id 表)
  - `src/external/wifi_driver/ea6621q/drivers/seekwaveplatform/sdio/skw_sdio_rx.c` (trunk_W 就绪包)
  - `src/external/wifi_driver/ea6621q/drivers/skwifi/skw_core.c` (cmd 版本)
  - `src/external/wifi_driver/ea6621q/include/linux/platform_data/skw6160_config.h` (`EA6316`)
  - `src/external/wifi_driver/ea6621q/drivers/skwifi/skw_cfg80211.{c,h}` (扫描三元组 / PASSIVE 位 / join band)
  - `src/frameworks/opt/net/wifi/libwifi_hal/rk_wifi_ctrl.cpp` (`{"SKW6160","1ffe:6316"}`)
  - `src/firmware/swt6652x/*` (5 个固件) + `src/device/.../rk3576_lz200.mk` (5 条 `PRODUCT_COPY_FILES`)
  - `scripts/install_board.sh` (新增 `FILE_MAP` 7 文件 + `FW_MAP` 5 固件含改名 + `vendor wifi.mk` 幂等 `filter-out` 补丁)
  - `scripts/check_firmware_content.sh` (新增: 产物 md5 == src md5 的机器门禁)
- **做了什么**: ① 逐项对齐 v19→v20 协议改 6 处驱动 + 1 处 HAL ② 每个补丁都在板子上实测通过 ③ 全部回灌 `src/` 并扩展同步脚本 ④ 板级 mk 装 5 个固件 ⑤ 重编整包 → 发现**固件被 EA6621Q 版覆盖**(见下) ⑥ 给 `vendor/rockchip/common/wifi/wifi.mk` 打 `filter-out` 补丁, 只让板级 `firmware/` 提供这两个名字 ⑦ 增量重编 `vendor+super` + 重打 `update.img` ⑧ 新增产物内容校验脚本并跑全绿。
- **证据 (证明修好)**:
  - WiFi 关联: `wpa_state=COMPLETED` / `Connected to e8:07:79:3d:5d:71` / `40MHz HE-MCS3 HE-NSS2 137.6Mbit/s` → `logs/20261118-1202-rk3576-skw-wifi-assoc-ok.log` (md5 `da26b20169e5331885e2c730d0ac3425`)
  - 扫描: `scan_chn_num:39` → `scan result: 38`, 零断言 → `logs/20261118-1136-rk3576-skw-scan-ok.log`
  - 蓝牙: `state: ON / address: 24:EF:B4:55:C2:41 / name: LKB3576` + `[SKWBT]:scomm[1] read:820`
  - 重启自动恢复: 不发任何命令, `/proc/modules` 有 skw 三模块 / `wlan0` 在 / `Wifi is enabled` / BT `state: ON`
  - **固件冲突根因证据**: `out/build-rk3576_lz200.ninja` 里 `build out/.../vendor/etc/firmware/ROM_EXEC_KERNEL_IRAM.bin: rule342515 vendor/rockchip/common/wifi/firmware/ROM_EXEC_KERNEL_IRAM.bin`(错版 499,196B); 修后同一条变成 `... device/rockchip/rk3576/rk3576_lz200/firmware/ROM_EXEC_KERNEL_IRAM.bin`
  - **修后产物校验**: `bash scripts/check_firmware_content.sh` → 逐项 `OK`, 不一致 0 项 (IRAM 697,852B md5 `1c2fd6cf…` / DRAM 397,068B md5 `12d0dd18…` / `skw.ko` md5 `e7228310…` / 两个 `librkwifi-ctrl.so` 均含 `SKW6160`+`1ffe:6316` / `wifi.load` 含 3 个 skw)
  - **烧录**: `build/logs/20261119-0217-flash-update-img-wifi-bt.log` —— 烧前 md5 门禁通过 (实际==登记 `2c68b98a…`), `DevNo=1 Vid=0x2207,Pid=0x350e Mode=Maskrom`, `Download Boot Success` / `Test Device Success` / `Check Chip Success` / `Get FlashInfo Success` / `Download IDB Success` / `Download Firmware Success` / `Upgrade firmware ok.` / `FLASH_EXIT=0`
  - **烧后复验 (不 push)**: `logs/20261119-0222-rk3576-verify-after-flash-wifi-bt.log` (md5 `42ea98732b37ac2f2a34b884c837a6a9`, 88 行) —— 三模块 / wlan0 / `Wifi is enabled` / 扫描 12 BSS / BT ON / 板上固件 5 个 md5 / `BSPASSERT` 0
  - **新整包**: `update.img` **2,155,315,843B md5 `2c68b98adea30d3de8cc5fa667a11547`** (已登 `build/MD5SUMS.txt`); 编译日志 `build/logs/20261118-1210-build-android-u-wifi-bt.log`(`BUILD_FULL_EXIT=0`, build 23:22) + `build/logs/20261118-1248-rebuild-vendor-super.log`(`MAKE_SUPER_EXIT=0`) + `build/logs/20261118-1258-pack-update-img-wifi-bt.log`(`PACK_EXIT=0`)
- **结论 / 状态**: ✅ **固件已带全部功能并已烧录验收** (烧录与复验证据见 2026-11-19 条目): ① `sys.boot_completed=1` (Android 14) ② `/proc/modules` 有 `skw`/`skw_bootcoms`/`skw_sdio` 三模块 ③ `wlan0` 在 (MAC `24:ef:b4:55:c2:3f`) ④ `cmd wifi status` = `Wifi is enabled`, 扫描 `cmd wifi list-scan-results` 出 **12 个 BSS** ⑤ `BSPASSERT` 0 次 / `skw_cmd *EIO` 0 次 ⑥ BT `state: ON` / `address 24:EF:B4:55:C2:41` / `name LKB3576`, logcat 持续 `[SKWBT]:scomm[1] read:820...` ⑦ 板上 `/vendor/etc/firmware` 五个固件 md5 **逐一 == `src/firmware/swt6652x/md5.txt`** (IRAM `1c2fd6cf…` / DRAM `12d0dd18…` / EA6316 bin `479045…` + ini `ad5c98…` / NV `441018…`) ⇒ 证明"目的路径撞车"已彻底修好, 镜像里是 SWT6652x 正确版本。**唯一未做**: 关联(连 AP) 复验 —— `WiFi_3D5D71`(手机热点) 当前不在扫描列表且密码未留存, 等热点打开+密码后补一条。
- **回滚方案**: ① 固件回滚: 重烧旧整包 (旧 md5 `377c1fc7bd987dcaa38376d893bafcb8`, 或 `archive/` 里留的版本); 烧录脚本 `scripts/flash_update.sh` 烧前会核 md5, 想烧旧包就把 `build/MD5SUMS.txt` 的登记行改成旧包 md5 或删掉该行 ② 源码回滚: `git -C <SDK> checkout -- external/wifi_driver frameworks/opt/net/wifi/libwifi_hal` + `git -C vendor/rockchip/common checkout -- wifi/wifi.mk`(或删掉 `filter-out` 两行) ③ 板子侧临时退路: `wlan0` 不可用时以太网 `eth0` 仍正常
- **涉及文件**: 见「修改位置」清单; 文档 `README.md`(编译铁律) / `src/README.md`(补丁索引) / `docs/BUILD_ANDROID.md`(§6 编译流程) / `docs/BOARD.md`(§7 WiFi/BT) / 顶层 `docs/rules/23-src-vs-sdk.md`(新增 §23.13 编译铁律)

### 2026-11-18 — Android 14 在 LKB3576 真正启动并渲染桌面 + 无屏浏览器远程显示/操控打通

- **问题现象**: 整包编译与烧录都成功（`update.img` md5 `377c1fc7…`），但开机后 `hwcomposer-3` 直接 `SIGABRT`，约 120s 后 `RescueParty` 强制重启（无限循环），永远到不了桌面；`/dev/dri` 根本不存在；后来靠 `recovery` 侧手工 `make_f2fs` 清完 metadata/userdata 才进了正常启动，但显示依然是黑的（无 HDMI、无 `/dev/dri/card0`）。修复过程中还出现「改了 DTB 但内核行为不变」的假象。
- **根因 (为什么)**: **两层**真因，缺一都解释不通：
  1. **i2c1 整条总线没起来** → 我们自建的板级 DTS `rk3576-neardi-lz200.dtsi` 里为了复刻厂家 Ubuntu 内核的「带上拉的 i2c1 引脚组」，新增了 `i2c1m0_xfer_pullup` 节点，但**直接挂在 `&pinctrl` 下**（当成一个 function），而 RK pinctrl 只把「function 节点（`i2c1 { }`）的子节点」注册成 group ⇒ `rockchip_dt_node_to_map()` 按名查不到 ⇒ dmesg `rockchip-pinctrl pinctrl: unable to find group for node i2c1m0-xfer-pullup` ⇒ i2c1 控制器 probe 返回 `-EINVAL` ⇒ 板上只有 `i2c-0/2/3/4/5/7`，**没有 i2c-1** ⇒ 挂在 i2c1@0x23 的 **rk806 PMIC 整颗不探测** ⇒ `DCDC_REG2/4/7/8` + `PLDO_REG1` 这些供电全缺 ⇒ `vop / dsi / npu / adc` 全部 deferred probe ⇒ 无 DRM 设备 ⇒ `hwcomposer-3` 拿不到 `/dev/dri/card0` 直接 abort。
  2. **内核真正用的 DTB 不在 boot.img 文件尾**：Rockchip U-Boot 的 `rockchip_read_dtb_file()` 走的是 boot.img **`second` 段（387,072 字节）= resource image**，DTB 从 resource image 里解出来（`resource_setup_ram_list`），文件尾那个 `dtb` 段（`dtb_size` = 298,179）在 AVB 流程里并不作为内核 FDT ⇒ 所以第一次只补文件尾 DTB 完全无效，必须重打 `resource.img`。
- **关键参数**:
  - 板级修复: `i2c1m0_xfer_pullup` 改为 `&pinctrl { i2c1 { i2c1m0_xfer_pullup: … } }`（引脚 `<0 RK_PB2 11 &pcfg_pull_up>` / `<0 RK_PB3 11 &pcfg_pull_up>` 不变）
  - 新 DTB: `rk3576-lz200-android.dtb` **298,187 字节**（旧 298,179，+8）、md5 `1c347bb499b5d81698a5e0e71249897c`、FDT `totalsize=298187 ver=17/16 struct=271616 strings=26515`
  - `resource.img` **387,072 字节**（与板上 second 段等长，所以 `second_size` 不用改）、md5 `c4ea410d3bfe027234a261f0ad28ced0`、内含 FDT @0x1600
  - 分区/偏移: boot 分区 LBA 0xc800；**second(resource) 段 LBA 75440**（`75440×512 = 38,629,280`）；boot.img 头 `dtb_size` 在文件偏移 **1648**，`id`（AVB SHA1）在偏移 **576**
  - AVB 哈希: U-Boot 打印的 `Hash real: 0xd559c8b0…9fdd2ff9` 是**字节序**，写入要按小端拆字 `0xB0C859D5 0x5119351F 0x961B3B09 0xD53AE479 0xF92FDD9F`，写到 boot 分区 LBA 51201（0xc801）偏移 64
  - U-Boot `mw.l` 的第 3 个参数是 **count 不是值** ⇒ 多值必须分条写
  - 串口注入通道: recovery/console shell 里 `echo '<base64 200字符>' >> f.b64` 逐行注入 + `base64 -d`，实测 **42 KB/s**，64KB 随机数据 md5 完全一致；工具 `scripts/inject_over_serial.py`
  - 启动时序: 重启后 **15.7s** 达 `sys.boot_completed=1`；`ro.build.version.release=14` / `ro.product.device=rk3576_lz200` / `wm size = 800x1280` / `/dev/dri = card0 card1 renderD128 renderD129`
  - 远程桌面: 板上 `persist.adb.tcp.port=5555`（重启后自动监听，实测 `tcp6 [::]:5555 LISTEN adbd`）；本机 `adb connect 10.0.102.185:5555`；ws-scrcpy 监听 `*:8000`，页面内 canvas **800x1280 ×2**，`readPixels sum=87604`（非全黑）
- **修改位置**:
  - `rk3576_android14/src/kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-neardi-lz200.dtsi`（`&pinctrl` 里把 group 包进 `i2c1 { }`，并写明为什么）
  - SDK 侧同文件（由 `scripts/install_board.sh` 推，`--check` 0 不一致）
  - 新增 `rk3576_android14/scripts/run_ws_scrcpy.sh`、`rk3576_android14/scripts/inject_over_serial.py`
  - 板上 flash 改动（非源码）: boot 分区 second 段（resource.img）+ header `dtb_size` + `id` 哈希；`misc` 分区清 0
- **做了什么**: ① 查 `regulator_summary` 无任何 rk806 DCDC/LDO + `/sys/bus/i2c/devices` 缺 `i2c-1` + dmesg 的 `unable to find group` 三证合一锁根因 ② 对照 `drivers/pinctrl/pinctrl-rockchip.c` 的 `rockchip_dt_node_to_map` 确认「group 必须挂 function 节点下」③ 改 DTS 并把 group 包进 `i2c1 { }` ④ `install_board.sh` 推 SDK（14 kernel + 13 device 全一致）⑤ `./build.sh -K -J6` 重编内核（`KERNEL_BUILD_EXIT=0`）⑥ 发现内核不吃文件尾 DTB，改走 `resource.img` ⑦ 串口注入 387,072 字节 resource.img → `dd seek=75440 conv=notrunc` → 回读 md5 一致 ⑧ U-Boot 补 AVB `id` 哈希（按字节序拆小端字）⑨ 清 misc 重启 → `boot_completed=1`、桌面渲染 ⑩ `persist.adb.tcp.port=5555` + 重启复验 ⑪ ws-scrcpy 装/编/起 + 无头 Chrome 端到端验证「看得到 + 点得动」
- **证据 (证明修好)**:
  - 内核重编: `build/logs/20261118-0108-rebuild-kernel-i2c1fix.log` 第 5421 行 **`KERNEL_BUILD_EXIT=0`**
  - 启动日志: `logs/20261118-0141-rk3576-android-resource-fix-boot.log`（修后首启）→ `grep` **无** `unable to find group` / **无** `RescueParty`，跑 265s+ 不重启
  - 重启持久化: `logs/20261118-0152-rk3576-android-reboot-persist.log`（`sys.boot_completed=1` @15.68s，AVB 无报错）
  - 桌面截图: `captures/20261118-0149-rk3576-lz200-android-desktop.png` md5 `f63aad1b628588192817eb914a374b5f`（Launcher3 + 状态栏 + 导航栏，800x1280）
  - 浏览器画面: `captures/20261118-0152-rk3576-lz200-browser-ws-scrcpy-desktop.png` md5 `b983cd1f176ac8ef1db95155931c8ebb`
  - 浏览器操控: `captures/20261118-0155-rk3576-lz200-browser-click-proof.png` md5 `a1a3419f6a4509a985926ec7f80eae18` —— 点击后板上焦点从 `com.android.launcher3/QuickstepLauncher` 变为 `com.android.permissioncontroller/GrantPermissionsActivity`
  - 复核命令: `adb -s 10.0.102.185:5555 shell "getprop sys.boot_completed; getprop persist.adb.tcp.port; ls /dev/dri; wm size"` → `1 / 5555 / card0 card1 renderD128 renderD129 / 800x1280`
- **结论 / 状态**: ✅ **已修复并达成目标**（2026-11-18 主人要求"安卓真正启动 + 浏览器远程显示操控"，两项都已实测通过；截图/日志见上）
- **回滚方案**:
  - DTS: `cd rk3576_android14 && git checkout -- src/kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-neardi-lz200.dtsi && bash scripts/install_board.sh`（然后重编内核）
  - 板上 boot 分区: cache 分区里留有旧件 `/mnt/c/boot-second-area.bin`（旧 resource 段 387,072）、`boot-head.bin`、`boot-lba76192-600.bin`；recovery 里 `dd if=<备份> of=/dev/block/by-name/boot bs=512 seek=75440 conv=notrunc` 即可回退（回退后需再补一次 AVB `id` 哈希）
  - 远程桌面: `pkill -f 'node ./index.js'` 停 ws-scrcpy；`su 0 setprop persist.adb.tcp.port ""` 关 adb tcp
- **涉及文件**: `rk3576_android14/src/kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-neardi-lz200.dtsi`、`rk3576_android14/scripts/{run_ws_scrcpy.sh,inject_over_serial.py,serial_boot_uboot.py,serial_uboot_run.py,serial_tail_ts.py}`、`rk3576_android14/docs/{PROGRESS.md,WORKLOG.md,CAPTURES.md,project.json}`、`rk3576_android14/{captures,logs,build/logs}/20261118-*`；SDK 侧 `kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-neardi-lz200.dtsi`（同内容）

### 2026-11-17 — 板级适配落地 `src/` + 文件级 `src ↔ SDK` 同步脚本（不碰同步中的 SDK 树）

- **问题现象**: 路线 B 的板级改动（内核 DTS + 板级目录）必须在 SDK 树里才能编译，但全量 `repo sync` 正在跑；此时改 SDK 已跟踪文件（如内核 dts `Makefile`）会被 `git checkout` 覆盖或直接冲突中断，需要一个"先写仓内、等 sync 完一键推"的机制
- **根因 (为什么)**: SDK 树在仓库根之外（100G 级 Android 树，不适合入仓 ⇒ 见 §21/§23），而 `repo sync` 会对每个项目 `git checkout` 到 pinned SHA：**未跟踪新文件不冲突**，但**已跟踪文件的本地修改会冲突**；因此板级改动必须以主仓 `src/` 为唯一可信副本（可提交、可换机器），SDK 只作编译场
- **关键参数**:
  - 板级 fragment 来源: 220 `~/rk3576/rk3576_linux/kernel/arch/arm64/boot/dts/rockchip/RK3576/neardi/` → **13 个 `.dtsi` / 88K**，md5 与本机逐一一致
  - 唯一 include 改动: `rk3576-neardi-lz200.dtsi` 里 `#include "../rk3576-rk806.dtsi"` → `#include "rk3576-rk806.dtsi"`（flat 布局）
  - 新建顶层 dts: `rk3576-lz200-android.dts` = `rk3576.dtsi` + `rk3576-neardi-lz200.dtsi` + **`rk3576-android.dtsi`**（Ubuntu 那份用的是 `rk3576-linux.dtsi`）+ 10 个外设 fragment，model `Rockchip RK3576 NEARDI LZ200 Board (Android 14)`
  - 板级目录: `device/rockchip/rk3576/rk3576_lz200/`（13 文件，由 `rk3576_u` 复制）→ `PRODUCT_KERNEL_DTS := rk3576-lz200-android` / `BOARD_SUPER_PARTITION_SIZE := 6442450944`（**6 GiB**，默认只有 ~3.04G）/ 删 `pcie_wifi.config` / `BOARD_GSENSOR_MXC6655XA_SUPPORT := false` / `PRODUCT_NAME|DEVICE := rk3576_lz200` / `PRODUCT_MODEL := LKB3576`
  - 同步脚本: `scripts/install_board.sh`（默认推 / `--check` 只比 md5 / `--pull` 回收）
  - 分区表: `parameter.txt` 由 `RebuildParameter.mk` + `parameter.in` + 板级 `*_PARTITION_SIZE` **构建期生成**，不用手写
- **修改位置**: 新增 `rk3576_android14/src/kernel-6.1/arch/arm64/boot/dts/rockchip/{rk3576-neardi*.dtsi ×13, rk3576-lz200-android.dts}`、`src/device/rockchip/rk3576/rk3576_lz200/`(13 文件)、`src/README.md`、`scripts/install_board.sh`；改 `sdk/README.md`(重写为仓外挂载事实)、`scripts/check_src_sdk_sync.sh`(仓外 SDK 转调 install_board)、`scripts/README.md`、`docs/ADAPT_ROCKCHIP_ANDROID.md`(§6.1/§6.3/§6.5 按实际落地重写)
- **做了什么**: ① 220 rsync 13 个 fragment 到仓内 `src/`（不直接进 SDK）② 改 1 处 include 为 flat 写法 ③ 写 Android 顶层 dts ④ 复制 `rk3576_u` 成 `rk3576_lz200` 并改 4 处 ⑤ 写 `install_board.sh`（含幂等补内核 `Makefile` dtb 行，`--check`/`--pull`）⑥ `check_src_sdk_sync.sh` 在 `sdk/` 无实体目录时自动转调 `install_board.sh --check` ⑦ 文档按实际落地更新
- **证据 (证明修好)**: 13 个 dtsi `md5sum` 与 220 远端输出**逐行一致**（如 `rk3576-neardi-lz200.dtsi` = `bc55069b6c528cc65aec97aa76d753c0`）；`bash -n scripts/install_board.sh` + `check_src_sdk_sync.sh` 语法 OK；`install_board.sh --check` 在 SDK 内核未 sync 时输出 14 个 kernel MISS + 13 个 device MISS 并 `exit 1`（错误路径正确）；`grep` 确认板级 mk 已改成 `rk3576_lz200`
- **结论 / 状态**: 🔄 **进行中** —— 板级改动已备好且**未污染正在同步的 SDK 树**；等全量 `repo sync` `EXIT=0` 后一键推 SDK 再编译
- **回滚方案**: `rm -rf rk3576_android14/src/kernel-6.1 rk3576_android14/src/device && git checkout -- rk3576_android14/scripts rk3576_android14/docs`（src 尚未进 SDK，删掉即回到"无板级"状态）；SDK 侧无改动，无需回滚
- **涉及文件**: `rk3576_android14/src/**`(新增)、`rk3576_android14/scripts/install_board.sh`(新)、`rk3576_android14/src/README.md`(新)、`rk3576_android14/sdk/README.md`、`rk3576_android14/scripts/{check_src_sdk_sync.sh,README.md}`、`rk3576_android14/docs/{ADAPT_ROCKCHIP_ANDROID.md,PROGRESS.md,WORKLOG.md,project.json}`

### 2026-11-17 — 路线B 定案并开工：瑞芯微官方 Android 14 BSP + 自建 lz200 板级（源码已落地，全量同步中）

- **问题现象**: 路线 A（NEARDI 官方 Android 14 整包）只有一个邮件渠道，拿不到包就完全停摆；主人要求改走「瑞芯微官方安卓源码 + 现有 Ubuntu 源码自己适配板级」，需要先证明源码能拿到、板级差异到底在哪、要改几个文件
- **根因 (为什么)**: ① NEARDI 官方 Android 包不公开（wiki 明确受限资料只走邮件，`github.com/neardi` 只有 Linux buildroot）② 但 Rockchip Android 14 BSP 有**公共 GitLab 镜像组**（Radxa 维护 manifest），可匿名拉取 ③ 板级差异并不大：SoC/外设 fragment 都在 Ubuntu SDK 里，Android 侧只需把 DTS 搬进 **flat 布局**、建一个板级目录、分区照 EVB 模板
- **关键参数**:
  - 源码: `gitlab.com/rockchip_android14_rk3576`（public）；manifest = `radxa/manifests` 分支 `Android14_RK3576_Radxa_rk6` → `rockchip-u-release.xml`；**merged manifest 1234 个项目**
  - 关键 pinned SHA: `kernel-6.1`=`343ed2c8…` / `u-boot`=`bf2c7da5…` / `device/rockchip/common`=`9e6765fd…` / `device/rockchip/rk3576`=`e6f577e7…`
  - 本机 repo 工具: googlesource **不可达**（curl 000/20s）⇒ vendored **repo v2.54**（GitHub codeload，`tmp/repo-src`），`repo init --no-repo-verify --depth=1`
  - repo 2.54 的 `repo sync` **不接受 `--depth`**（实测 `no such option`）⇒ 深度写在 `init`
  - 局部 sync 实测: 3 个项目 **EXIT=0 / 63 秒 / 221M**
  - 内核 DTS 布局: BSP 是 **flat** (`arch/arm64/boot/dts/rockchip/rk3576-*.dts`)，Ubuntu 是 `RK3576/neardi/` 子目录；fragment 共 **12 个 / 88K**，唯一需改的 include 是 `../rk3576-rk806.dtsi` → `rk3576-rk806.dtsi`
  - 内核 config: BSP = `rockchip_defconfig` + `rk3576.config`；`CONFIG_ASHMEM/BINDER_IPC/BINDERFS=y` 已在 `rockchip_defconfig`（917/988/989 行），`android-14.config` 在此 BSP **不存在**
  - u-boot: 板级变量 `PRODUCT_UBOOT_CONFIG ?= rk3576_defconfig`；Ubuntu SDK 仅有通用 `rk3576-evb.dts/rk3576-tb.dts` ⇒ **不动**
  - 无线: SeekWave **SV6160**，Ubuntu SDK 无驱动源码、BSP 配置无 sv6160、板上 dmesg 只有 `WLAN_RFKILL` 初始化 ⇒ 首版走有线；**有线侧实证正常**: 板上 dmesg 显示 `rk_gmac-dwmac` **eth0 (2a220000) + eth1 (2a230000) 均 probe 成功** (取证 `logs/20261117-1131-rk3576-lkb3576-wifi-eth-check.log`)
  - 磁盘: 268G 可用；估算 源码 90~120G + `.repo` 25~40G + `out` 80~120G = **195~280G**（临界）
- **修改位置**: `rk3576_android14/docs/ADAPT_ROCKCHIP_ANDROID.md`（**NEW**, 10 节完整方案）；`docs/{project.json,PROGRESS.md,WORKLOG.md,SESSION_HANDOFF.md}`；`docs/BUILD_ANDROID.md`（加路线A/B 说明）；本机安装 `repo`(apt, 未用) + vendored repo v2.54
- **做了什么**: ① 实测 gitlab 匿名克隆 + manifest 下载/合并计数 ② 解决 repo 工具 googlesource 不可达（vendored + `--no-repo-verify`）③ `repo init --depth=1` 完成，局部 sync 3 个项目验证 linkfile/板级模板 ④ 写完整自适配方案（DTS flat 迁移 / config 策略 / 板级目录 4 个改动点 / u-boot 不动 / 分区与烧录验收）⑤ 启动全量 sync（日志 `build/logs/20261117-1123-repo-sync-full.log`）⑥ 串口复查板内模块与 WiFi 现状
- **证据 (证明修好)**: `git ls-remote` 内核/AOSP 抽样均返回分支；`repo manifest -o` 后 `grep -c '<project'` = **1234**；局部 sync 日志 `build/logs/20261117-1123-repo-sync-partial-ok.log`（EXIT=0 / 63s / 221M）；树内已存在 `build.sh`、`device/rockchip/rk3576/rk3576_u/BoardConfig.mk`、`u-boot/configs/rk3576_defconfig`；失败留证 `build/logs/20261117-1121-repo-sync-partial-fail.log`（`--depth` 位置错）；串口取证 `logs/20261117-1131-rk3576-lkb3576-wifi-eth-check.log`（`lsmod` 空 / `/lib/modules` 仅 build / 无 sv6160 / dmesg 仅 WLAN_RFKILL + eth0/eth1 probe OK）
- **结论 / 状态**: 🔄 **进行中** —— 源码链路打通（局部 OK），**全量 1234 项目同步中**；板级 3 处改动未开始；磁盘与无线驱动是已知风险
- **回滚方案**: 删 `~/linux/rk3576_android/work/radxa-rk3576-android14` 即回收空间；文档回滚 `git checkout -- rk3576_android14/`；apt 装的 repo 可 `sudo apt-get remove repo`
- **涉及文件**: `rk3576_android14/docs/ADAPT_ROCKCHIP_ANDROID.md`(NEW)、`rk3576_android14/docs/{project.json,PROGRESS.md,WORKLOG.md,SESSION_HANDOFF.md,BUILD_ANDROID.md}`、`rk3576_android14/build/logs/20261117-11{21,23}-repo-sync-*.log`

### 2026-11-17 — 板子型号更正为 NEARDI LKB3576，并确认官方 Android target = lz200（无需移植板级）

- **问题现象**: 项目前一轮按 "LZ200" 写文档，还留了一条待办"官方 target 是 `rk3576_neardi_lb200-userdebug`，本板 lz200 需移植 DTS/defconfig"；主人指出板子实际型号是 **NEARDI LKB3576**（`neardi.com/cms/index/productsd.html?id=90`），需要按真实型号重新核对板级
- **根因 (为什么)**: 前一轮只查到 **LPR3576 / Neardi-PI3** 的 Android 编译页（那里 lunch 是 `rk3576_neardi_lb200-userdebug`），把 **lb200** 误当成"官方 target"，再拿板上 `device-tree model = Rockchip RK3576 NEARDI LZ200 Board` 去对，才得出"型号不符、需移植"的错误结论。实际 LKB3576 是独立产品分册，官方给的 target 就是 **lz200**
- **关键参数**:
  - 官方 LKB3576 Android 编译页 lunch：**`rk3576_neardi_lz200-userdebug`**
  - 官方全自动编译：**`./build.sh -AKUpu`**（本机加 `-J6`），产物 `rockdev/Image-rk3576_neardi_lz200/update.img`
  - Ubuntu SDK defconfig：`rockchip_rk3576_neardi_lz200_defconfig`（主人给的 `cs_lz200_linux_defconfig` 是同一板级变体）
  - SDK 包：`neardi-3576-android-14.tar.gz`，校验文件 `neardi-3576-android-14-tar.gz.md5sum`，渠道 `support@neardi.com`
  - 硬件：DC12V / **2×千兆网口 + WiFi6** / HDMI2.0 + MIPI-DSI / 3×USB3.0 + Type-C / M.2 2242 / mini-PCIe
  - 烧录：`sudo upgrade_tool uf update.img`；Loader 模式 = 串口 `reboot loader` 或断电按住 Update 键插 Type-C
  - 本机：Ubuntu 22.04.5 / 8 vCPU / 19G 内存 / 25G swap / 268G 可用（官方要求 22.04 + 16G + 250G）
- **修改位置**: `rk3576_android14/docs/{BUILD_ANDROID.md,BOARD.md,SESSION_HANDOFF.md,project.json,PROGRESS.md,WORKLOG.md}`、`rk3576_android14/README.md`；本机补装编译依赖
- **做了什么**: ① 抓官方 LKB3576 四个页面（编译/规格/烧录/必读）核对全部事实 ② `BUILD_ANDROID.md` 按 LKB3576 全量重写（含 14 行官方 Android 分区表、烧录/擦除命令、三种远程桌面方案） ③ `BOARD.md` 补 LKB3576 硬件规格与"为何 model 报 LZ200"的说明 ④ 删掉"需移植 lb200→lz200"的错误待办，改为直接 lunch ⑤ 补装 `gcc-multilib g++-multilib lib32ncurses-dev lib32z1-dev dwarves`
- **证据 (证明修好)**: 官方页原文 `select rk3576_neardi_lz200-userdebug` / `rockdev\Image-rk3576_neardi_lz200`（已存档进 `docs/BUILD_ANDROID.md` §5/§6）；`dpkg-query` 复核 5 个依赖 = installed；`python3 bin/check` 0 错 + `bash verify.sh --changed` FAIL 0（见 WORKLOG 12:10 条）
- **结论 / 状态**: ✅ 板级结论已纠正（LKB3576 = lz200，无需移植）；仍 **⛔ 阻塞在 SDK 包**（只能邮件申请）
- **回滚方案**: 本项目文档为纯文本，`git checkout -- rk3576_android14/` 即回退；依赖包回退 `sudo apt-get remove gcc-multilib g++-multilib lib32ncurses-dev lib32z1-dev dwarves`
- **涉及文件**: `rk3576_android14/README.md`、`rk3576_android14/docs/{BUILD_ANDROID.md,BOARD.md,SESSION_HANDOFF.md,project.json,PROGRESS.md,WORKLOG.md}`

### 2026-11-17 — 立项: RK3576 LZ200 Android 14 构建项目 + 本机环境/板子串口就绪
- **问题现象**: 主人要在本机构建 RK3576 最新 Android 固件；本机原来 7.7G 内存 / 根盘剩 35G，且没有屏幕，要求浏览器远程操控安卓桌面
- **根因 (为什么)**: Android 14 全编需 ≥16GB 内存 + 250~400GB 本地盘（官方推荐 32G/400G）；虚拟机原配置差 9~11 倍磁盘、2~4 倍内存；无 HDMI 时必须另行搭远程桌面通道
- **关键参数**: 本机 VM 现 19 GiB 内存 (available 17G) + swap 25 GiB (`/data/swapfile` 24G + 原 2G) + `/dev/sdb` 300G ext4 挂 `/data`（可用 268G，写速 255 MB/s，`noatime`）；板子串口 **`/dev/ttyUSB1` @ 1500000**、root/root、板内现 Ubuntu（hostname `openiot`）；板级 `cs_lz200_linux_defconfig` + DTS `RK3576/neardi/`
- **修改位置**: `rk3576_android14/{README.md,docs/{project.json,BOARD.md,SESSION_HANDOFF.md,PROGRESS.md,WORKLOG.md}}`；`machines/dengbaowen-ubuntu.json`(projects)
- **做了什么**: `bin/new` 建 9 项目录骨架并登记；按实测填写信息卡/板卡表/交接卡/project.json；系统侧新增 300G 盘格式化挂载 + 24G swap + `vm.swappiness=10`
- **证据 (证明修好)**: `findmnt /data` = `/dev/sdb ext4 rw,noatime`；`df -h /data` = 295G/可用 268G；`free -h` = Mem 19Gi + Swap 25Gi；pyserial 1500000 收到 `root@openiot:~#`；`python3 bin/check` 0 错（见 WORKLOG 10:40 条）
- **结论 / 状态**: 🔄 进行中（环境就绪；**阻塞: Android 14 源码包来源** —— 220/223/224 无 Android 树，需主人提供 Rockchip/NEARDI 整包）
- **回滚方案**: 删除 `rk3576_android14/` → `python3 bin/render` + `python3 bin/check`；系统侧 `swapoff /data/swapfile` + 注释 fstab → `umount /data`（详见顶层 WORKLOG 卸载步骤）
- **涉及文件**: `rk3576_android14/**`、`machines/dengbaowen-ubuntu.json`
