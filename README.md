# ARK100

Static site for ARK100 on BNB Smart Chain (chainId 56). Publish path `./`, build command `echo ok`. `index.html` is served at `/`.

The page reads ArkSale, TicketNFT, ARK, FloodEngine, SandbagShop, and ArkPot. Minting is paused on the site: the mint control stays on 铸造已暂停，合约升级中 / Minting paused, contract upgrade in progress, and no code path sends `ArkSale.mint`. In the current sale contract, BNB paid for tickets after the pool opens would not go into the liquidity pool. A fixed contract will be deployed separately. Existing tickets can be refunded in full only if sales stay under 3,000 before the pool opens. The refund window is around 2026-11-11 18:36 Asia/Shanghai. Anyone may then call `enableRefunds`, and each payer claims with `refund(tokenId)` from My Ark. If the old contract reaches 3,000 sold, it opens the pool automatically and `enableRefunds` cannot succeed after that. Do not bypass the site and mint by calling the old sale contract directly.

Secondary trading is live on BSC: `TicketMarketBNB`, `TicketMarketARK`, and `TicketBidMarket`. Addresses are in `js/chain.js`. A zero address would leave that book blank with 市场合约待部署; these three are set.

Cabin rates are the TicketNFT numbers: Economy 70% at 100 ARK/day, Business 25% at 200, Captain 5% at 600, drawn after mint with `requestCabin` / `settleCabin`. Sunk tickets produce 0. The 0.70 / 0.25 / 0.05 figures are cabin-draw probabilities. 150 ARK/day is the expected value across that draw, not a floor. A roughly 7-day payback is an open-price anchor, not a promise. Unprotected tickets: about 2–3% on nights 1–7, about 3–8% on nights 8–100.

The top bar switches 中文 / EN (`localStorage` key `ark100-lang`). A `zh` browser language opens in Chinese; every other language opens in English.

## Ticket market (NestEgg-style)

Two listing books and one bid book. BNB and ARK never share a contract. There is no Agent ID check on list, buy, or bid. Mint still requires one.

| Contract | Pays in | Calls |
| --- | --- | --- |
| `TicketMarketBNB` | BNB wei | `approve` the ticket, `list(tokenId, priceWei)`, `buy(tokenId)` with `value = price`. Extra BNB is refunded. |
| `TicketMarketARK` | ARK wei | `approve` the ticket, `list(tokenId, priceWei)`, `ARK.approve` the market, `buy(tokenId)` with no BNB. |
| `TicketBidMarket` | BNB escrow | `postBid(kind, param, unitPrice, qty, duration)` with `value = unitPrice * qty`. Seller `approve`s then `acceptBid(bidId, tokenId)` for one unit. |

`MARKET_FEE_BPS` is `250` (2.5%) on each contract. The fee is paid to `feeRecipient` on every sale and every bid fill. Rounding dust stays with the seller.

Listable tickets are afloat (`isAlive`) and not inside `requestCabin` (`tickets(id).cabinCommitBlock == 0`). Sunk tickets and tickets with a cabin commit still set are rejected. A cabin that has not been requested yet (cabin 0, commit 0) can be listed. Cabin, claim clock, and minter stay on TicketNFT and move with `transferFrom`. The markets do not escrow the NFT: the seller approves, and the market pulls with `transferFrom` at fill time. `buy` rechecks owner, approval, and listability. Anyone can `cleanListing` a stale row. The seller `cancel`s their own row.

Bid kinds match NestEgg EggBidMarketV2: `0` any listable ticket (`param` 0), `1` cabin (`param` 0 unsettled, 1 economy, 2 business, 3 captain), `2` one `tokenId` (`qty` must be 1). Duration is 1 hour to 30 days. The buyer can `cancelBid` any time the bid is open. After `expires`, anyone can `refundExpired`. A fill of the last unit closes the bid.

The live TicketNFT (`0x815202403e51C6525452dB09FC7c40dD2762D87e`) is a normal ERC-721. `transferFrom` / `approve` are open. There is no transfer hook blocking sales, so this change does not redeploy TicketNFT, ArkSale, or FloodEngine.

### Deployed on BSC mainnet

Do not deploy these again. `script/DeployMarkets.s.sol` records the constructor args used:

- `ticketNft`: `0x815202403e51C6525452dB09FC7c40dD2762D87e`
- `arkToken` (ARK market only): `0xBCbA6cFc97d2c0A4Dcf22295D92EF5227B5db712`
- `feeRecipient`: ArkSale `projectWallet()`, also ArkToken `projectWallet()`, `0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74`

| Book | Address | Deploy tx |
| --- | --- | --- |
| `TicketMarketBNB` (`marketBnb`) | `0xC24b79485705cEF5AfF36fb4c4cCda34F8423d95` | [`0xc1d70e60ef4b9e7c3e1fb137b665701bcee5c9c0722eb16ec7b20bc68642055b`](https://bscscan.com/tx/0xc1d70e60ef4b9e7c3e1fb137b665701bcee5c9c0722eb16ec7b20bc68642055b) |
| `TicketMarketARK` (`marketArk`) | `0x3fF61e70B89dc5b0EDD9a7f27435d6604683Bd64` | [`0x1a8c2859d6957be284da4bf2353446467fb4cc0733d5392d943b7deede78abb0`](https://bscscan.com/tx/0x1a8c2859d6957be284da4bf2353446467fb4cc0733d5392d943b7deede78abb0) |
| `TicketBidMarket` (`marketBid`) | `0xbC58134B8596e8A12050fcDF2435F42Ea0E2Aa32` | [`0x1277e5eca9d58adb69bab65b88848961afdf9ec408159f56a646f4f3444f67e7`](https://bscscan.com/tx/0x1277e5eca9d58adb69bab65b88848961afdf9ec408159f56a646f4f3444f67e7) |

Those addresses are already in `js/chain.js`. ABIs are in `abi/`. The site encodes the same function selectors directly, the same way mint does, and reads `MARKET_FEE_BPS` from each book.

`forge test` runs `test/market` (fee, cancel, sunk and pending-cabin rejects, bid post / fill / cancel / expiry). The older `test/Ark100.t.sol` imports contracts that are not published in this repo, so it sits outside that test path.
