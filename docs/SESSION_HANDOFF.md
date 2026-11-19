# rk3576_android14/docs/SESSION_HANDOFF.md — 交接卡 (上个 AI 停在哪)

> **用途**: 换 AI / 换电脑 / 隔几天回来 / 死机重启后, **先读这一页**(1 分钟) 就知道从哪继续。
> 与 `WORKLOG.md` 的分工: WORKLOG = **逐条流水**(发生过什么); 本文件 = **当前状态快照**(现在在哪、下一步做什么)。
> 保持 1 屏以内 —— 老的"下一步"做完了就删, 不要堆积。

---

## 1. 现在停在哪

| 项 | 内容 |
|---|---|
| **最后更新** | 2026-11-19 06:52 (UTC) |
| **本轮任务** | 打通 WiFi **STA 关联**(连 AP) → 修 CP 的 TX 帧起点 + RX 描述符布局 → 整包重编 → 烧录复验 |
| **当前状态** | ✅ **WiFi STA 全链路打通 (2026-11-19 06:47 UTC)**: `wlan0 192.168.50.42/24` + `ping 223.5.5.5` 2/2(24ms) + DNS 解析 `www.baidu.com` 并通 + 扫描有结果, **与 `eth0` 并存**(不再被 `onNetworkUnwanted` 拆网) + BT `state: ON`; 12/12 浸泡采样全绿(`BSPASSERT=0`)。clean ko md5 **`04db703d96b2a13702609598bf272f06`** 已回灌 `src/`, `install_board.sh --check` **11 文件 0 不一致**。🔄 **正在整包重编** (`./build.sh -A -u -J6`, 日志 `build/logs/20261119-0648-build-android-sta-eapol-rx-fix.log`) —— 出包后要烧录固化, 板上目前跑的仍是 **adb push** 的 ko |
| **机器** | 本机 `dengbaowen-ubuntu` (VM: Ubuntu 22.04.5 / 19G 内存 / 25G swap / 8 vCPU / 268G 盘) |
| **板子** | **NEARDI LKB3576**（RK3576），串口 `/dev/ttyUSB1` @1500000，root/root |

### 已就绪 (2026-11-17 实测/查证)

| 项 | 状态 |
|---|---|
| 编译盘 | `/dev/sdb` 300G → **`~/linux/rk3576_android`**（fstab UUID 单行，可用 **268G**） |
| 内存/swap | 19 GiB（available 16G）/ **25 GiB swap** |
| 编译依赖 | ✅ `gcc-multilib` `g++-multilib` `lib32ncurses-dev` `lib32z1-dev` `dwarves` |
| repo 工具 | ✅ vendored **repo v2.54** → `~/linux/rk3576_android/tmp/repo-src`（googlesource 不可达；`/usr/bin/repo` 弃用） |
| manifest | ✅ radxa/manifests 快照 → `~/linux/rk3576_android/work/manifests`（main, commit `1677660`） |
| repo init | ✅ `~/linux/rk3576_android/work/radxa-rk3576-android14`（`--depth=1`, merged manifest 1234 项目） |
| 局部 sync | ✅ device/rockchip/rk3576 + common + u-boot：EXIT=0 / 63s / 221M |
| 板级结论 | **LKB3576 = neardi lz200 板级**；路线A lunch 是 `rk3576_neardi_lz200-userdebug`；路线B 自建 `rk3576_lz200` |
| 主文档 | **`docs/ADAPT_ROCKCHIP_ANDROID.md`**（路线B 全案：源码/坑/DTS/config/板级目录/风险） |

## 2. 下一步 (照做即可)

**已完成的烧录流程 (下次照抄即可)**:
```bash
# 1) 板子在 Android: 让它进 loader
adb -s <USB序列号> shell reboot loader
# 2) 在 VMware 里把**新的** loader 设备 (2207:350e) 再 connect 一次 (身份变了不会自动接)
# 3) 一条命令烧 (md5 门禁 + 等设备全在里面)
bash scripts/flash_update.sh --wait 60
```

**本轮修的三处 (2026-11-19, 别回退)**:
| 文件 | 改动 | 不改的后果 |
|---|---|---|
| `src/external/wifi_driver/ea6621q/drivers/skwifi/skw_rx.c` | 事件 seq 不符 → 按收到的 seq 重对齐 + 丢这一个包 (`resync (no assert)`) | 丢一个 SDIO 事件包 → `skw_hw_assert` → CP 断言 → WiFi+BT 全挂, 只能重启 |
| `src/.../drivers/skwifi/skw_msg.c` | 命令超时连续 3 次才断言, 前 2 次清 `BLOCK_TX` 继续 | 单次 2s 超时 = `BLOCK_TX` 永久置位 ⇒ 之后所有命令 `-EIO` |
| `src/packages/modules/Bluetooth/system/gd/stack_manager.cc` | 启停等待 3s/5s → **15s/15s** | CP 重下固件 ~2.0s + 开销 > 3s ⇒ BT 栈崩 ⇒ HAL close() 停整颗 CP ⇒ 死循环 |

**稳定性回归自测 (烧完就照跑)**:
```bash
S=826226b8b84c7930
adb -s $S shell 'for i in $(seq 1 10); do cmd wifi start-scan; sleep 6; done'      # 10 轮扫描
adb -s $S shell 'cmd bluetooth_manager disable; sleep 5; cmd bluetooth_manager enable'  # BT 关开 ×3
adb -s $S shell 'echo -n BSPASSERT=; dmesg|grep -c BSPASSERT; echo -n resync=; dmesg|grep -c "resync (no assert)"; echo -n mask0=; dmesg|grep -c "mask: 0x0"'
# 期望: BSPASSERT=0 / mask0=0; resync 可以 >0 (说明补丁在真实丢包时生效了) —— 但 WiFi 必须仍能扫描、BT 仍能开
```

**关联(连 AP)复验 —— 不再需要主人给热点密码**: 用仓内 `scripts/lkb_test_ap.sh` 在本机 USB 网卡自建热点
```bash
sudo bash scripts/lkb_test_ap.sh start     # SSID LKB_AP_TEST / 密码 Lkb3576Test123 / ch6 / 192.168.50.1
S=826226b8b84c7930
adb -s $S shell 'su 0 cmd wifi connect-network LKB_AP_TEST wpa2 "Lkb3576Test123"'
sleep 20
adb -s $S shell 'ip -br addr | grep wlan0; ping -c2 -W2 223.5.5.5'
sudo bash scripts/lkb_test_ap.sh stop      # 验完收掉
```
> 抓空口: `sudo iw phy phy0 interface add mon0 type monitor` + `sudo ip link set mon0 up` + `sudo tcpdump -i mon0 -nn -e -w /tmp/opencode/x.pcap "wlan addr1 24:ef:b4:55:c2:3f or wlan addr2 24:ef:b4:55:c2:3f"`;
> **注意** `pkill -f <pattern>` 会杀掉自己的命令行 —— 用 `pkill -x tcpdump`。

**本轮修的四处 (2026-11-19 STA, 别回退)**:
| 文件 | 改动 | 不改的后果 |
|---|---|---|
| `src/.../skwifi/skw_core.c` | 特殊直发路径**实推 2 字节但声明 `padding_gap=0`**(新变量 `desc_gap`) | CP 从 `8+声明gap` 读帧 ⇒ A3 与 EAPOL 载荷错位 2 字节 ⇒ 2/4 永远到不了 AP |
| `src/.../skwifi/skw_rx.c` | `SKW_LKB_RX_FRAME_OFF 18` / `LEN_ADJ 6` + `skw_rx_eth_sane()` + `skw_rx_deliver_eth()`, 分支**在 peer/tid 判断之前** | 数据帧(tid=11/15、peer 随机)被 reorder/replay/iface 判死 ⇒ DHCP 拿不到 IP |
| `src/.../skwifi/skw_rx.c` | `skw_eapol_iface()`: `inst_id` 越界(实测 3)时回退到已注册 STA/AP iface | `to_skw_iface(3)=NULL` ⇒ 3/4 `-EINVAL` ⇒ 握手停在 2/4 |
| `src/.../skwifi/skw_msg.c` | `skw_rx_eapol_deliver()` 兼容 802.3 / 802.11 两形态 | PTK 未装时 CP 交的是 802.3, 只认 802.11 会丢 |

**注意 (擦盘后的默认态)**: GPT 重建会擦 `/data` ⇒ 开机 `Wifi is disabled` + `bluetooth_on=0`, 先 `svc wifi enable` / `cmd bluetooth_manager enable` 一次, 这与驱动无关。

**改代码时的铁律**: `bash scripts/install_board.sh --check` 全绿 → 改 `src/` → 推 SDK → 编译 → `bash scripts/check_firmware_content.sh` 全 OK → 出 `update.img` → 烧 → 零 push 复验 (§23.13)。

## 3. 关键约束 / 别踩的坑

- **repo 命令必须用 vendored 的**：`export PATH=$HOME/linux/rk3576_android/tmp/repo-src:$PATH`；`/usr/bin/repo` 会去连不通的 googlesource
- **`--depth` 写在 `repo init`**（repo 2.54 的 `sync` 不接受 `--depth`）；`init` 要加 `--no-repo-verify`（vendored 无签名）
- **磁盘临界**：268G vs 估算 195~280G；编译前看 `df`，不够扩 vmdk 到 400~500G（宿主机关机操作）
- **无线已通 (2026-11-18)**: 板载是 **SeekWave SWT6652x / SV6316** (SDIO `1FFE:6316`, 不是 SV6160); 7 处驱动/HAL 补丁在 `src/` 里, 明细见 `src/README.md` §1.1; **改完必须 `install_board.sh --check` + `check_firmware_content.sh` 全绿再出固件**, 否则固件里是旧版 (`adb push` 验过不算交付, §23.13)
- **板级布局差异**：BSP 内核 DTS 是 flat 目录（无 `RK3576/neardi/`），fragment 要拷进去 + 改 1 处 include
- **u-boot 不动**：`PRODUCT_UBOOT_CONFIG ?= rk3576_defconfig`，通用 dts 够用
- **烧 Android 会重写 GPT**：板上 Ubuntu 被覆盖；回滚 = 重烧 220 上编的 Ubuntu `update.img`
- **普通用户编译**（不要 root）；`-J` 不超过 6（19G 内存）
- 串口设备名随插拔变：`/dev/ttyUSB1` @1500000（`ttyUSB0` 无输出）
- 无 HDMI：远程桌面走 adb + scrcpy；黑屏查 `wm size` / `dumpsys SurfaceFlinger`

## 4. 未完成 / 已知问题

| # | 问题 | 影响 | 备注 |
|---|---|---|---|
| 1 | 全量 sync 未完成 | 后续都等它 | 1234 项目；断流直接重跑（可续传） |
| 2 | 磁盘 268G 临界 | 可能编到一半满盘 | 编译前 `df`；不够扩 vmdk |
| 3 | 无线无驱动 | 首版无 WiFi | 有线 + USB adb 交付；向 NEARDI 索取驱动 |
| 4 | 板级改动**还没进 SDK** | 现在 lunch 里还没有 `rk3576_lz200` | sync 完跑 `scripts/install_board.sh` 即可; 改动全部在 `src/` |
| 5 | 板子当前仅 `usb0` 192.168.2.1/24 | 方案 B（板 IP 直连）暂不可用 | 插网线或先走 USB adb |

## 5. 证据与入口 (下个 AI 第一站)

- 进度权威: `docs/PROGRESS.md` 顶部
- 现场流水: `docs/WORKLOG.md` 顶部 20 条
- **路线B 主文档: `docs/ADAPT_ROCKCHIP_ANDROID.md`**
- 板级改动索引: `src/README.md`; SDK 挂载事实: `sdk/README.md`; 同步脚本: `scripts/install_board.sh`
- 路线A 兜底: `docs/BUILD_ANDROID.md`
- 硬件/网络: `docs/BOARD.md`

---

## 维护规则

- **只写当前快照**, 不写历史 (历史在 `PROGRESS.md` / `WORKLOG.md`)
- 每次收尾: 更新「最后更新」+「现在停在哪」+「下一步」三段
- 状态用词固定: `✅ 已完成` / `🔄 进行中` / `⛔ 阻塞` (便于 grep)
