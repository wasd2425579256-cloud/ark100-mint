/* ARK100 BSC mainnet reads and wallet sends. chainId 56. */
(function (global) {
  var CHAIN_ID = 56;
  var LOG_FROM = 131743398;
  var ADDR = {
    nft: "0xDF2aF96477aBe8E5Eaa9Cf79650D58917e6c3490",
    ark: "0x97F7025f2999bF9468Ae74bDeBB688105976bE33",
    sale: "0x64a67c2D48898D414DbD63F56deAbD0988C2Af65",
    flood: "0xE426bCf166Fe48626DD6114B049375b6ff9B9825",
    shop: "0x7d3953B2130DE00A54195335Ac3D6863fb21B498",
    pot: "0x99aF1fF0056D195a907590529d53D11C7913Ddc0",
    // TicketMarketBNB / TicketMarketARK / TicketBidMarket on the fixed BSC suite.
    // feeRecipient is the constructor arg 0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74.
    marketBnb: "0x5E42aA493317ba4E7582638c6b36C1A5f1836dB0",
    marketArk: "0xCc355eF294af0B077666944b2D0271C40D17D17d",
    marketBid: "0x1788Dda94DB19e0Da9467B421DCD9539Be4220c9",
    // Previous suite. Refunds of the tickets already sold stay on these contracts.
    // enableRefunds only if !opened && startTime + 7 days. Do not mint against them.
    legacySale: "0x5f92105341Cbc09462A0a10973664a322505BF32",
    legacyNft: "0x815202403e51C6525452dB09FC7c40dD2762D87e",
    // Predicted PancakeSwap V2 ARK/WBNB pair. The pair contract is created when the pool opens.
    launchPair: "0x5FA6c91C846FF96ABdd694F85F123Cf49aA90662",
    verifier: "0xf14F5cF3fCB976082Df08dA1609D1698C39Ff2e2",
    registry: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
    router: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
    feed: "0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE"
  };
  var CALL_RPCS = [
    "https://bsc-dataseed.binance.org",
    "https://bsc-dataseed1.binance.org",
    "https://bsc-dataseed1.defibit.io",
    "https://bsc-dataseed1.ninicoin.io",
    "https://bsc.publicnode.com"
  ];
  var LOG_RPCS = [
    "https://bsc.publicnode.com",
    "https://bsc-rpc.publicnode.com"
  ];
  var SEL = {
    sold: "0x02c7e7af",
    startTime: "0x78e97925",
    opened: "0x5f88eade",
    openedAt: "0x38930203",
    refunding: "0xf43e98c7",
    currentTier: "0xd679677a",
    priceUsd: "0x8b3948bd",
    quoteMint: "0x665216c6",
    bnbUsd: "0x58614dbf",
    lastMintTime: "0x9d463520",
    mint: "0xa0712d68",
    openPool: "0xeb5797a4",
    enableRefunds: "0x8c52dc41",
    refund: "0x278ecde1",
    payer: "0x561874ee",
    paidBnb: "0xf88e127c",
    started: "0x1f2698ab",
    currentDayIndex: "0xdbb8cc46",
    dayState: "0x68b9fa97",
    start: "0xbe9a6555",
    commit: "0xf4f98ad5",
    settleBatch: "0xad28484a",
    landfall: "0x111bfda0",
    totalMinted: "0xa2309ff8",
    aliveCount: "0x0145a938",
    balanceOf: "0x70a08231",
    mintedBy: "0x3cef28d2",
    ownerOf: "0x6352211e",
    cabinOf: "0xa768222b",
    isAlive: "0xd84b2361",
    yieldClaimed: "0xfe271972",
    pendingArk: "0x17d15042",
    tickets: "0x50b44712",
    requestCabin: "0x0ac028a7",
    settleCabin: "0x2cdf61fe",
    claim: "0x379607f5",
    isSurvivor: "0x7c649965",
    shopPrice: "0xa035b1fe",
    basePrice: "0xf86325ed",
    bags: "0x8c4c2801",
    protectedUntil: "0x736e07b9",
    buy: "0xd96a094a",
    applyBag: "0x840ced87",
    landed: "0x939a1b1b",
    survivorCount: "0x6f7840b2",
    sharePerTicket: "0xb771d65d",
    claimShare: "0x0cc03e7a",
    officialPair: "0x2eab62e4",
    pair: "0xa8aa1b31",
    totalSupply: "0x18160ddd",
    verify: "0x63a9c3d7",
    handleOf: "0xc50a1514",
    marketFeeBps: "0x553c0248",
    marketList: "0x50fd7367",
    marketBuy: "0xd96a094a",
    marketCancel: "0x40e58ee5",
    cleanListing: "0x48f0fda2",
    listings: "0xde74e57b",
    activeListingIds: "0xc771682a",
    buyable: "0xb0936aa2",
    postBid: "0x03ddc73f",
    acceptBid: "0x02e9d5e4",
    cancelBid: "0x9703ef35",
    refundExpired: "0x1402b17a",
    bidOf: "0x649ccc14",
    activeBidIds: "0x9985df97",
    activeBidIdsPage: "0x6d8ffe99",
    approve: "0x095ea7b3",
    allowance: "0xdd62ed3e",
    getApproved: "0x081812fc",
    isApprovedForAll: "0xe985e9c5"
  };
  var PLAYER_TOPIC = {
    "0xd8b419dcb55349414000518e58bc0ec29a3419a418cc9ab706cd9db1260cb2f4": "minted",
    "0xd4bad73c5099a3769d4429c744e3f7d60ecdc476a5365a1e001f7c786bbb5e2d": "cabin",
    "0x7a9a06c55874350326aa34f26931e1884daaed485fbceacf63ee7dca789abcc0": "cabinAsk",
    "0xf2bd1f32e2adf49754b48f76d4783ba580d903abb1fad49fbc47f22744306c7b": "sunk",
    "0x75f99453bf011afe339701989b45715b8caf401b4b1bb9e34aca566c946df33f": "flood",
    "0xedba86fd2b22962d534e70ad9b0ff8730de46f636146f2bab6a72cbb1ebbcc53": "sandbag",
    "0x4f85fed081fb11cf3f5a6e5de7b1b68ca75da06da0d59626888faead638b9630": "pool",
    "0xa78c547613f6306e7a70d1bd161c18a496cae1eeb8d4f9e58b60d69ad72ddf58": "sale",
    "0x7b410a12695cc08d97420d25b1c0ccffa0dc9aed0ccb52ca0a4cbe5f1f9756f4": "applied",
    "0x6036d47c571ff73dc29478cdb7431b7b739983b3960894623bbbebd69294bd82": "commit",
    "0x7ca5472b7ea78c2c0141c5a12ee6d170cf4ce8ed06be3d22c8252ddfc7a6a2c4": "refund",
    "0x006e0c97de781a7389d44ba8fd35d1467cabb17ed04d038d166d34ab819213f3": "floodStart",
    "0xae7e9d1786fc96dc90791724a07fa79f77df8dd7656543fb746238843ea79ce2": "gift"
  };
  var CABIN_RATE = { 1: 100, 2: 200, 3: 600 };
  var watchers = [];
  var account = "";

  function fail(code) {
    var err = new Error(code);
    err.code = code;
    return err;
  }

  function hexUint(n) {
    var v = BigInt(n);
    if (v < 0n) throw fail("bad-uint");
    return v.toString(16).padStart(64, "0");
  }

  function hexAddr(a) {
    var h = String(a || "").toLowerCase().replace(/^0x/, "");
    if (!/^[0-9a-f]{40}$/.test(h)) throw fail("bad-address");
    return h.padStart(64, "0");
  }

  function word(hex, index) {
    var h = String(hex || "").replace(/^0x/, "");
    var slice = h.slice(index * 64, index * 64 + 64);
    if (!slice) return 0n;
    return BigInt("0x" + slice);
  }

  function decodeString(hex, slot) {
    var h = String(hex || "").replace(/^0x/, "");
    var offset = Number(word(hex, slot));
    var start = offset * 2;
    if (!h.slice(start, start + 64)) return "";
    var len = Number(BigInt("0x" + h.slice(start, start + 64)));
    var data = h.slice(start + 64, start + 64 + len * 2);
    var bytes = new Uint8Array(len);
    for (var i = 0; i < len; i++) bytes[i] = parseInt(data.slice(i * 2, i * 2 + 2) || "0", 16);
    try { return new TextDecoder().decode(bytes); } catch (e) { return ""; }
  }

  function formatUnits(value, decimals, maxDp) {
    var v = BigInt(value);
    var neg = v < 0n;
    if (neg) v = -v;
    var base = 10n ** BigInt(decimals);
    var whole = v / base;
    var frac = (v % base).toString().padStart(decimals, "0").slice(0, maxDp).replace(/0+$/, "");
    return (neg ? "-" : "") + whole.toString() + (frac ? "." + frac : "");
  }

  function formatInt(n) {
    return BigInt(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }

  function shortAddr(a) {
    var s = String(a || "");
    if (s.length < 12) return s;
    return s.slice(0, 6) + "…" + s.slice(-4);
  }

  function isAddr(a) {
    return /^0x[0-9a-fA-F]{40}$/.test(String(a || "").trim());
  }

  function addrFromWord(raw) {
    var hex = String(raw || "").replace(/^0x/, "");
    if (hex.length < 40) return "";
    var body = hex.slice(-40);
    if (/^0+$/.test(body)) return "";
    return "0x" + body.toLowerCase();
  }

  async function rpc(urls, method, params) {
    var last = fail("rpc");
    for (var i = 0; i < urls.length; i++) {
      try {
        var res = await fetch(urls[i], {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: method, params: params }),
          signal: AbortSignal.timeout(8000)
        });
        if (!res.ok) { last = fail("rpc-" + res.status); continue; }
        var data = await res.json();
        if (data.error) { last = fail(data.error.message || "rpc-error"); continue; }
        return data.result;
      } catch (e) {
        last = e;
      }
    }
    throw last;
  }

  function callRpc(method, params) { return rpc(CALL_RPCS, method, params); }
  function logRpc(method, params) { return rpc(LOG_RPCS.concat(CALL_RPCS), method, params); }

  async function ethCall(to, data, from) {
    var tx = { to: to, data: data };
    if (from) tx.from = from;
    var out = await callRpc("eth_call", [tx, "latest"]);
    return out || "0x";
  }

  async function callUint(to, sel, arg) {
    var data = sel;
    if (arg !== undefined && arg !== null) {
      data += (typeof arg === "string" && String(arg).indexOf("0x") === 0) ? hexAddr(arg) : hexUint(arg);
    }
    return word(await ethCall(to, data), 0);
  }

  async function tryUint(to, sel, arg) {
    try { return await callUint(to, sel, arg); } catch (e) { return null; }
  }

  async function readBlockHead() {
    var blockHex = await callRpc("eth_blockNumber", []);
    var block = await callRpc("eth_getBlockByNumber", [blockHex, false]);
    return { blockHex: blockHex, now: BigInt(block.timestamp) };
  }

  async function readBoard() {
    var row = await Promise.all([
      readBlockHead(),
      callUint(ADDR.sale, SEL.sold),
      callUint(ADDR.sale, SEL.startTime),
      callUint(ADDR.sale, SEL.opened),
      callUint(ADDR.sale, SEL.openedAt),
      callUint(ADDR.sale, SEL.currentTier),
      callUint(ADDR.sale, SEL.priceUsd),
      callUint(ADDR.sale, SEL.lastMintTime),
      callUint(ADDR.flood, SEL.started),
      callUint(ADDR.nft, SEL.totalMinted),
      callUint(ADDR.nft, SEL.aliveCount),
      callUint(ADDR.shop, SEL.shopPrice),
      callUint(ADDR.shop, SEL.basePrice),
      callUint(ADDR.pot, SEL.landed),
      callUint(ADDR.pot, SEL.survivorCount),
      callUint(ADDR.pot, SEL.sharePerTicket),
      tryUint(ADDR.sale, SEL.pair),
      tryUint(ADDR.ark, SEL.officialPair)
    ]);
    var head = row[0];
    var now = head.now;
    var sold = row[1];
    var startTime = row[2];
    var opened = row[3] !== 0n;
    var openedAt = row[4];
    var tier = row[5];
    var priceUsd = row[6];
    var lastMintTime = row[7];
    var floodStarted = row[8] !== 0n;
    var totalMinted = row[9];
    var aliveCount = row[10];
    var shopPrice = row[11];
    var basePrice = row[12];
    var landed = row[13] !== 0n;
    var survivors = row[14];
    var share = row[15];
    var pair = row[16];
    var officialPair = row[17];
    var dayIndex = null;
    var day = null;
    if (floodStarted) {
      dayIndex = await tryUint(ADDR.flood, SEL.currentDayIndex);
      if (dayIndex && dayIndex > 0n) {
        try {
          var raw = await ethCall(ADDR.flood, SEL.dayState + hexUint(dayIndex));
          day = {
            commitBlock: word(raw, 0),
            settled: word(raw, 1) !== 0n,
            water: word(raw, 2),
            sunk: word(raw, 3)
          };
        } catch (e) { day = null; }
      }
    }
    var saleStarted = startTime !== 0n && now >= startTime;
    var mintOpen = saleStarted && sold < 10000n;
    var canOpen = sold >= 3000n && !opened;
    var canStart = opened && !floodStarted;
    var refundWindow = 7n * 24n * 60n * 60n;
    var refundOpensAt = startTime === 0n ? 0n : startTime + refundWindow;
    var refundsOpen = startTime !== 0n && !opened && now >= refundOpensAt;
    return {
      block: BigInt(head.blockHex),
      now: now,
      sold: sold,
      startTime: startTime,
      opened: opened,
      openedAt: openedAt,
      tier: tier,
      priceUsd: priceUsd,
      lastMintTime: lastMintTime,
      floodStarted: floodStarted,
      dayIndex: dayIndex,
      day: day,
      totalMinted: totalMinted,
      aliveCount: aliveCount,
      shopPrice: shopPrice,
      basePrice: basePrice,
      landed: landed,
      survivors: survivors,
      share: share,
      pair: pair,
      officialPair: officialPair,
      saleStarted: saleStarted,
      mintOpen: mintOpen,
      canOpen: canOpen,
      canStart: canStart,
      refundOpensAt: refundOpensAt,
      refundsOpen: refundsOpen
    };
  }

  async function quoteMint(count) {
    var n = BigInt(count);
    if (n < 1n || n > 10n) throw fail("bad-count");
    var raw = await ethCall(ADDR.sale, SEL.quoteMint + hexUint(n));
    return { bnbDue: word(raw, 0), usdTotal: word(raw, 1), count: n };
  }

  async function verifyAgent(addr) {
    var raw = await ethCall(ADDR.verifier, SEL.verify + hexAddr(addr));
    var ok = word(raw, 0) !== 0n;
    var handle = "";
    try { handle = decodeString(raw, 1); } catch (e) { handle = ""; }
    if (!handle) {
      try {
        var hraw = await ethCall(ADDR.registry, SEL.handleOf + hexAddr(addr));
        handle = decodeString(hraw, 0);
      } catch (e2) { handle = ""; }
    }
    return { ok: ok && !!handle, handle: handle };
  }

  async function readTicketOn(nft, sale, id) {
    var tokenId = BigInt(id);
    var ownerRaw;
    try {
      ownerRaw = await ethCall(nft, SEL.ownerOf + hexUint(tokenId));
    } catch (e) {
      return null;
    }
    var owner = addrFromWord(ownerRaw);
    if (!owner) return null;
    var cabin = await callUint(nft, SEL.cabinOf, tokenId);
    var alive = (await callUint(nft, SEL.isAlive, tokenId)) !== 0n;
    var pending = 0n;
    try { pending = await callUint(nft, SEL.pendingArk, tokenId); } catch (e) { pending = 0n; }
    var commitBlock = 0n;
    try {
      var info = await ethCall(nft, SEL.tickets + hexUint(tokenId));
      commitBlock = word(info, 4);
    } catch (e2) { commitBlock = 0n; }
    var payer = "";
    var payerKnown = true;
    try {
      payer = addrFromWord(await ethCall(sale, SEL.payer + hexUint(tokenId)));
    } catch (e3) {
      payer = "";
      payerKnown = false;
    }
    var paidBnb = null;
    try { paidBnb = await callUint(sale, SEL.paidBnb, tokenId); } catch (e4) { paidBnb = null; }
    var yieldClaimed = false;
    try { yieldClaimed = (await callUint(nft, SEL.yieldClaimed, tokenId)) !== 0n; } catch (e5) { yieldClaimed = false; }
    var c = Number(cabin);
    var sunk = !alive || c === 4;
    var unsettled = !sunk && (c === 0);
    var rate = sunk ? 0 : (unsettled ? null : (CABIN_RATE[c] || 0));
    return {
      id: tokenId,
      owner: owner,
      cabin: c,
      alive: alive,
      sunk: sunk,
      unsettled: unsettled,
      rate: rate,
      pendingArk: pending,
      commitBlock: commitBlock,
      payer: payer,
      payerKnown: payerKnown,
      paidBnb: paidBnb,
      yieldClaimed: yieldClaimed,
      legacy: false
    };
  }

  async function readTicket(id) {
    var primary = await readTicketOn(ADDR.nft, ADDR.sale, id);
    if (primary) return primary;
    var old = await readTicketOn(ADDR.legacyNft, ADDR.legacySale, id);
    if (old) old.legacy = true;
    return old;
  }

  async function ticketsOn(nft, sale, owner, includePayer) {
    if (!isAddr(owner)) throw fail("bad-address");
    var target = owner.toLowerCase();
    var minted = await callUint(nft, SEL.totalMinted);
    var balance = await callUint(nft, SEL.balanceOf, owner);
    var rows = [];
    if (minted === 0n || (balance === 0n && !includePayer)) {
      return { balance: balance, minted: minted, tickets: rows };
    }
    var limit = minted > 800n ? 800n : minted;
    var ids = [];
    for (var i = 1n; i <= limit; i++) ids.push(i);
    var owners = await mapPool(ids, 12, async function (id) {
      try {
        return addrFromWord(await ethCall(nft, SEL.ownerOf + hexUint(id)));
      } catch (e) { return ""; }
    });
    var mine = [];
    owners.forEach(function (who, idx) { if (who === target) mine.push(ids[idx]); });
    if (includePayer) {
      var payers = await mapPool(ids, 12, async function (id) {
        try {
          return addrFromWord(await ethCall(sale, SEL.payer + hexUint(id)));
        } catch (e) { return ""; }
      });
      payers.forEach(function (who, idx) {
        if (who === target && mine.indexOf(ids[idx]) === -1) mine.push(ids[idx]);
      });
    }
    rows = await mapPool(mine, 6, function (id) { return readTicketOn(nft, sale, id); });
    return {
      balance: balance,
      minted: minted,
      truncated: minted > limit,
      tickets: rows.filter(Boolean)
    };
  }

  async function ticketsOf(owner, opts) {
    var primary = await ticketsOn(ADDR.nft, ADDR.sale, owner, false);
    if (!(opts && opts.includePayer)) return primary;
    var old = await ticketsOn(ADDR.legacyNft, ADDR.legacySale, owner, true);
    old.tickets.forEach(function (row) { row.legacy = true; });
    return {
      balance: primary.balance,
      minted: primary.minted,
      truncated: !!(primary.truncated || old.truncated),
      tickets: primary.tickets.concat(old.tickets),
      legacyBalance: old.balance,
      legacyMinted: old.minted
    };
  }

  async function readLegacyRefund() {
    var head = await readBlockHead();
    var now = head.now;
    var row = await Promise.all([
      callUint(ADDR.legacySale, SEL.opened),
      callUint(ADDR.legacySale, SEL.refunding),
      callUint(ADDR.legacySale, SEL.startTime),
      callUint(ADDR.legacySale, SEL.sold)
    ]);
    var opened = row[0] !== 0n;
    var refunding = row[1] !== 0n;
    var startTime = row[2];
    var sold = row[3];
    var refundWindow = 7n * 24n * 60n * 60n;
    var opensAt = startTime === 0n ? 0n : startTime + refundWindow;
    var refundsClosed = opened || sold >= 3000n;
    var canEnableRefunds = !refundsClosed && !refunding && startTime !== 0n && now >= opensAt;
    return {
      now: now,
      opened: opened,
      refunding: refunding,
      startTime: startTime,
      sold: sold,
      opensAt: opensAt,
      refundsClosed: refundsClosed,
      canEnableRefunds: canEnableRefunds
    };
  }

  async function sandbagFor(id, dayIndex) {
    if (!dayIndex) return false;
    try {
      var v = await callUint(ADDR.shop, SEL.protectedUntil + hexUint(id) + hexUint(dayIndex));
      return v !== 0n;
    } catch (e) { return false; }
  }

  async function mapPool(items, limit, fn) {
    var out = new Array(items.length);
    var cursor = 0;
    async function worker() {
      while (cursor < items.length) {
        var idx = cursor++;
        out[idx] = await fn(items[idx], idx);
      }
    }
    var n = Math.min(limit, items.length);
    var jobs = [];
    for (var i = 0; i < n; i++) jobs.push(worker());
    await Promise.all(jobs);
    return out;
  }

  function topicWord(hex) {
    if (!hex || hex === "0x") return null;
    return BigInt(hex);
  }

  async function recentFeed() {
    var latest = Number(BigInt(await callRpc("eth_blockNumber", [])));
    var cursor = latest;
    var logs = [];
    var guard = 0;
    while (cursor > LOG_FROM && logs.length < 40 && guard < 4) {
      var from = Math.max(LOG_FROM, cursor - 45000);
      try {
        var batch = await logRpc("eth_getLogs", [{
          address: [ADDR.sale, ADDR.nft, ADDR.flood, ADDR.shop, ADDR.pot, ADDR.ark],
          fromBlock: "0x" + from.toString(16),
          toBlock: "0x" + cursor.toString(16)
        }]);
        if (Array.isArray(batch)) logs = logs.concat(batch);
      } catch (e) {
        if (guard === 0) throw e;
        break;
      }
      if (from === LOG_FROM) break;
      cursor = from - 1;
      guard++;
    }
    logs.sort(function (a, b) { return Number(BigInt(b.blockNumber) - BigInt(a.blockNumber)); });
    var player = [];
    var wires = {};
    logs.forEach(function (lg) {
      var kind = PLAYER_TOPIC[(lg.topics && lg.topics[0] || "").toLowerCase()];
      var block = Number(BigInt(lg.blockNumber));
      if (!kind) {
        if (!wires[block]) wires[block] = { kind: "wire", tx: lg.transactionHash, block: block, n: 0 };
        wires[block].n += 1;
        return;
      }
      var id = lg.topics && lg.topics.length > 1 ? topicWord(lg.topics[1]) : null;
      if (kind === "minted" && lg.topics && lg.topics.length > 2) id = topicWord(lg.topics[2]);
      player.push({ kind: kind, tx: lg.transactionHash, block: block, id: id });
    });
    var items = player.slice(0, 12);
    Object.keys(wires).forEach(function (tx) { items.push(wires[tx]); });
    items.sort(function (a, b) { return b.block - a.block; });
    var times = {};
    var unique = [];
    items.forEach(function (item) {
      if (unique.indexOf(item.block) === -1) unique.push(item.block);
    });
    await mapPool(unique.slice(0, 8), 4, async function (bn) {
      try {
        var b = await callRpc("eth_getBlockByNumber", ["0x" + bn.toString(16), false]);
        times[bn] = Number(BigInt(b.timestamp));
      } catch (e) { times[bn] = 0; }
    });
    return items.slice(0, 10).map(function (item) {
      item.time = times[item.block] || 0;
      return item;
    });
  }

  function isZeroAddr(a) {
    var h = String(a || "").toLowerCase().replace(/^0x/, "");
    return !/^[0-9a-f]{40}$/.test(h) || /^0+$/.test(h);
  }

  function parseUnits(text, decimals) {
    var s = String(text || "").trim();
    if (!/^\d+(\.\d+)?$/.test(s)) throw fail("bad-amount");
    var parts = s.split(".");
    var fracSrc = parts[1] || "";
    if (fracSrc.length > decimals) throw fail("bad-amount");
    var whole = parts[0].replace(/^0+(?=\d)/, "") || "0";
    var frac = fracSrc.padEnd(decimals, "0");
    var base = 10n ** BigInt(decimals);
    return BigInt(whole) * base + (frac ? BigInt(frac) : 0n);
  }

  function addrAt(hex, index) {
    var h = String(hex || "").replace(/^0x/, "");
    var slice = h.slice(index * 64, index * 64 + 64);
    if (slice.length < 64) return "";
    var body = slice.slice(24).toLowerCase();
    if (!/^[0-9a-f]{40}$/.test(body) || /^0+$/.test(body)) return "";
    return "0x" + body;
  }

  function decodeUintArray(hex) {
    var h = String(hex || "").replace(/^0x/, "");
    if (h.length < 128) return [];
    var offset = Number(BigInt("0x" + h.slice(0, 64)));
    var start = offset * 2;
    if (h.length < start + 64) return [];
    var len = Number(BigInt("0x" + h.slice(start, start + 64)));
    if (!Number.isFinite(len) || len < 0) return [];
    var out = [];
    var cap = Math.min(len, 40);
    for (var i = 0; i < cap; i++) {
      var w = h.slice(start + 64 + i * 64, start + 64 + i * 64 + 64);
      if (w.length < 64) break;
      out.push(BigInt("0x" + w));
    }
    out.truncated = len > cap;
    return out;
  }

  async function readListingBook(market) {
    if (isZeroAddr(market)) return { deployed: false, feeBps: 250n, rows: [], truncated: false };
    var feeBps = await callUint(market, SEL.marketFeeBps);
    var ids = decodeUintArray(await ethCall(market, SEL.activeListingIds));
    var truncated = !!ids.truncated;
    var rows = await mapPool(ids, 6, async function (id) {
      var listingRaw = await ethCall(market, SEL.listings + hexUint(id));
      var info = await ethCall(ADDR.nft, SEL.tickets + hexUint(id));
      var buyable = 0n;
      try { buyable = await callUint(market, SEL.buyable, id); } catch (e) { buyable = 0n; }
      return {
        id: id,
        seller: addrAt(listingRaw, 0),
        price: word(listingRaw, 1),
        cabin: Number(word(info, 0)),
        mintedAt: word(info, 2),
        commit: word(info, 4),
        buyable: buyable !== 0n
      };
    });
    return { deployed: true, feeBps: feeBps, rows: rows.filter(Boolean), truncated: truncated };
  }

  async function readActiveBidIds(market) {
    var pageSize = 40;
    var offset = 0;
    var all = [];
    var guard = 0;
    while (guard < 50) {
      var raw = await ethCall(market, SEL.activeBidIdsPage + hexUint(offset) + hexUint(pageSize));
      var ids = decodeUintArray(raw);
      for (var i = 0; i < ids.length; i++) all.push(ids[i]);
      if (ids.length < pageSize) break;
      offset += pageSize;
      guard++;
    }
    all.truncated = guard >= 50;
    return all;
  }

  async function readBidBook(market) {
    if (isZeroAddr(market)) return { deployed: false, feeBps: 250n, rows: [], truncated: false };
    var feeBps = await callUint(market, SEL.marketFeeBps);
    var ids = await readActiveBidIds(market);
    var truncated = !!ids.truncated;
    var rows = await mapPool(ids, 6, async function (id) {
      var raw = await ethCall(market, SEL.bidOf + hexUint(id));
      return {
        id: id,
        buyer: addrAt(raw, 0),
        unitPrice: word(raw, 1),
        qtyLeft: word(raw, 2),
        kind: Number(word(raw, 3)),
        param: word(raw, 4),
        expires: word(raw, 5),
        open: word(raw, 6) !== 0n
      };
    });
    return { deployed: true, feeBps: feeBps, rows: rows.filter(Boolean), truncated: truncated };
  }

  async function readListing(market, id) {
    var raw = await ethCall(market, SEL.listings + hexUint(id));
    return { seller: addrAt(raw, 0), price: word(raw, 1) };
  }

  async function getApproved(id) {
    var raw = await ethCall(ADDR.nft, SEL.getApproved + hexUint(id));
    return addrAt(raw, 0);
  }

  async function isApprovedForAll(owner, operator) {
    var raw = await ethCall(ADDR.nft, SEL.isApprovedForAll + hexAddr(owner) + hexAddr(operator));
    return word(raw, 0) !== 0n;
  }

  async function arkAllowance(owner, spender) {
    var raw = await ethCall(ADDR.ark, SEL.allowance + hexAddr(owner) + hexAddr(spender));
    return word(raw, 0);
  }

  function sendApproveNft(spender, id) {
    return sendTx(ADDR.nft, SEL.approve + hexAddr(spender) + hexUint(id), 0);
  }

  function sendApproveArk(spender, amount) {
    return sendTx(ADDR.ark, SEL.approve + hexAddr(spender) + hexUint(amount), 0);
  }

  function sendList(market, id, priceWei) {
    if (isZeroAddr(market)) throw fail("market-not-deployed");
    return sendTx(market, SEL.marketList + hexUint(id) + hexUint(priceWei), 0);
  }

  async function sendBuyBnb(id) {
    if (isZeroAddr(ADDR.marketBnb)) throw fail("market-not-deployed");
    var row = await readListing(ADDR.marketBnb, id);
    if (row.price === 0n) throw fail("unlisted");
    return sendTx(ADDR.marketBnb, SEL.marketBuy + hexUint(id), row.price);
  }

  function sendBuyArk(id) {
    if (isZeroAddr(ADDR.marketArk)) throw fail("market-not-deployed");
    return sendTx(ADDR.marketArk, SEL.marketBuy + hexUint(id), 0);
  }

  function sendCancelListing(market, id) {
    if (isZeroAddr(market)) throw fail("market-not-deployed");
    return sendTx(market, SEL.marketCancel + hexUint(id), 0);
  }

  function sendCleanListing(market, id) {
    if (isZeroAddr(market)) throw fail("market-not-deployed");
    return sendTx(market, SEL.cleanListing + hexUint(id), 0);
  }

  function sendPostBid(kind, param, unitPrice, qty, duration) {
    if (isZeroAddr(ADDR.marketBid)) throw fail("market-not-deployed");
    var total = BigInt(unitPrice) * BigInt(qty);
    var data = SEL.postBid + hexUint(kind) + hexUint(param) + hexUint(unitPrice) + hexUint(qty) + hexUint(duration);
    return sendTx(ADDR.marketBid, data, total);
  }

  function sendAcceptBid(bidId, tokenId) {
    if (isZeroAddr(ADDR.marketBid)) throw fail("market-not-deployed");
    return sendTx(ADDR.marketBid, SEL.acceptBid + hexUint(bidId) + hexUint(tokenId), 0);
  }

  function sendCancelBid(bidId) {
    if (isZeroAddr(ADDR.marketBid)) throw fail("market-not-deployed");
    return sendTx(ADDR.marketBid, SEL.cancelBid + hexUint(bidId), 0);
  }

  function sendRefundExpired(bidId) {
    if (isZeroAddr(ADDR.marketBid)) throw fail("market-not-deployed");
    return sendTx(ADDR.marketBid, SEL.refundExpired + hexUint(bidId), 0);
  }

  function provider() {
    return global.ethereum || null;
  }

  async function ensureChain() {
    var eth = provider();
    if (!eth) throw fail("no-wallet");
    var id = await eth.request({ method: "eth_chainId" });
    if (parseInt(id, 16) === CHAIN_ID) return;
    try {
      await eth.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x38" }] });
    } catch (e) {
      if (e && (e.code === 4902 || e.code === -32603)) {
        await eth.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: "0x38",
            chainName: "BNB Smart Chain",
            nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
            rpcUrls: ["https://bsc-dataseed.binance.org"],
            blockExplorerUrls: ["https://bscscan.com"]
          }]
        });
      } else {
        throw e;
      }
    }
  }

  async function connect() {
    var eth = provider();
    if (!eth) throw fail("no-wallet");
    var accounts = await eth.request({ method: "eth_requestAccounts" });
    await ensureChain();
    account = accounts && accounts[0] ? accounts[0] : "";
    watchers.forEach(function (fn) { fn(account); });
    return account;
  }

  function isSaleMint(to, data) {
    if (!to || data == null) return false;
    var dest = String(to).toLowerCase();
    if (dest !== ADDR.sale.toLowerCase() && dest !== ADDR.legacySale.toLowerCase()) return false;
    var body = String(data).toLowerCase();
    if (body.slice(0, 2) !== "0x") body = "0x" + body;
    return body.indexOf(SEL.mint.toLowerCase()) === 0;
  }

  async function sendTx(to, data, value) {
    if (isSaleMint(to, data)) throw fail("mint-paused");
    var eth = provider();
    if (!eth) throw fail("no-wallet");
    await ensureChain();
    var accounts = await eth.request({ method: "eth_requestAccounts" });
    var from = accounts[0];
    account = from;
    var tx = { from: from, to: to, data: data };
    if (value && BigInt(value) > 0n) tx.value = "0x" + BigInt(value).toString(16);
    try {
      await callRpc("eth_call", [tx, "latest"]);
    } catch (e) {
      var err = fail("revert");
      err.detail = e && e.message ? e.message : String(e);
      throw err;
    }
    var hash = await eth.request({ method: "eth_sendTransaction", params: [tx] });
    return hash;
  }

  async function waitReceipt(hash) {
    for (var i = 0; i < 24; i++) {
      var rec = await callRpc("eth_getTransactionReceipt", [hash]);
      if (rec) return rec;
      await new Promise(function (r) { setTimeout(r, 1500); });
    }
    return null;
  }

  async function sendMint() {
    throw fail("mint-paused");
  }

  async function sendOpenPool(board) {
    if (!board || !board.canOpen) throw fail("open-not-ready");
    return sendTx(ADDR.sale, SEL.openPool, 0);
  }

  async function sendStartFlood(board) {
    if (!board || !board.canStart) throw fail("start-not-ready");
    return sendTx(ADDR.flood, SEL.start, 0);
  }

  async function sendEnableRefunds() {
    var snap = await readLegacyRefund();
    if (!snap.canEnableRefunds) throw fail("refund-not-ready");
    return sendTx(ADDR.legacySale, SEL.enableRefunds, 0);
  }

  function sendRefund(id) {
    return sendTx(ADDR.legacySale, SEL.refund + hexUint(id), 0);
  }

  function sendRefundNew(id) {
    return sendTx(ADDR.sale, SEL.refund + hexUint(id), 0);
  }

  async function sendRequestCabin(id) {
    return sendTx(ADDR.nft, SEL.requestCabin + hexUint(id), 0);
  }

  async function sendSettleCabin(id) {
    return sendTx(ADDR.nft, SEL.settleCabin + hexUint(id), 0);
  }

  async function sendClaim(id) {
    return sendTx(ADDR.nft, SEL.claim + hexUint(id), 0);
  }

  async function sendClaimShare(id, board) {
    if (!board || !board.landed) throw fail("pot-not-landed");
    return sendTx(ADDR.pot, SEL.claimShare + hexUint(id), 0);
  }

  async function sendCommit(day, board) {
    if (!board || !board.floodStarted) throw fail("flood-not-started");
    return sendTx(ADDR.flood, SEL.commit + hexUint(day), 0);
  }

  async function sendSettleBatch(day, maxCount, board) {
    if (!board || !board.floodStarted) throw fail("flood-not-started");
    var n = BigInt(maxCount || 400);
    if (n < 1n) n = 1n;
    if (n > 400n) n = 400n;
    return sendTx(ADDR.flood, SEL.settleBatch + hexUint(day) + hexUint(n), 0);
  }

  async function sendLandfall(board) {
    if (!board || !board.floodStarted) throw fail("flood-not-started");
    return sendTx(ADDR.flood, SEL.landfall, 0);
  }

  async function sendBuyBag(count, board) {
    if (!board || !board.opened) throw fail("pool-not-open");
    return sendTx(ADDR.shop, SEL.buy + hexUint(count || 1), 0);
  }

  async function sendApplyBag(id, day, board) {
    if (!board || !board.floodStarted) throw fail("flood-not-started");
    return sendTx(ADDR.shop, SEL.applyBag + hexUint(id) + hexUint(day), 0);
  }

  function onWallet(fn) { watchers.push(fn); }

  function bindProvider() {
    var eth = provider();
    if (!eth || !eth.on) return;
    eth.on("accountsChanged", function (accounts) {
      account = accounts && accounts[0] ? accounts[0] : "";
      watchers.forEach(function (fn) { fn(account); });
    });
    eth.on("chainChanged", function () { global.location.reload(); });
  }

  bindProvider();

  global.ArkChain = {
    CHAIN_ID: CHAIN_ID,
    MINT_PAUSED: true,
    ADDR: ADDR,
    CABIN_RATE: CABIN_RATE,
    formatUnits: formatUnits,
    formatInt: formatInt,
    shortAddr: shortAddr,
    isAddr: isAddr,
    isZeroAddr: isZeroAddr,
    parseUnits: parseUnits,
    readBoard: readBoard,
    readLegacyRefund: readLegacyRefund,
    readListingBook: readListingBook,
    readBidBook: readBidBook,
    readListing: readListing,
    getApproved: getApproved,
    isApprovedForAll: isApprovedForAll,
    arkAllowance: arkAllowance,
    quoteMint: quoteMint,
    verifyAgent: verifyAgent,
    readTicket: readTicket,
    ticketsOf: ticketsOf,
    sandbagFor: sandbagFor,
    recentFeed: recentFeed,
    connect: connect,
    account: function () { return account; },
    sendMint: sendMint,
    sendOpenPool: sendOpenPool,
    sendStartFlood: sendStartFlood,
    sendEnableRefunds: sendEnableRefunds,
    sendRefund: sendRefund,
    sendRefundNew: sendRefundNew,
    sendRequestCabin: sendRequestCabin,
    sendSettleCabin: sendSettleCabin,
    sendClaim: sendClaim,
    sendClaimShare: sendClaimShare,
    sendCommit: sendCommit,
    sendSettleBatch: sendSettleBatch,
    sendLandfall: sendLandfall,
    sendBuyBag: sendBuyBag,
    sendApplyBag: sendApplyBag,
    sendApproveNft: sendApproveNft,
    sendApproveArk: sendApproveArk,
    sendList: sendList,
    sendBuyBnb: sendBuyBnb,
    sendBuyArk: sendBuyArk,
    sendCancelListing: sendCancelListing,
    sendCleanListing: sendCleanListing,
    sendPostBid: sendPostBid,
    sendAcceptBid: sendAcceptBid,
    sendCancelBid: sendCancelBid,
    sendRefundExpired: sendRefundExpired,
    waitReceipt: waitReceipt,
    onWallet: onWallet
  };
})(window);
