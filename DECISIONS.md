# ARK100 已锁定决策

更新时间：2026-11-04（Asia/Shanghai）

## 已拍板

| # | 项 | 决定 |
|---|---|---|
| 1 | 团队收款钱包 | **Amajun** `0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74`，部署时 immutable 写入 `ArkSale` / `ArkToken` |
| 2 | Agent ID 注册表 | NestEgg 同款 `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`，经 `AgentIdRegistryVerifier` 包装 |
| 3 | 开池种子 ARK | **350,000,000 ARK**（`ArkSale.POOL_SEED_ARK`）；临上线再按目标开盘价精算，现不改 |
| 4 | 团队留货 | **不做**合约级预留 / 免费票 / ARK 预挖；开铸后 heya、Amajun 按玩家规则各买最多 10 张 |

## 经济常量（同合约）

- 总量 10,000 票；每址 / Agent 槽位最多 10
- 阶梯 USD：$2 / $3 / $4 / $5（边界 2500 / 5000 / 7500 / 10000）
- 闲置 5 分钟降一档，地板 $2
- #3000 自动开 ARK/WBNB；LP → `0xdead`
- 铸造款：65% 池储备 · 15% 奖池 · 20% 团队（开池前全额托管；7 天未开池可全额退）
- 交易税写死 2% = 烧 0.5% + 奖池腿 0.5% + 团队 1%
- 官方市场 2.5%：v1 **未实现**（记入 v1.1）

## 红线（不可破）

- Sale / Pot 无 `withdraw` / `rescue` / `sweep`
- 无升级代理、无黑名单、无暂停卖出、税率不可调
- 未开池失败路径必须可全额退
- 密钥 / 私钥只走环境变量，不进仓库与提示词

## 未决 / 延后

- 残骸 NFT 与官方市场 2.5%（v1.1）
- 域名选购与 Render 上线时机（见 README 下一步）
- 主网广播时机（需用户明确授权）
- 开盘目标价精算后是否微调 `POOL_SEED_ARK`

## 配置文件

- `script/config.mainnet.json` — 主网锁定参数 + 部署占位
- `script/Deploy.s.sol` — Foundry 脚本；**默认不要 `--broadcast`**

| 5 | T-1 首晚沙袋 50 | **不预留 admin mint**；开池后 buy+gift 空投；不做无限沙袋 |

## 2026-11-04 公开开池保险
- `ArkSale.openPool()`：任何人可调；条件 `sold >= OPEN_AT && !opened && !refunding`；nonReentrant；复用 `_openPool()`，发同一 `PoolOpened` 事件。mint 内自动开池保留。无新增权限。
- `ArkSale.openedAt`：`_openPool()` 写入 `block.timestamp`（新存储变量放在末尾，不动旧槽位）。
- `FloodEngine.start()`：去掉参数，改读 `sale.openedAt()` 并要求 `sale.opened()`；仍然任何人可调、只能一次。原 `start(uint256)` 任何人可传任意时间戳抢先调用、篡改洪水日历——已修复。
