# ARK100

Static site for ARK100 on BNB Smart Chain (chainId 56). Publish path `./`, build command `echo ok`. `index.html` is served at `/`.

The page reads ArkSale, TicketNFT, ARK, FloodEngine, SandbagShop, and ArkPot. A connected wallet can send `ArkSale.mint` only after `startTime` is set and the current block is at or after that time. Until then the mint control stays on 正式未开售 / Sale not started and does not send a transaction.

Secondary trading is a separate set of contracts (`TicketMarketBNB`, `TicketMarketARK`, `TicketBidMarket`). Until their addresses replace the zero addresses in `js/chain.js`, the market section says 市场合约待部署 and does not send trades.

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

### Deploy (not done in this PR)

`script/DeployMarkets.s.sol` deploys all three. Constructor args, BSC mainnet:

- `ticketNft`: `0x815202403e51C6525452dB09FC7c40dD2762D87e`
- `arkToken` (ARK market only): `0xBCbA6cFc97d2c0A4Dcf22295D92EF5227B5db712`
- `feeRecipient`: ArkSale `projectWallet()`, also ArkToken `projectWallet()`, `0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74`

```bash
forge script script/DeployMarkets.s.sol --rpc-url https://bsc-dataseed.binance.org --broadcast --private-key $DEPLOYER_KEY
```

Paste the three addresses into `js/chain.js` (`marketBnb`, `marketArk`, `marketBid`) in place of the zero addresses. ABIs for those contracts are in `abi/`. The site encodes the same function selectors directly, the same way mint does. The page reads `MARKET_FEE_BPS` from whichever book is deployed.

`forge test` runs `test/market` (fee, cancel, sunk and pending-cabin rejects, bid post / fill / cancel / expiry). The older `test/Ark100.t.sol` imports contracts that are not published in this repo, so it sits outside that test path.
