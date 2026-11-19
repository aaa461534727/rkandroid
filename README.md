# rkandroid — RK3576 (NEARDI LKB3576) Android 14 源码定义仓

> **本仓不放源码本体**，放的是**「源码的定义」**：
> 一份把 1234 个 project 逐个锁死到 commit 的 manifest + 我们自己的**板级叠加层** `src/`（2.4 MB）。
> 任何人（任何 AI）拿到本仓 + 3 条命令，就能在本地把 **109 GB** 源码按原样拉回来，并编出**同一个固件**。

| 项 | 值 |
|---|---|
| 目标板 | NEARDI **LKB3576**（RK3576，8 核，板载 WiFi = NEARDI FD7352S / SWT6652x / EA6316） |
| Android | **14.0**（Rockchip BSP `android-14.0-mid-rkr6`，AOSP tag `android-14.0.0_r27`） |
| 内核 | BSP `kernel-6.1`（**6.1.99**），u-boot 2017.09 |
| lunch 目标 | `rk3576_lz200-userdebug` |
| 源码来源 | 公开镜像 `https://gitlab.com/rockchip_android14_rk3576`（`repo sync` 从这里拉） |
| 本仓体积 | ~4 MB（源码 0 字节） |
| 复现出的源码 | ~109 GB（含 `out/` 编译产物约 115 GB，需 **≥ 260 GB** 空闲盘） |

---

## 1. 为什么源码不直接进仓

| GitHub 限制 | 这套源码 | 结论 |
|---|---|---|
| 单文件 ≤ 100 MB | 排除 `out/`、`rockdev/` 后仍有 **186 个** >100 MB（`libassimp.so`、`swiftshader` 测试数据…） | push 直接被拒 |
| 仓库建议 ≤ 1 GB | 109 GB | 差 100 倍 |
| 传输 | 109 GB，家用上行要几天 | 中途必断 |
| 授权 | 含 libmali 等闭源 `.so`、Rockchip 私有 prebuilts | 公开仓违规 |

而 `.repo/`（36 GB）本身**已经就是全部裸仓**——把源码再塞进一个 git 仓等于**复制一遍 git**，纯浪费。

所以采用 Android BSP 的标准分发形态：**仓放定义（manifest），源码由 `repo sync` 按定义拉取**。

---

## 2. 仓里有什么

| 路径 | 作用 | 体积 |
|---|---|---|
| `default.xml` | **入口 manifest**（单文件，无 include，1234 个 project 全部锁 commit） | 283 KB |
| `manifests/` | 原厂多文件 manifest 快照（include 链，**仅供人读/对照**，`repo init` 不指向它） | 1.4 MB |
| `src/` | **板级叠加层**（我们改过的源码唯一可信副本）：内核 DTS、`device/rockchip/rk3576/rk3576_lz200/`、WiFi 驱动 6 处补丁、WiFi HAL、BT、框架侧 2 个文件、无线固件（只有 `.ini`/`md5.txt`，`.bin` 不入仓） | 2.4 MB |
| `scripts/sync.sh` | **一键**：`repo init` + `repo sync` + 应用 `src/` 叠加层 | — |
| `scripts/install_board.sh` | `src/` ⇄ 源码树 双向同步（`--check` / `--pull` / `--push`） | — |
| `scripts/verify_tree.sh` | 同步完自检：project 数、关键仓、lunch 目标、src 一致性 | — |
| `scripts/check_firmware_content.sh` | **出固件前的机器门禁**：核 `out/` 里固件/ko/HAL 的 md5 是否 == `src/` | — |
| `scripts/flash_update.sh` | 整包烧录（烧前核 md5 → `adb reboot loader` → `upgrade_tool uf`） | — |
| `scripts/lkb_test_ap.sh` | 本机 USB 网卡自建测试热点（给板子 WiFi STA 复验用） | — |
| `docs/SYNC_AND_BUILD.md` | **主文档**：装环境 → 同步 → 叠加板级 → 编译 → 校验 → 烧录 → 坑 | — |
| `docs/ADAPT_ROCKCHIP_ANDROID.md` | 板级移植全过程（为什么 kernel DTB 取自 `boot.img` 的 `second` 段等） | — |
| `docs/PROGRESS.md` / `docs/WORKLOG.md` | 历史结论（含 WiFi 数据面根因）与逐日流水 | — |
| `docs/SESSION_HANDOFF.md` / `docs/BOARD.md` | 交接卡 / 板子硬件与串口信息 | — |

固件二进制（`*.bin`）、镜像（`*.img`）、`out/`、`rockdev/` 全部被 `.gitignore` 排除（厂商授权文件不得公开，见 `src/firmware/swt6652x/md5.txt` 校验版本）。

---

## 3. 三步上手

### 0) 环境（Ubuntu 22.04，普通用户，**不要 root**）

```bash
sudo apt-get install -y git repo curl python3 rsync bc build-essential \
     zip unzip libssl-dev libncurses5 libncurses5-dev libxml2-utils \
     lz4 zlib1g-dev gcc-multilib g++-multilib
# repo 工具（本机若已有可跳过）
mkdir -p ~/bin && curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo && chmod a+x ~/bin/repo
export PATH=~/bin:$PATH

git config --global user.name  "你的名字"
git config --global user.email "你的邮箱"
# 磁盘: 源码 ~109G + 编译产物 ~115G ⇒ 至少留 260G (推荐 300G)
# 内存: 8G 能编 (-J4)，16G 舒服 (-J6)；本机实测 -J6 峰值约 8G
```

### 1) 取本仓（4 MB）

```bash
git clone https://github.com/aaa461534727/rkandroid.git ~/rkandroid
```

### 2) 同步源码 + 应用板级叠加层（一次性，数十分钟~数小时，看带宽）

```bash
WS=~/rk3576_android14_ws JOBS=8 bash ~/rkandroid/scripts/sync.sh
```

它做三件事：`repo init`（读本仓 `default.xml`）→ `repo sync`（1234 个 project，109 GB）→ `install_board.sh --push`（把 `src/` 铺进源码树）。

> **本机已有 109 G 源码？** 别重下，直接复用：
> `WS=$HOME/linux/rk3576_android/work/radxa-rk3576-android14 bash ~/rkandroid/scripts/sync.sh --no-sync`
> （只做 init + 叠加，不联网）

### 3) 编译 → 出 `update.img`

```bash
cd $WS
source build/envsetup.sh
lunch rk3576_lz200-userdebug
./build.sh -A -u -J6          # -A 编 Android, -u 打 update.img, -J6 并行度(内存 16G 用 6)
# 产物: $WS/rockdev/Image-rk3576_lz200/update.img  (约 2.1 GB)
```

**出固件前必跑门禁**（否则镜像里的固件/ko 可能是错版本）：

```bash
bash ~/rkandroid/scripts/check_firmware_content.sh
```

### 4) 烧录（只走 USB，不需要 HDMI/屏幕）

```bash
bash ~/rkandroid/scripts/flash_update.sh --wait 60
```

> `upgrade_tool` 需先装：`sudo mv upgrade_tool /usr/local/bin && sudo chmod a+x /usr/local/bin/upgrade_tool`。
> 没有屏幕也能用浏览器操控桌面（ws-scrcpy，见 `docs/SYNC_AND_BUILD.md` §8）。

完整步骤、增量编译、单模块编译、常见报错 → **`docs/SYNC_AND_BUILD.md`**。

---

## 4. 当前状态（2026-11-19）

| 项 | 状态 |
|---|---|
| 源码同步 / 首次编译 | ✅ 通过（`repo sync` 全量，`./build.sh -A -u -J6` 出 2.1 GB `update.img`） |
| Android 14 启动 | ✅ `sys.boot_completed=1`，浏览器远程桌面可用（不插 HDMI、不插鼠标） |
| 内核 / DTB | ✅ 自建 `rk3576-lz200-android.dtb`（已知坑：DTB 必须重打进 `resource.img` 的 `second` 段） |
| 无线 | ⚠️ 关联/4-way/DHCP/收发链路全通，**但 CP 固件 TX 聚合缺 LLC/SNAP ⇒ IP 帧在对端呈现畸形**（见 `docs/PROGRESS.md` 2026-11-19 条目；根因在**厂商 CP 固件**，非主机驱动逻辑） |
| 整包烧录 | ✅ 两轮 `Upgrade firmware ok.`，md5 已登记于主框架仓 `build/MD5SUMS.txt` |

---

## 5. 铁律（改之前先看 `AGENTS.md`）

1. **`src/` 是唯一可信副本**：在源码树里调试改通的改动，必须 `install_board.sh --pull` 拉回 `src/` 再提交，否则换机器就丢。
2. **不要手改 `default.xml`**（它是 `repo manifest -r` 生成的快照）；要加/删 project，改写生成流程并在 `docs/` 记一笔。
3. **固件/镜像不入仓**（`*.bin` `*.img` `out/` `rockdev/` 已被 `.gitignore` 排除）。
4. **板子 IP / 串口 / 服务器账号是机器私有信息**，不写进本仓，按 `AGENTS.md` §4 从本机登记处取。
5. 动手前先写 `docs/WORKLOG.md`，结论写 `docs/PROGRESS.md`（见 `AGENTS.md` §5）。
