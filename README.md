# ARK100

Static site for ARK100 on BNB Smart Chain (chainId 56). Publish path `./`, build command `echo ok`. `index.html` is served at `/`.

The page reads the fixed ArkSale, TicketNFT, ARK, FloodEngine, SandbagShop, and ArkPot on BSC mainnet. Minting stays paused on the site until the new sale’s `startTime` is set. This page does not call `startSale`. The mint control stays on 铸造已暂停，等待开售 / Minting paused until the sale starts, and no code path sends `ArkSale.mint`.

Tickets bought on the previous sale can be refunded in full only if that sale stays under 3,000 before its pool opens. The refund window is around 2026-11-11 18:36 Asia/Shanghai. Anyone may then call `enableRefunds` on the old ArkSale (`0x5f92105341Cbc09462A0a10973664a322505BF32`), and each payer claims with `refund(tokenId)` from My Ark. Those reads and sends use `ADDR.legacySale` and `ADDR.legacyNft` (`0x815202403e51C6525452dB09FC7c40dD2762D87e`). If the old contract reaches 3,000 sold, it opens the pool automatically and `enableRefunds` cannot succeed after that. Do not mint by calling the old sale contract directly.

The new ArkSale does not use that global switch. After its own `startTime + 7 days`, and only while the pool is still closed, the current holder calls `refund(tokenId)` on the new sale. That burns the ticket, returns that ticket’s `paidBnb`, and lowers `sold` by one, so the pool still opens automatically at 3,000 live paid tickets. Minting continues through the window. A refund does not give the original minter another mint slot. While `startTime` is 0 the site hides the new-sale refund control. The deployed suite at `0xB69f…` was never started; `script/DeployFixedSuite.s.sol` redeploys the whole set and must not be broadcast from this repo.

The tide, mint quote, markets, flood, sandbag shop, pot, and ARK token read the new suite. Addresses are in `js/chain.js`.

Secondary trading uses the fixed suite on BSC: `TicketMarketBNB`, `TicketMarketARK`, and `TicketBidMarket`, each bound to the new TicketNFT. Addresses are in `js/chain.js`. A zero address would leave that book blank with 市场合约待部署; these three are set.

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

The new TicketNFT (`0x48eb4F2FB2C4D6765C8156428b7639F6dD92B70e`) is the book the markets trade. The previous TicketNFT (`0x815202403e51C6525452dB09FC7c40dD2762D87e`) stays in place so the tickets already sold can be refunded through the old ArkSale. It is not the listing book.

### Deployed on BSC mainnet (fixed suite)

`startSale` has not been called on the new ArkSale. This site does not call it. `feeRecipient` on the three markets remains `0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74`.

| Contract | Address |
| --- | --- |
| `ArkPot` | `0x3456AD558d17eF7D11646abfF6e602Ce647f40E3` |
| `ArkToken` (ARK) | `0xF6E13Cd0D344f6De19392d526387667b33c74580` |
| `TicketNFT` | `0x48eb4F2FB2C4D6765C8156428b7639F6dD92B70e` |
| `FloodEngine` | `0x5f58A3d0cd684774bc6075bf588f345a391e637c` |
| `SandbagShop` | `0xD82fa4Dfa0086712CEB3986C453747a257E8655f` |
| `ArkSale` | `0xB69f1F7A14dbCbB82A5eFcCB4B7579410eEc746E` |
| `TicketMarketBNB` (`marketBnb`) | `0x9162AB0b4eC0Bb3cf5C3b53e3b19f866E2c54eA1` |
| `TicketMarketARK` (`marketArk`) | `0xBF6cE810aFc7974Da041299a16cb016b3ad45449` |
| `TicketBidMarket` (`marketBid`) | `0x480Fb7a8FA5feaBe3a20F7424669D9a63342f8Dd` |
| Pancake ARK/WBNB `launchPair` | `0x89cf36021Ac16f031F3E04D122d024663130499e` |

`launchPair` is the predicted PancakeSwap V2 address. It has no contract code until the pool is created at open.

Previous suite, refunds only. `enableRefunds` succeeds only if that sale is still unopened and `startTime + 7 days` has passed (around 2026-11-11 18:36 Asia/Shanghai), and only while sales stay under 3,000 so the old pool does not open.

| Contract | Address |
| --- | --- |
| Old `ArkSale` (`legacySale`) | `0x5f92105341Cbc09462A0a10973664a322505BF32` |
| Old `TicketNFT` (`legacyNft`) | `0x815202403e51C6525452dB09FC7c40dD2762D87e` |

Those addresses are in `js/chain.js`. ABIs are in `abi/`. The site encodes the same function selectors directly, the same way mint does, and reads `MARKET_FEE_BPS` from each book.

`forge test` runs `test/market` (fee, cancel, sunk and pending-cabin rejects, bid post / fill / cancel / expiry). The older `test/Ark100.t.sol` imports contracts that are not published in this repo, so it sits outside that test path.
