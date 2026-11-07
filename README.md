# ARK100

Static site for ARK100 on BNB Smart Chain (chainId 56). Publish path `./`, build command `echo ok`. `index.html` is served at `/`.

The page reads the fixed ArkSale, TicketNFT, ARK, FloodEngine, SandbagShop, and ArkPot on BSC mainnet. Frontend mint is unpaused (`MINT_PAUSED` is false). This page does not call `startSale`. The new ArkSale `startTime` is already set (2026-11-05 20:00 Asia/Shanghai) and the sale is open: a wallet with an Agent ID and a non-empty name can mint, max 10 per address. The pool is still closed and opens at 3,000. If a later chain read says the sale has not started, the control returns to 正式未开售 / Sale not started. Until the board loads, the page defaults to 已开售 / Minting open and does not send a mint.

Tickets bought on the previous sale can be refunded in full only if that sale stays under 3,000 before its pool opens. The refund window is around 2026-11-11 18:36 Asia/Shanghai (19:36 Tokyo). The page keeps an old-ticket refund card on that sale: it shows the old sold count, the window in Beijing and Tokyo, a countdown, and an `enableRefunds` button that stays disabled until the window opens. My Ark lists that wallet’s old tickets with Claim refund disabled until the old sale is refunding. The new sale has no `enableRefunds` step. Its refund card stays hidden while `startTime` is 0. `startTime` is already set, so the card shows a countdown until `startTime` + 7 days (2026-11-12 20:00 Asia/Shanghai). After that, and only while the pool is closed, My Ark shows a per-ticket refund for the current holder. Minting continues, and the pool still opens at 3,000 live tickets. A refund burns the ticket and does not free the 10-per-address mint cap. Those old reads and sends use `ADDR.legacySale` and `ADDR.legacyNft` (`0x815202403e51C6525452dB09FC7c40dD2762D87e` / `0x5f92105341Cbc09462A0a10973664a322505BF32`). If the old contract reaches 3,000 sold, it opens the pool automatically and refunds cannot be enabled after that. Do not mint by calling the old sale contract directly.

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

The new TicketNFT (`0xDF2aF96477aBe8E5Eaa9Cf79650D58917e6c3490`) is the book the markets trade. The previous TicketNFT (`0x815202403e51C6525452dB09FC7c40dD2762D87e`) stays in place so the tickets already sold can be refunded through the old ArkSale. It is not the listing book.

### Deployed on BSC mainnet (fixed suite)

`startSale` has been called on the new ArkSale. `startTime` is 2026-11-05 20:00 Asia/Shanghai. This site does not call `startSale`. The sale is open and `opened` is still false. `feeRecipient` on the three markets remains `0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74`.

| Contract | Address |
| --- | --- |
| `ArkPot` | `0x99aF1fF0056D195a907590529d53D11C7913Ddc0` |
| `ArkToken` (ARK) | `0x97F7025f2999bF9468Ae74bDeBB688105976bE33` |
| `TicketNFT` | `0xDF2aF96477aBe8E5Eaa9Cf79650D58917e6c3490` |
| `FloodEngine` | `0xE426bCf166Fe48626DD6114B049375b6ff9B9825` |
| `SandbagShop` | `0x7d3953B2130DE00A54195335Ac3D6863fb21B498` |
| `ArkSale` | `0x64a67c2D48898D414DbD63F56deAbD0988C2Af65` |
| `TicketMarketBNB` (`marketBnb`) | `0x5E42aA493317ba4E7582638c6b36C1A5f1836dB0` |
| `TicketMarketARK` (`marketArk`) | `0xCc355eF294af0B077666944b2D0271C40D17D17d` |
| `TicketBidMarket` (`marketBid`) | `0x1788Dda94DB19e0Da9467B421DCD9539Be4220c9` |
| Pancake ARK/WBNB `launchPair` | `0x5FA6c91C846FF96ABdd694F85F123Cf49aA90662` |

`launchPair` is the predicted PancakeSwap V2 address. It has no contract code until the pool is created at open.

Previous suite, refunds only. `enableRefunds` succeeds only if that sale is still unopened and `startTime + 7 days` has passed (around 2026-11-11 18:36 Asia/Shanghai), and only while sales stay under 3,000 so the old pool does not open.

| Contract | Address |
| --- | --- |
| Old `ArkSale` (`legacySale`) | `0x5f92105341Cbc09462A0a10973664a322505BF32` |
| Old `TicketNFT` (`legacyNft`) | `0x815202403e51C6525452dB09FC7c40dD2762D87e` |

Those addresses are in `js/chain.js`. ABIs are in `abi/`. The site encodes the same function selectors directly, the same way mint does, and reads `MARKET_FEE_BPS` from each book.

`forge test` runs `test/market` (fee, cancel, sunk and pending-cabin rejects, bid post / fill / cancel / expiry). The older `test/Ark100.t.sol` imports contracts that are not published in this repo, so it sits outside that test path.

## Referral tag

`js/ref.js` is included before `js/chain.js`. On each page load it reads `?ref=`.

Two shapes are accepted. A named KOL code is lowercased, every character outside `[a-z0-9_]` is dropped, and the result is kept only when its length is 1 to 20. A wallet invite is a full address: `0x` plus 40 hex digits, any case, or 40 hex digits with no prefix. It is stored as lowercase `0x` plus 40 hex. The 20-character cap stays on names. That alphabet cannot hold a 20-byte address without dropping bits, and the report has to recover the full referrer address. Anything else is ignored.

A valid ref is stored in `localStorage` key `ark100_ref` as `{"ref":"...","ts":<ms>}`. The first valid ref wins for 30 days: an unexpired record is not replaced, and an expired record is replaced by the next valid `?ref=`. Internal links do not need to keep the query. When a ref is active, the boarding slip shows a small muted `ref:` line. If the connected wallet is that same address, the line stays hidden and the mint is not tagged.

`sendMint` is the only sender that uses it, and only for the new ArkSale (`0x64a67c2D48898D414DbD63F56deAbD0988C2Af65`, `mint(uint256)`, selector `0xa0712d68`). After the ABI-encoded `uint256` count it appends the UTF-8 bytes of `ARKREF:` plus the ref. Solidity does not read trailing calldata, so the mint still executes. No suffix is added when there is no unexpired ref, or when the connected wallet equals an address ref (self-referral). `legacySale` and every other transaction are unchanged. `sendTx` runs `eth_call` and `eth_sendTransaction` with that same `data`. `isSaleMint` matches the selector prefix, so the suffix still counts as a sale mint.

The boarding slip shows 邀请好友上船 before a wallet connects. The reward sentence is already visible: it reads the single constant `PLAYER_REWARD` in `js/ref.js` (`"0.05"`, shown as 5%). Friends who mint through the link earn the referrer that fraction of the ticket payment, settled weekly, paid in BNB to the referrer wallet. The contract does not move this BNB. The owner sends it from the report. A guest line says that connecting a wallet generates the personal link, and the connect button in the card uses the same wallet connect as the boarding slip. The link, copy, and post on X stay off until a wallet is connected. After it connects, the link is `https://www.ark100.vip/?ref=` plus that wallet address. Copy puts the link on the clipboard. Post on X opens an intent with a short boarding line and the same link.

Invite and share links use `www` on purpose. `https://ark100.vip/?ref=` answers `301` to `https://www.ark100.vip/` and drops the query. The same redirect keeps the query on other paths, such as `/js/ref.js?a=1` and `/index.html?ref=`. That response is Render’s automatic custom-domain redirect, cached at the edge (`cf-cache-status: HIT`, no `rndr-id`), so the static site never sees the apex request. A Blueprint `routes` rule does not apply to it: Render skips redirect and rewrite rules when a file already exists at the path, and `/` is `index.html`. The apex response is not this page, so a script cannot read `?ref=`. The follow-up request to `www` is cross-origin, and its `Referer` does not carry the query. There is no in-repo redirect or script that puts the query back. Links already shared on the apex root stay untagged.

### Referral report

```
node scripts/ref-report.mjs [--from-block N] [--to-block N] [--share 0.35] [--team-ratio 0.2] [--player-reward 0.05] [--out file.csv]
RPC=https://bsc-dataseed.binance.org node scripts/ref-report.mjs
```

Node 18+, no packages. The RPC default is `https://bsc-dataseed.binance.org` (`RPC` or `--rpc` overrides it). That host serves `eth_call` and `eth_getTransactionByHash`, and it rejects `eth_getLogs` with `-32005 limit exceeded`. When that happens, log queries fall back to `https://bsc.publicnode.com` and then `https://bsc-rpc.publicnode.com`, the same log endpoints `js/chain.js` uses. A configured RPC that already serves logs is used as-is. The script scans ArkSale for successful direct `mint(uint256)` calls from the start block through latest. The default start block is the first block whose timestamp is at least `1793880000` (the new sale `startTime`, 2026-11-05 20:00 Asia/Shanghai), found by binary search. `--from-block` skips that search.

Transaction hashes come from `ArkSale` `Minted(address,uint256,uint256,uint256,string)` logs (topic `0xd8b419dcb55349414000518e58bc0ec29a3419a418cc9ab706cd9db1260cb2f4`, the same topic `js/chain.js` labels `minted`). `eth_getLogs` is requested in 5,000-block chunks. If that query cannot be served, the script falls back to TicketNFT `0xDF2aF96477aBe8E5Eaa9Cf79650D58917e6c3490` `Transfer` logs from `0x0`. Each unique hash is loaded with `eth_getTransactionByHash`. A row is kept when `to` is ArkSale and the input starts with `0xa0712d68`. The ticket count is the first ABI word, BNB paid is `tx.value`, and a trailing `ARKREF:` tag is decoded when the extra bytes are exactly that prefix plus either a 1–20 character `[a-z0-9_]` code or a full address. Untagged mints are grouped as `(none)`. A mint whose sender is the address in the tag is `kind=self` and is not paid.

The CSV columns are `hash,block,from,tickets,value_wei,bnb_paid,ref,kind`. The stderr summary groups those rows per ref: kind, tx count, tickets, BNB paid, team BNB, payout, and the payable address when the ref is a wallet.

`--share` defaults to `0.35` and applies only to named KOLs. That amount is a cut of team revenue, not of gross BNB:

```
team_bnb = floor(bnb_paid * team_ratio)
payout_bnb = floor(team_bnb * share)
```

An address referrer is paid a share of the ticket payment. `PLAYER_REWARD` in `js/ref.js` is the only default (`"0.05"`). `--player-reward` overrides that run:

```
payout_bnb = floor(bnb_paid * player_reward)
```

The summary ends with `payable addresses`: address, tickets, BNB paid, and payout. Those are the wallets to transfer, by hand, on the weekly settlement. Self-referrals are omitted from that list.

`team_ratio` is the fraction of BNB paid that belongs to the team. ArkSale exposes it as the public constant `TEAM_BPS`. Read it with an `eth_call` to `0x64a67c2D48898D414DbD63F56deAbD0988C2Af65` and data `0xd5861d91` (`TEAM_BPS()`), then divide by 10,000. The deployed constant is `2000`, so the fraction is `0.2`. The script uses that call unless `--team-ratio` is passed. If the call fails and the flag is omitted, it does not guess: named payouts stay blank. Address payouts still fill, because they do not use `team_ratio`.

Before the pool opens, the team leg accrues in `teamDue` and is paid to `projectWallet` inside `openPool`. After open, each mint pays that leg immediately. `POT_BPS` is `1500` (15% pot) and is not part of the named-KOL base. `bnb_paid` is the transaction value. The contract refunds any overpay above the mint quote before the split, so a manual overpay is larger than the BNB that is divided. Mints sent from this site use the quoted amount.

`node --test scripts/ref-test.mjs` checks sanitizing, the 30-day first-touch rule, named and address calldata with and without the suffix, self-referral exclusion, both payout formulas, and that the report decoder reads the same bytes.
