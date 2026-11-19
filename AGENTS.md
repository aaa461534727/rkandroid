# AGENTS.md — 接手本仓的 AI 必读（rkandroid）

> 本仓 = **RK3576 / LKB3576 的 Android 14 源码定义仓**。只放「源码的定义（manifest）+ 我们的板级叠加层（`src/`）+ 脚本/文档」，
> **不放源码本体，也不放固件镜像**。你克隆到的是一个 4 MB 的骨架，源码要自己 `repo sync` 出来（109 GB）。

---

## 0. 30 秒速览

```bash
git clone https://github.com/aaa461534727/rkandroid.git ~/rkandroid
WS=~/rk3576_android14_ws JOBS=8 bash ~/rkandroid/scripts/sync.sh     # init + sync(109G) + 铺 src
WS=$WS bash ~/rkandroid/scripts/verify_tree.sh                      # 必须 FAIL=0
cd $WS && source build/envsetup.sh && lunch rk3576_lz200-userdebug
./build.sh -A -u -J6                                               # 产物 rockdev/Image-rk3576_lz200/update.img
bash ~/rkandroid/scripts/check_firmware_content.sh                  # 出固件前门禁, 必须全 OK
bash ~/rkandroid/scripts/flash_update.sh --wait 60                  # USB 烧录
```

细节全在 **`docs/SYNC_AND_BUILD.md`**（唯一操作手册）。

---

## 1. 进场必读顺序（按这个顺序读，别乱翻）

| # | 文件 | 解决什么问题 |
|---|---|---|
| 1 | `README.md` | 这是什么、仓里有什么、当前状态（1 分钟） |
| 2 | `docs/SYNC_AND_BUILD.md` | 怎么同步 / 怎么编 / 怎么烧 / 10 个坑 / 验收 DoD |
| 3 | `docs/SESSION_HANDOFF.md` | 上一轮交接卡：断点、未结问题、下一步 |
| 4 | `docs/PROGRESS.md` **最上面 3~5 条** | 历史结论（含 WiFi 数据面根因，**很多坑别重踩**） |
| 5 | `docs/WORKLOG.md` **最上面 10~20 条** | 上个 AI 干到哪、卡在哪（防死机丢现场） |
| 6 | `docs/BOARD.md` / `docs/ADAPT_ROCKCHIP_ANDROID.md` | 板子硬件 / 板级移植全过程（DTS、DTB 打包、i2c 那些坑） |
| 7 | `src/README.md` | `src/` 里每个文件改了什么、为什么 |

---

## 2. 五条硬约束（违反 = 后面的人要重新踩坑）

1. **`src/` 是唯一可信副本**（板级改动只认它）。
   在源码树里调通的改动**必须** `install_board.sh --pull` 拉回 `src/` 并提交，否则换机器 / 下次 `repo sync` 就丢。
2. **不许手改 `default.xml`**。它是 `repo manifest -r` 生成的快照（1234 个 project 逐条锁 commit）。
   要增删 project：先在源码树里改好 → 重新 `repo manifest -r` → 替换 `default.xml` → 在 `docs/` 记一笔为什么。
3. **固件 / 镜像不入仓**：`*.bin`（厂商 WiFi 固件）`*.img`、`out/`、`rockdev/` 一律 `.gitignore`。
   固件版本靠 `src/firmware/swt6652x/md5.txt` 认。
4. **私有信息不写进本仓**：板子 IP、串口、服务器账号/密码、内网拓扑 —— 这些是"机器私有事实"，属于每台机器的登记信息，不在这里。
5. **记录规矩**（防死机丢现场）：
   - 动手**前**在 `docs/WORKLOG.md` 写一行（时间 / 动作 / 目标 / 命令 / 预期）；
   - 有结论（修好了 / 定论了）在 `docs/PROGRESS.md` 最上面加一条**标准条目**（现象 / 根因 / 参数 / 改动位置 / 做了什么 / 证据 / 结论 / 回滚 / 文件）；
   - 板子抓的原始数据（pcap/wav/png/dump）进 `captures/`（若本仓没有该目录，放主框架仓对应项目），**不许只留 `/tmp` 或板子里**。

---

## 3. 标准工作流（改 WiFi 驱动为例）

```bash
# 1) 改：直接改源码树 (调试最快)
cd $WS/external/wifi_driver/ea6621q/drivers/skwifi && vi skw_core.c

# 2) 编：只编驱动 ~50 秒
cd $WS/external/wifi_driver && ./build_wifi_ko.sh ea6621q

# 3) 板验证：adb push 到 /vendor/lib/modules + /vendor_dlkm/lib/modules 后重启 (不要 rmmod/insmod)
adb root && adb remount
adb push $WS/external/wifi_driver/ea6621q/drivers/skwifi/skw.ko /vendor/lib/modules/
adb reboot

# 4) 收：改通了拉回 src/
SDK=$WS bash ~/rkandroid/scripts/install_board.sh --pull
SDK=$WS bash ~/rkandroid/scripts/install_board.sh --check    # 必须 == OK

# 5) 提交本仓（交付 = 整包重编 + 烧录，不许只停在第 3 步的 adb push）
git -C ~/rkandroid add -A && git -C ~/rkandroid commit -m "fix(skwifi): ..." && git -C ~/rkandroid push
```

**交付线**：`adb push` 的 ko 只算调试；**最终必须 `./build.sh -A -u -J6` + `check_firmware_content.sh` + 烧录**。
原因：镜像里的固件/ko 走 `out/` → `vendor/`，与 `adb push` 是两条路，历史上被 EA6621Q 版同名固件覆盖过一次。

---

## 4. 板子 / 服务器地址从哪来

本仓**故意不含**具体 IP / 串口 / 账号 —— 那是"机器私有事实"，每台机器各自登记。
在本机（主框架仓）用 `python3 bin/machine whoami` / `bin/machine local rk3576_android14` 取；
**不要照抄别人文档里出现过的 IP**（不同工作站网段不同，照抄 = 串味）。

已确认的通用事实（与机器无关，可以写死）：

| 项 | 值 |
|---|---|
| SoC | RK3576（8 核 A72/A53，Mali-G52 MC3） |
| 板 | NEARDI **LKB3576** |
| 无线 | 板载 NEARDI FD7352S = **SWT6652x**（SV6316/EA6316），SDIO `1FFE:6316`，WiFi 与 BT 共用一颗 CP |
| 串口 | 控制台 `1500000` 8N1（不是 115200） |
| 分区/打包 | `parameter.txt` + `rockdev/Image-rk3576_lz200/` |
| lunch | `rk3576_lz200-userdebug` |

---

## 5. 当前未结问题（2026-11-19）

| 问题 | 状态 |
|---|---|
| WiFi 数据面：IP 帧空口畸形（对端看到 `802.3 + LLC dsap 0x44`） | **根因在厂商 CP 固件**：TX 无条件包成单子帧 A-MSDU 且不带 LLC/SNAP。主机驱动侧（TX `padding=2/gap=0`、RX 偏移 18）已逐项验证正确。**只能等厂商更新 CP 固件或换模组** |
| `skw_tx.h` 的 `SKW_SNAP_HDR_LEN 8` 定义了没人用、`skw_set_tx_desc_eth_type()` 是空函数 | 旁证：厂商漏做 SNAP。驱动侧补 SNAP 的实验**未验证**（推板无断言，但连接/抓包步骤被叫停） |
| CP 不定期 `BSPASSERT ... mms_interface.c-376` | 断言后 `skw->flags = 0x8301`，只能重启板子；已加"同步命令连续 3 次超时才断言"的容错 |
| 真实 AP（手机热点，支持 ADDBA）复验 | 未做（缺热点密码）—— 这是唯一"可能不换硬件就好"的路径 |

---

## 6. 禁止清单

- ❌ 手改 `default.xml` / `manifests/` 里的原厂文件（`manifests/` 只是**对照用**的历史快照，`repo init` 不指向它）
- ❌ 把源码本体（`out/` `rockdev/` 任何 project 的整目录）或厂商固件 `.bin` 提交进来
- ❌ `git push --force` 覆盖别人的提交；改历史先说明
- ❌ 用 `rmmod/insmod` 换 WiFi 驱动（平台会挂）—— 用 push + 重启
- ❌ 只做 `adb push` 就宣布"改好了"（必须整包重编 + 烧录 + 冒烟）
- ❌ 在文档里写死某台机器的 IP / 密码 / 串口设备号
