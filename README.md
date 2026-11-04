# ARK100

Static site for ARK100 on BNB Smart Chain (chainId 56). Publish path `./`, build command `echo ok`. `index.html` is served at `/`.

The page reads ArkSale, TicketNFT, ARK, FloodEngine, SandbagShop, and ArkPot. A connected wallet can send `ArkSale.mint` only after `startTime` is set and the current block is at or after that time. Until then the mint control stays on 正式未开售 / Sale not started and does not send a transaction.

Cabin rates are the TicketNFT numbers: Economy 70% at 100 ARK/day, Business 25% at 200, Captain 5% at 600, drawn after mint with `requestCabin` / `settleCabin`. Sunk tickets produce 0. The 0.70 / 0.25 / 0.05 figures are cabin-draw probabilities. 150 ARK/day is the expected value across that draw, not a floor. A roughly 7-day payback is an open-price anchor, not a promise. Unprotected tickets: about 2–3% on nights 1–7, about 3–8% on nights 8–100.

The top bar switches 中文 / EN (`localStorage` key `ark100-lang`). A `zh` browser language opens in Chinese; every other language opens in English.
