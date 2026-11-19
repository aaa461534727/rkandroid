# rk3576_android14/docs — 文档目录

> 文档目录入口. 主项目入口看 `../README.md`.

## 文档清单

| 文件 | 作用 | 状态 |
|------|------|------|
| `PROGRESS.md` | 进度跟踪 (L2 结果层, 事后写) | 必填 |
| `WORKLOG.md` | 操作流水现场 (L4 实时层, **动手前就写**, 防死机丢现场 — 见顶层 `AGENTS.md` §14) | 必填 |
| `CAPTURES.md` | **取证台账**: `captures/` 每个文件的 md5 / 抓取命令 / 证明什么 —— **换机器靠它重抓** (见顶层 `AGENTS.md` §14.6) | 有取数就填 (台账入仓, 数据不入仓) |
| `SESSION_HANDOFF.md` | **交接卡**: 上个 AI 停在哪 / 下一步 / 坑 (1 屏快照, 换 AI 先读这页) | 必填 |
| `BOARD.md` | **板卡与硬件核对表**: 型号 / IP / 串口 / 账号 / 固件 md5 / 上板命令 | 有板子就填 |
| `ARCHITECTURE.md` | 架构图/设计 | 选填 |
| `<其他>.md` | ... | ... |

## 按主题找文档

- **想了解整体**: 看 `../README.md` + `ARCHITECTURE.md`
- **想看进度**: 看 `PROGRESS.md`
- **想快速恢复现场 (1 分钟)**: 先看 `SESSION_HANDOFF.md`, 再看 `WORKLOG.md` 最上面 10~20 条 (§14)
- **想上板 / 核对硬件**: 看 `BOARD.md` (IP / 串口 / 固件 md5)
- **想找"哪份数据证明的结论"**: 看 `CAPTURES.md` (取证台账: md5 + 抓取命令 + 证明什么)
- **想了解踩坑**: 看 `<踩坑>.md` 或 grep `## 踩坑` / `## 问题`
- **想编译运行**: 看 `../README.md` 编译入口段

---

## 本仓发布范围（2026-11-19）

| 目录 | 是否随本仓发布 | 说明 |
|---|---|---|
| `docs/` `src/` `scripts/` `manifests/` `default.xml` | ✅ 是 | 文档 / 板级叠加层 / 脚本 / 源码定义 |
| `captures/` | ✅ 是 | 决定性取证原始数据（空口抓包等），`docs/CAPTURES.md` 有 md5 + 重抓命令 |
| `logs/`、`build/logs/`、`build/MD5SUMS.txt` | ❌ 否 | 体积大、含构建噪声；结论已写进 `docs/PROGRESS.md`，需要时按 `docs/CAPTURES.md` 的方法重抓/重编 |
| 固件 `.bin` / 镜像 `.img` / `out/` / `rockdev/` | ❌ 否 | 厂商授权文件与构建产物，`.gitignore` 排除；版本靠 `src/firmware/swt6652x/md5.txt` 认 |
