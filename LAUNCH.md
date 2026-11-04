# ARK100 上线与宣发执行清单（按 Canvas 计划）

更新：2026-11-04 ~16:02 Asia/Shanghai · 每步做完自动开下一步；主网广播须用户明确授权。

## 已完成
- [x] 玩法/经济/红线定稿
- [x] 品牌日出锁定 + 域名 ark100.vip
- [x] Render 静态站 + DNS
- [x] 宣发静图草稿（主海报/教程/夜洪/进度）
- [x] **P0 官网 v2** NestEgg 级壳 · [ark100.vip](https://www.ark100.vip)
- [x] **P0.5 中英切换** 右上角 中文|EN · PR#2 → `1f48652`（部署中）

## 进行中
- [ ] **一夜 FAQ**（怎么算过了一晚 / 第几晚）→ PR #4 仍待合并
- [x] **公开 openPool 保险（合约侧完成 2026-11-04）**：`ArkSale.openPool()` 无权限；`FloodEngine.start()` 无参数，读取 `sale.openedAt()`；18/18 测试在合约环境通过。本静态仓库同步了 `src/ArkSale.sol`、`src/FloodEngine.sol`、`test/Ark100.t.sol`
- [x] 站上「开池 / 启动洪水」按钮占位：`sold >= 3000 && !opened && !refunding` 才显示开池；`opened && !started` 才显示 `FloodEngine.start()`。地址仍是 `PENDING_MAINNET`，按钮只复制 Agent 说明，不发交易

## 已完成补充
- [x] **沙袋 FAQ** 已上线
- [x] **P1 宣发** 静图 + flood teaser mp4 + X GIF `promo/ark100-flood-teaser-x.gif`（~4.2MB）
- [x] **P2** @ARK100Game 用户已注册并上好头像/banner/简介；置顶预告由用户全套就绪后自发

## 下一步
1. 一夜 FAQ（PR #4）合上并部署
2. 本 PR 的开池 / 启动洪水占位合上后，随 main 的自动部署上线；不要在地址仍是 PENDING_MAINNET 时广播主网
3. **P3** Agent 指令与 CA 占位接线
4. **P4（可选）** Market 2.5%
5. **P5 主网**（仅用户明确授权）→ 同步把连钱包/真铸造/查仓/挂单/开池洪水改成真功能
6. T-3 / T-1 / T0 + 每日战报

## 主网接线后必改真
- 连钱包 / 真铸造 / 真查仓 / 真挂单成交 / 真开池·洪水：CA 写入后同批去掉 PENDING/演示

## 红线
- 不擅自主网 broadcast

## T-1 首晚沙袋（50）
- 合约未预留 admin mint；默认：开池后团队烧 ARK `buy` ≥50 袋，对中奖票 `gift(tokenId, dayIndex)` 链上赠送。
- 不做无限沙袋 / 不做永久特权 mint（破无 owner 红线）。
- 备选（需用户点头）：主网前加 50 袋封顶、发完即死的 promo 入口。

## 官网文案同步
- 用户以玩家视角问的复杂点（如沙袋怎么得）→ 同批补进 FAQ/玩法区双语文案。
