# rk3576_android14 — 取证 / 产出物台账 (captures/)

> **规矩**: 顶层 `AGENTS.md` **§14.6 产出物落盘铁律** + **§24.2.3 captures/** + **§18.2 自查第 12 项**。
> **本台账进 git**; `captures/` 里的原始数据**不进 git** (二进制大文件) —— 所以**换机器 clone 后本机没有数据**,
> 只能按「抓取命令」重抓, 再用 **md5** 核对是不是同一份。
> **登记判据**: `captures/` 下每个文件 (README.md 除外) 必须有一行; **没登记 = 线索缺失 = 违规**。
> **怎么补**: `python3 bin/captures write <项目>` 自动补缺失行 (md5 / 大小 / 时间 / 机器), 然后手工补
> 「抓取命令」「证明什么」「对应 PROGRESS」三列 —— 不许留 `TODO` 就算完。
> **检查**: `python3 bin/captures check` (verify.sh / pre-commit 会自动跑)。

## 取证文件

| 文件 (相对 captures/) | 大小 | md5 | 抓取时间 (UTC) | 抓取机器 | 抓取命令 | 证明什么 | 对应 PROGRESS |
|---|---|---|---|---|---|---|---|

<!-- 一行一个文件, 例:
| `20261016-0801-rv1106-usbaudio.wav` | 4.0M | `201dd480f5acd89b0760b6ee4aee365d` | 2026-10-16 00:55 | `bob-220` | `arecord -D hw:1,0 -f S16_LE -r 48000 -c 2 -d 22 /tmp/a.wav` | 证明 USB 音频切到 RV1106 后有真实声音 (mean -17.9dB) | 2026-10-16 |
--> 

## 登记规则 (照抄, 别自己发明)

1. **文件名**: `captures/<YYYYMMDD-HHMM>-<板子或机器>-<抓什么>.<扩展名>` (§24.2.3), 例 `20261016-0801-rv1106-usbaudio.wav`。
2. **抓取命令必须能照着重抓** (带接口名 / 过滤表达式 / 时长), 不许写"抓了个包"。
3. **证明什么** 写"这条数据支持哪条结论", 与 `docs/PROGRESS.md` 对应条目对得上。
4. **md5** 是换机器认数据的唯一凭据; 重抓后 md5 不同 = 不是同一份, 要在本行注明差异。
5. 只登记 `captures/` 里的原始数据; **文字日志 / 编译日志 / 脚本 / 文档不登记在这里** (各自进 `logs/` / `build/logs/` / `scripts/` / `docs/`, 见 §14.6.1)。
| `20261118-0149-rk3576-lz200-android-desktop.png` | 788.4K | `f63aad1b628588192817eb914a374b5f` | 2026-11-18 09:49 | dengbaowen-ubuntu | adb -s 10.0.102.185:5555 exec-out screencap -p > <文件>   (adb over tcp 5555) | 证明 Android 14 在无 HDMI 的 LKB3576 上确实渲染出桌面: Launcher3 + 状态栏 9:49 + 导航栏, 800x1280 —— 即 /dev/dri + SurfaceFlinger 链路已通 | 2026-11-18 |
| `20261118-0152-rk3576-lz200-browser-ws-scrcpy-desktop.png` | 417.1K | `b983cd1f176ac8ef1db95155931c8ebb` | 2026-11-18 09:52 | dengbaowen-ubuntu | 无头 Chrome (/usr/bin/google-chrome --headless=new + puppeteer-core) 打开 http://127.0.0.1:8000/#!action=stream&udid=10.0.102.185%3A5555&player=broadway&ws=... , 4~16s 后 page.screenshot() | 证明「浏览器看到安卓桌面」达成: 页面内 2 个 canvas 都是 800x1280, readPixels 非全黑, 右侧有电源/音量/返回/主页/多任务/旋转/键盘控制栏 | 2026-11-18 |
| `20261118-0155-rk3576-lz200-browser-click-proof.png` | 132.8K | `a1a3419f6a4509a985926ec7f80eae18` | 2026-11-18 09:52 | dengbaowen-ubuntu | 同上 headless Chrome 打开 stream 页 → page.mouse.click(canvas 内 Gallery 图标位置) → 6s 后截图; 同时 adb shell dumpsys window / grep mCurrentFocus 前后对比 | 证明「浏览器操控安卓」达成: 点击前焦点 = com.android.launcher3 (QuickstepLauncher), 点击后焦点 = com.android.permissioncontroller/GrantPermissionsActivity —— 浏览器输入注入真的到板子上了 | 2026-11-18 | `2026-11-18` |
| `20261119-0240-rk3576-android-desktop-after-flash.png` | 789.2K | `add7aaf82e09447aa14cdb3f2a5dff0b` | 2026-11-19 02:40 | dengbaowen-ubuntu | `adb -s 826226b8b84c7930 exec-out screencap -p > captures/<文件>` (USB adb, 烧录后 0 次 push) | 证明**新烧的整包能自己出桌面**: 800x1280, `dumpsys window` 焦点 = `com.android.launcher3/QuickstepLauncher`, SurfaceFlinger `running` —— 即 WiFi/蓝牙补丁进固件后图形链路没被破坏 | `2026-11-19` |
| `20261119-0616-rk3576-eapol-tx-shift2-air.pcap` | 2.3K | `89d689169706bec827b9c0df068c8b34` | 2026-11-19 06:16 | dengbaowen-ubuntu | `sudo iw phy phy0 interface add mon0 type monitor` + `sudo ip link set mon0 up` → `sudo tcpdump -i mon0 -w <文件> "wlan addr2 24:ef:b4:55:c2:3f or wlan addr1 24:ef:b4:55:c2:3f"` (板子 `su 0 cmd wifi connect-network LKB_AP_TEST wpa2 "Lkb3576Test123"` 期间抓); 回放 `sudo tcpdump -r <文件> -nn -e "wlan type data"` | 证明**修 TX 前的错位**: 板子发出的 2/4 EAPOL 帧在空口上是 `SA:24:ef:b4:55:c2:3f DA:c9:27:1e:46:24:ef ... ethertype Unknown (0x0103)` —— DA 被错位成 AP MAC 的后 4 字节 + 板子 MAC 前 2 字节, ethertype 从 0x888e 变成 0x0103 ⇒ CP 认为的帧起点比驱动实际放的早 2 字节, 4-way 2/4 永远到不了 AP | `2026-11-19` WSTA 条目 §根因① |
| `20261119-0623-rk3576-eapol-tx-pad2-gap2-air.pcap` | 2.3K | `327ae838ff3b89daf654d95ea073fe85` | 2026-11-19 06:23 | dengbaowen-ubuntu | 同上 (`mon0` + `sudo tcpdump -i mon0 -w <文件> "wlan addr2 24:ef:b4:55:c2:3f or wlan addr1 24:ef:b4:55:c2:3f"`) | 证明**"只把驱动实推字节改成 2"不够**: 此时驱动日志 `eapol tx: ret 0 peer 8 tid 0 len 135 pad 2 eth_off 8`, 但空口 A3 仍错 (`DA:c9:27:1e:46:24:ef / 0x0103`) ⇒ CP 的帧起点 = `8 + 声明的 padding_gap`, 与实推字节数无关 (声明 2 时它从 10 读) | `2026-11-19` WSTA 条目 §根因① |
| `20261119-0626-rk3576-eapol-2of4-fixed-air.pcap` | 2.1K | `b5efbc49fc6b32a56e03b45975ecb89d` | 2026-11-19 06:26 | dengbaowen-ubuntu | 同上 (`mon0` + `sudo tcpdump -i mon0 -w <文件> "wlan addr2 24:ef:b4:55:c2:3f or wlan addr1 24:ef:b4:55:c2:3f"`) | 证明**TX 修好(实推 2 字节 + 声明 gap 0)**: 板子发出的 2/4 帧 `SA:24:ef:b4:55:c2:3f DA:68:8f:c9:27:1e:46 ... ethertype EAPOL (0x888e), length 121: EAPOL key (3) v1, len 117` —— A3 与 ethertype 全对, 同一时间段 AP 回了 3/4 (hostapd 侧 `sending 3/4 msg`) | `2026-11-19` WSTA 条目 §根因① 证据 |
| `20261119-0635-rk3576-dhcp-offer-air.pcap` | 4.0K | `fef0c1125998b6a52f68f1c50905e75d` | 2026-11-19 06:35 | dengbaowen-ubuntu | `sudo tcpdump -i mon0 -nn -e -w <文件> "wlan addr1 24:ef:b4:55:c2:3f and wlan type data"` (板子反复 DHCPDISCOVER 期间抓) | 证明**DHCPOFFER 确实到了空口但被驱动丢掉**: 抓到 `68:8f:c9:27:1e:46 > 24:ef:b4:55:c2:3f ... Data IV: 1 Pad 20` 共 6 帧加密下行数据帧, 同期宿主 `dnsmasq` 日志有 `DHCPOFFER 192.168.50.42` 而板侧 `wlan0 RX packets` 只有 2 ⇒ 问题在 RX 解析, 不在上行/AP 侧 | `2026-11-19` WSTA 条目 §根因②④ |
| `20261119-0922-lkb3576-air-tx-agg-drop.pcap` | 998B | `70709f20dbe1704be3301f7685f5c221` | 2026-11-19 09:22 | dengbaowen-ubuntu | 主机 AP 侧: `sudo tcpdump -i wlx688fc9271e46 -n -s 0 -w <文件> "icmp or arp"`, 同时板子 `su 0 ping -I wlan0 -c 12 -i 0.3 192.168.50.1` (AP = 本机 hostapd, 11g 模式) | 证明**高频发送时 CP 直接吞帧**: 12 个 ICMP 请求只有 3 个上空口 (seq 1~3), 其余 9 个连畸形帧都没有; 同期板子 netdev `tx_packets` 正常增长、`tx_dropped=0` ⇒ 帧已交给驱动/CP, 丢在 CP 内部; 而随后 1pps 的 3 发外网 ping 全通 ⇒ 与"背靠背发送触发聚合"直接相关 | `2026-11-19` 进度条目「CP TX 聚合路径」 |
| `20261119-0922-lkb3576-air-tx-agg-malformed.pcap` | 936B | `cce56a7a6c2ad06c68ea672f9c12f06b` | 2026-11-19 09:22 | dengbaowen-ubuntu | 主机 AP 侧: `sudo tcpdump -i wlx688fc9271e46 -n -s 0 -w <文件> "ether src 24:ef:b4:55:c2:3f"`, 同时板子 `ping -I wlan0 -c 8 -i 0.3 192.168.50.1` | 证明**CP 的 TX 聚合走了 A-MSDU 分支且漏 LLC/SNAP**: 前 3 帧是正确 IPv4/ICMP (ethertype 0x0800); 从第 4 帧起 ethertype 被改写成 `0x0054` (= 84 = 98−14, 即 A-MSDU 子帧长度), AP 侧解析成 `802.3 length 84 + LLC` ⇒ 聚合帧非法, AP 丢弃/误解 | `2026-11-19` 进度条目「CP TX 聚合路径」 |
