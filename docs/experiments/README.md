# bak-20261119-snap-exp — 清盘前保存：SDK 树比 src/ 多出的 4 个文件改动

**背景**: 2026-11-19 主人要求清空 `/dev/sdb`(295G) 上的 RK3576 Android 源码树，改做 RK3528 安卓。
清空前 SDK 树里还有 4 个文件的改动**没有回收进 src/**，先存成补丁，防止丢失。

`src/` 补丁, 见 `sdk-vs-src.patch` (13 KB):

| 文件 | 改动内容 | 状态 |
|---|---|---|
| `skwifi/skw_core.c` | ① TX 描述符布局 v1 (`padding=2 / gap=0`, eth 固定偏移 8) ② `skw_setup_txba()` 开头 `if (1) return;` 完全停掉 TX BA ③ **SNAP 插入实验**(以太头后插 8 字节 `AA AA 03 00 00 00 <ethertype>`) | ①②已验证(空口 ARP/ICMP 完好); ③**未验证**(只做到"推板+重启无断言") |
| `skwifi/skw_rx.c` | 下行单播不再依赖 `desc->msdu_offset == 0`，改按 `msdu_len+6` / `skb->len-18` 双长度自检投递 | ✅ 已验证(RX 单播通了) |
| `skwifi/skw_msg.c` | 同步命令超时改为连续 3 次才 `skw_hw_assert`，任意 ACK 清零 | ✅ 已验证(板子不再因 `SKW_CMD_DISCONNECT` 断言) |
| `skwifi/skw_cfg80211.c` | scan 请求 `skw_scan_chan_info` → `u16` 通道号 | ✅ 已验证(扫描正常) |

清理动作: 清盘后这 4 个改动已由 `install_board.sh --pull` 回收进 `src/`（2026-11-19），
本补丁仅作历史留档 —— 想看"回收前 src 长什么样"用 `patch -R`。
