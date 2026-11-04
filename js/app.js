(function () {
  var C = window.ArkChain;
  var lang = document.documentElement.dataset.lang === "en" ? "en" : "zh";
  var qty = 1;
  var board = null;
  var quote = null;
  var ticketFilter = "all";
  var ticketRows = [];
  var lookedUp = "";
  var account = "";

  function zh() { return lang !== "en"; }
  function $(id) { return document.getElementById(id); }

  function setBi(el, zhText, enText) {
    if (!el) return;
    var z = el.querySelector(".t-zh");
    var e = el.querySelector(".t-en");
    if (!z || !e) {
      el.textContent = zh() ? zhText : enText;
      return;
    }
    z.textContent = zhText;
    e.textContent = enText;
  }

  function say(el, zhText, enText) {
    if (!el) return;
    el.textContent = zh() ? zhText : enText;
  }

  function esc(s) {
    return String(s == null ? "" : s);
  }

  function bnbText(value) {
    if (value == null) return "…";
    return C.formatUnits(value, 18, 6) + " BNB";
  }

  function usdText(value) {
    if (value == null) return "…";
    return C.formatUnits(value, 18, 2);
  }

  function ago(ts) {
    if (!ts) return zh() ? "链上" : "On-chain";
    var sec = Math.max(0, Math.floor(Date.now() / 1000 - ts));
    if (sec < 90) return zh() ? "刚刚" : "Just now";
    if (sec < 3600) return zh() ? (Math.floor(sec / 60) + " 分钟前") : (Math.floor(sec / 60) + " min ago");
    if (sec < 86400) return zh() ? (Math.floor(sec / 3600) + " 小时前") : (Math.floor(sec / 3600) + " hr ago");
    return zh() ? (Math.floor(sec / 86400) + " 天前") : (Math.floor(sec / 86400) + " d ago");
  }

  function txLink(hash) {
    var a = document.createElement("a");
    a.href = "https://bscscan.com/tx/" + hash;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    a.textContent = C.shortAddr(hash);
    return a;
  }

  function saleLabel() {
    if (!board) return { zh: "正在读取", en: "Reading" };
    if (!board.saleStarted) return { zh: "正式未开售", en: "Sale not started" };
    if (board.refunding) return { zh: "退款已开启", en: "Refunds are open" };
    if (board.sold >= 10000n) return { zh: "已售罄", en: "Sold out" };
    return { zh: "发售中", en: "Sale is live" };
  }

  function mintBrief() {
    var price = board ? usdText(board.priceUsd) : "2";
    var due = quote ? bnbText(quote.bnbDue) : (zh() ? "读取 quoteMint" : "read quoteMint");
    var state = !board || !board.saleStarted
      ? (zh() ? "正式未开售。startTime 仍为 0 时不要发送 mint。" : "Sale not started. Do not send mint while startTime is 0.")
      : (board.mintOpen
        ? (zh() ? "发售已开始，可以发送 mint。" : "The sale has started. mint can be sent.")
        : (zh() ? "发售状态不允许铸造。" : "Mint is not open in the current sale state."));
    if (zh()) {
      return [
        "ARK100 铸造说明",
        "链：BNB Smart Chain（chainId 56）",
        "状态：" + state,
        "",
        "门槛：必须持有 Agent ID，handle 非空。",
        "注册表：" + C.ADDR.registry,
        "校验：" + C.ADDR.verifier,
        "",
        "数量：" + qty,
        "链上标价：$" + price + " / 张（含 5 分钟回落）。",
        "quoteMint(" + qty + ") 的 bnbDue：" + due,
        "",
        "1. 读取 ArkSale.quoteMint(" + qty + ") → (bnbDue, usdTotal)。",
        "   ArkSale: " + C.ADDR.sale,
        "2. 把报价给用户看，等明确确认。",
        "3. 仅在发售已开始时发送 ArkSale.mint(" + qty + ")，value = bnbDue。",
        "",
        "TicketNFT: " + C.ADDR.nft,
        "ARK: " + C.ADDR.ark,
        "奖池: " + C.ADDR.pot,
        "团队：" + C.ADDR.team,
        "这次调用不选择舱位。之后 requestCabin，再 settleCabin。",
        "经济舱 70% = 100 ARK/天，商务舱 25% = 200，船长舱 5% = 600。沉船日产为 0。"
      ].join("\n");
    }
    return [
      "ARK100 mint brief",
      "Chain: BNB Smart Chain (chainId 56)",
      "Status: " + state,
      "",
      "Gate: Agent ID with a non-empty handle.",
      "Registry: " + C.ADDR.registry,
      "Verifier: " + C.ADDR.verifier,
      "",
      "Qty: " + qty,
      "On-chain list price: $" + price + " / ticket (includes the 5-minute decay).",
      "quoteMint(" + qty + ") bnbDue: " + due,
      "",
      "1. Read ArkSale.quoteMint(" + qty + ") → (bnbDue, usdTotal).",
      "   ArkSale: " + C.ADDR.sale,
      "2. Show the quote. Wait for an explicit yes.",
      "3. Send ArkSale.mint(" + qty + ") with value = bnbDue only after the sale has started.",
      "",
      "TicketNFT: " + C.ADDR.nft,
      "ARK: " + C.ADDR.ark,
      "Pot: " + C.ADDR.pot,
      "Team: " + C.ADDR.team,
      "This call does not choose a cabin. Then requestCabin, then settleCabin.",
      "Economy 70% = 100 ARK/day, Business 25% = 200, Captain 5% = 600. Sunk tickets earn 0."
    ].join("\n");
  }

  function renderQuote() {
    var price = board ? Number(C.formatUnits(board.priceUsd, 18, 0)) : 2;
    if (!price) price = 2;
    $("qQty").textContent = String(qty);
    $("qPrice").textContent = String(price);
    if (quote && quote.count === BigInt(qty)) {
      $("qUsd").textContent = usdText(quote.usdTotal);
      $("bnbDue").textContent = bnbText(quote.bnbDue);
    } else if (board) {
      $("qUsd").textContent = String(qty * price);
    }
    var cmd = $("cmd");
    if (cmd) cmd.textContent = mintBrief();
    document.querySelectorAll(".qty").forEach(function (btn) {
      btn.setAttribute("aria-pressed", Number(btn.getAttribute("data-qty")) === qty ? "true" : "false");
    });
    document.querySelectorAll(".rung").forEach(function (rung) {
      rung.classList.toggle("is-now", Number(rung.getAttribute("data-tier")) === price);
    });
  }

  function renderTide() {
    if (!board) return;
    var sold = Number(board.sold);
    var price = Number(C.formatUnits(board.priceUsd, 18, 0)) || 2;
    var pct = (sold / 10000) * 100;
    $("sold").textContent = C.formatInt(board.sold);
    $("price").textContent = String(price);
    var water = $("water");
    var floater = $("floater");
    var meter = $("meter");
    water.style.height = pct + "%";
    water.classList.toggle("is-empty", pct <= 0);
    floater.style.bottom = pct <= 0 ? "10px" : ("calc(" + Math.min(pct, 78) + "% - 18px)");
    meter.setAttribute("aria-valuenow", String(sold));
    var remain = Math.max(3000 - sold, 0);
    say($("gaugeReadout"), sold === 0 ? "水位 0 · 龙骨" : ("水位 " + C.formatInt(board.sold)), sold === 0 ? "Level 0 · keel" : ("Level " + C.formatInt(board.sold)));
    meter.setAttribute("aria-valuetext", (zh() ? (sold + " / 10000 已售。开池线 #3000。") : (sold + " of 10000 sold. Pool opens at 3000.")));
    if (board.opened) {
      say($("remainLine"), "池子已经打开。", "The pool is open.");
    } else if (remain === 0) {
      say($("remainLine"), "已售已到 #3000。若池子还没打开，任何人可以调用 openPool()。", "Sold has reached #3000. If the pool is still closed, anyone may call openPool().");
    } else {
      say($("remainLine"), "距开池还差 " + C.formatInt(remain) + " 张。$3 档含 #3000，开池落在这一档里面。", C.formatInt(remain) + " tickets still to the open line. #3000 sits inside the $3 tier.");
    }
  }

  function renderSale() {
    var label = saleLabel();
    setBi($("saleSeal"), label.zh, label.en);
    setBi($("statusSale"), label.zh, label.en);
    var mintBtn = $("mintBtn");
    if (!mintBtn) return;
    if (board && board.mintOpen) {
      mintBtn.disabled = false;
      setBi(mintBtn, "铸造 " + qty + " 张", "Mint " + qty);
    } else if (board && board.saleStarted && board.refunding) {
      mintBtn.disabled = true;
      setBi(mintBtn, "退款中，停止铸造", "Refunding, mint is closed");
    } else if (board && board.saleStarted) {
      mintBtn.disabled = true;
      setBi(mintBtn, "现在不能铸造", "Mint is closed");
    } else {
      mintBtn.disabled = true;
      setBi(mintBtn, "正式未开售", "Sale not started");
    }
  }

  function renderNight() {
    var count = $("nightCount");
    var hint = $("nightHint");
    if (!board) return;
    if (!board.floodStarted || !board.dayIndex) {
      setBi(count, "洪水未启动", "Flood not started");
      setBi(hint, "开池并 start() 之后才有第 1–100 晚", "Nights 1–100 begin after the pool opens and start()");
    } else {
      var n = board.dayIndex.toString();
      var settled = board.day && board.day.settled;
      setBi(count, "第 " + n + " / 100 晚", "Night " + n + " / 100");
      setBi(hint, settled ? "这一晚已结算" : "这一晚尚未结算", settled ? "This night is settled" : "This night is not settled yet");
    }
    if ($("arkNight")) {
      if (!board.floodStarted || !board.dayIndex) say($("arkNight"), "当前晚数：洪水未启动。", "Current night: the flood has not started.");
      else say($("arkNight"), "当前晚数：第 " + board.dayIndex.toString() + " 晚。", "Current night: " + board.dayIndex.toString() + ".");
    }
    var price = board.shopPrice != null ? C.formatUnits(board.shopPrice, 18, 4) : "…";
    var base = board.basePrice != null ? C.formatUnits(board.basePrice, 18, 2) : "50";
    var alive = board.aliveCount != null ? C.formatInt(board.aliveCount) : "0";
    say($("sandbagLive"),
      "沙袋店基准价 " + base + " ARK。当前链上 price() 为 " + price + " ARK（存活 " + alive + "）。人还多时大约 50 ARK 一袋，幸存者越少越贵。",
      "Sandbag base price is " + base + " ARK. On-chain price() is " + price + " ARK (alive " + alive + "). About 50 ARK a bag while many tickets survive; the price rises as fewer remain.");
  }

  function renderActions() {
    if (!board) return;
    var openCard = $("openPoolCard");
    var startCard = $("startFloodCard");
    var refundCard = $("refundCard");
    if (openCard) openCard.hidden = !board.canOpen;
    if (startCard) startCard.hidden = !board.canStart;
    if (refundCard) refundCard.hidden = !board.canEnableRefunds;
    var dayInput = $("floodDayInput");
    if (dayInput && board.dayIndex && !dayInput.value) dayInput.value = board.dayIndex.toString();
    var parts = [];
    parts.push(zh()
      ? ("已售 " + C.formatInt(board.sold) + " / 10,000。开池：" + (board.opened ? "已打开" : "未打开") + "。退款：" + (board.refunding ? "已开启" : "未开启") + "。洪水：" + (board.floodStarted ? "已启动" : "未启动") + "。")
      : (C.formatInt(board.sold) + " / 10,000 sold. Pool: " + (board.opened ? "open" : "closed") + ". Refunds: " + (board.refunding ? "on" : "off") + ". Flood: " + (board.floodStarted ? "started" : "not started") + "."));
    if (!board.saleStarted) parts.push(zh() ? "铸造正式未开售。" : "Minting is not open yet.");
    else if (board.mintOpen) parts.push(zh() ? "铸造已开放。" : "Minting is open.");
    say($("chainStatus"), parts.join(" "));
    var buy = $("buyBagBtn");
    if (buy) {
      buy.disabled = !board.opened;
      setBi(buy, board.opened ? "购买 1 个沙袋" : "开池后才能买沙袋", board.opened ? "Buy 1 sandbag" : "Sandbags open with the pool");
    }
  }

  function cabinBadge(row) {
    if (row.sunk) return { cls: "mute", zh: "已沉", en: "Sunk" };
    if (row.unsettled) return { cls: "wait", zh: "未抽舱", en: "Unsettled" };
    if (row.cabin === 1) return { cls: "eco", zh: "经济 70%", en: "Economy 70%" };
    if (row.cabin === 2) return { cls: "biz", zh: "商务 25%", en: "Business 25%" };
    if (row.cabin === 3) return { cls: "cap", zh: "船长 5%", en: "Captain 5%" };
    return { cls: "wait", zh: "未抽舱", en: "Unsettled" };
  }

  function renderTickets() {
    var body = $("ticketBody");
    if (!body) return;
    body.innerHTML = "";
    var visible = 0;
    var afloat = 0, pending = 0, sunk = 0, bags = 0, daily = 0;
    ticketRows.forEach(function (row) {
      var state = row.sunk ? "sunk" : (row.unsettled ? "pending" : "afloat");
      if (state === "afloat") { afloat++; if (row.rate) daily += row.rate; }
      if (state === "pending") pending++;
      if (state === "sunk") sunk++;
      if (row.sandbag) bags++;
      if (ticketFilter !== "all" && ticketFilter !== state) return;
      visible++;
      var tr = document.createElement("tr");
      tr.setAttribute("data-state", state);
      var badge = cabinBadge(row);
      var statusZh = state === "afloat" ? "在航" : (state === "pending" ? "待抽舱" : "已沉");
      var statusEn = state === "afloat" ? "Afloat" : (state === "pending" ? "Pending" : "Sunk");
      var statusCls = state === "afloat" ? "ok" : (state === "sunk" ? "sunk" : "wait");
      var bagZh = row.sandbag ? "已堆沙袋" : (board && board.floodStarted ? "无沙袋" : "—");
      var bagEn = row.sandbag ? "Sandbagged" : (board && board.floodStarted ? "No sandbag" : "—");
      var rate = row.rate == null ? "—" : String(row.rate);
      tr.innerHTML =
        "<td>#" + row.id.toString() + "</td>" +
        "<td><span class=\"badge " + badge.cls + "\"><span class=\"t-zh\">" + badge.zh + "</span><span class=\"t-en\">" + badge.en + "</span></span></td>" +
        "<td><span class=\"badge " + statusCls + "\"><span class=\"t-zh\">" + statusZh + "</span><span class=\"t-en\">" + statusEn + "</span></span></td>" +
        "<td>" + rate + "</td>" +
        "<td><span class=\"t-zh\">" + bagZh + "</span><span class=\"t-en\">" + bagEn + "</span></td>" +
        "<td></td>";
      var cell = tr.lastChild;
      if (state === "pending") cell.appendChild(actionButton("request-cabin", row.id, "抽舱", "Draw cabin"));
      else if (state === "afloat") cell.appendChild(actionButton("apply-bag", row.id, "沙袋护住", "Apply sandbag"));
      else cell.appendChild(textSpan("无产出", "No yield"));
      body.appendChild(tr);
    });
    $("statAfloat").textContent = String(afloat);
    $("statPending").textContent = String(pending);
    $("statSunk").textContent = String(sunk);
    $("statBags").textContent = String(bags);
    say($("dailyLine"),
      lookedUp ? ("在航且已抽舱的日产合计 " + daily + " ARK。未抽舱还没有日产，已沉为 0。") : "连接钱包或输入地址后，这里显示链上日产。",
      lookedUp ? ("Afloat settled daily total " + daily + " ARK. Unsettled tickets have no rate yet. Sunk tickets earn 0.") : "Connect a wallet or paste an address to read on-chain daily ARK.");
    var empty = $("filterEmpty");
    if (empty) {
      empty.hidden = !(lookedUp && visible === 0);
      setBi(empty, "这个筛选下没有船票。", "No tickets in this filter.");
    }
  }

  function textSpan(zhText, enText) {
    var span = document.createElement("span");
    span.className = "muted";
    span.innerHTML = "<span class=\"t-zh\"></span><span class=\"t-en\"></span>";
    span.querySelector(".t-zh").textContent = zhText;
    span.querySelector(".t-en").textContent = enText;
    return span;
  }

  function actionButton(act, id, zhText, enText) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "ghost";
    btn.setAttribute("data-act", act);
    btn.setAttribute("data-id", id.toString());
    btn.innerHTML = "<span class=\"t-zh\"></span><span class=\"t-en\"></span>";
    btn.querySelector(".t-zh").textContent = zhText;
    btn.querySelector(".t-en").textContent = enText;
    return btn;
  }

  function feedLine(item) {
    var li = document.createElement("li");
    var time = document.createElement("time");
    time.textContent = ago(item.time);
    var div = document.createElement("div");
    var b = document.createElement("b");
    var labels = {
      minted: ["铸造", "Mint"],
      cabin: ["抽舱", "Cabin"],
      cabinAsk: ["请求抽舱", "Cabin request"],
      sunk: ["沉船", "Sunk"],
      flood: ["夜洪", "Flood"],
      sandbag: ["沙袋", "Sandbag"],
      pool: ["开池", "Pool"],
      sale: ["发售开始", "Sale started"],
      applied: ["沙袋生效", "Sandbag applied"],
      commit: ["夜洪提交", "Flood commit"],
      refund: ["退款", "Refund"],
      floodStart: ["洪水启动", "Flood started"],
      gift: ["赠送沙袋", "Sandbag gift"],
      wire: ["合约接线", "Contracts wired"]
    };
    var pair = labels[item.kind] || ["事件", "Event"];
    b.appendChild(textSpan(pair[0], pair[1]));
    div.appendChild(b);
    div.appendChild(document.createTextNode(" · "));
    var detail = "";
    if (item.kind === "wire") detail = zh() ? ("同一区块写入 " + item.n + " 条接线。") : (item.n + " wiring calls in the same block.");
    else if (item.id != null) detail = "#" + item.id.toString();
    else detail = zh() ? "已上链。" : "Confirmed on-chain.";
    div.appendChild(document.createTextNode(detail + " "));
    if (item.tx) div.appendChild(txLink(item.tx));
    li.appendChild(time);
    li.appendChild(div);
    return li;
  }

  function renderFeed(items) {
    var list = $("feedList");
    var empty = $("feedEmpty");
    if (!list) return;
    list.innerHTML = "";
    var shown = (items || []).filter(function (item) { return item.kind !== "wire" || item.n; });
    if (!shown.length) {
      if (empty) empty.hidden = false;
      return;
    }
    if (empty) empty.hidden = true;
    shown.forEach(function (item) { list.appendChild(feedLine(item)); });
  }

  function renderMarket() {
    say($("listingEmpty"), "链上挂单：0。船票发售只走 ArkSale。", "On-chain listings: 0. Tickets are sold only through ArkSale.");
    say($("bidEmpty"), "链上出价：0。", "On-chain bids: 0.");
  }

  function explain(code, detail) {
    var map = {
      "sale-not-started": ["正式未开售，没有发送交易。", "Sale not started. No transaction was sent."],
      "refunding": ["退款已开启，铸造已停止，没有发送交易。", "Refunds are on, so mint is closed. No transaction was sent."],
      "mint-closed": ["当前不能铸造，没有发送交易。", "Mint is closed. No transaction was sent."],
      "no-wallet": ["没有发现浏览器钱包。", "No browser wallet was found."],
      "open-not-ready": ["还不能开池：需要已售至少 3000、池子未开、且不在退款。没有发送交易。", "openPool is not ready: sold must be at least 3,000, the pool closed, and refunds off. No transaction was sent."],
      "start-not-ready": ["还不能启动洪水：需要池子已开且洪水未启动。没有发送交易。", "start() is not ready: the pool must be open and the flood not started. No transaction was sent."],
      "refund-not-ready": ["退款窗口还没到。没有发送交易。", "The refund window is not open. No transaction was sent."],
      "flood-not-started": ["洪水尚未启动，没有发送交易。", "The flood has not started. No transaction was sent."],
      "pool-not-open": ["开池之后才能买沙袋，没有发送交易。", "Sandbags can be bought after the pool opens. No transaction was sent."],
      "pot-not-landed": ["奖池尚未靠岸，没有发送交易。", "The pot has not landed. No transaction was sent."],
      "bad-id": ["请输入船票编号。", "Enter a ticket id."],
      "revert": ["合约拒绝了这笔调用，没有发出交易。", "The contract rejected the call. No transaction was sent."]
    };
    var pair = map[code] || ["操作没有完成。", "The action did not complete."];
    var text = zh() ? pair[0] : pair[1];
    if (code === "revert" && detail) text += " " + detail;
    return text;
  }

  function walletError(e) {
    if (e && (e.code === 4001 || e.code === "4001")) return zh() ? "已取消，没有发送交易。" : "Cancelled. No transaction was sent.";
    if (e && e.code) return explain(e.code, e.detail || e.message);
    return zh() ? "操作没有完成。" : "The action did not complete.";
  }

  async function track(hash, slot) {
    say(slot, "交易已提交，等待确认。", "Transaction submitted, waiting for confirmation.");
    if (slot) slot.appendChild(document.createTextNode(" "));
    if (slot) slot.appendChild(txLink(hash));
    var rec = await C.waitReceipt(hash);
    if (!rec) {
      say(slot, "交易已提交，确认还没返回。", "Submitted. The receipt is not back yet.");
      if (slot) { slot.appendChild(document.createTextNode(" ")); slot.appendChild(txLink(hash)); }
      return;
    }
    if (rec.status === "0x1") say(slot, "交易已确认。", "Transaction confirmed.");
    else say(slot, "交易失败。", "Transaction failed.");
    if (slot) { slot.appendChild(document.createTextNode(" ")); slot.appendChild(txLink(hash)); }
    refresh().catch(function () {});
  }

  async function refreshQuote() {
    try {
      quote = await C.quoteMint(qty);
    } catch (e) {
      quote = null;
      say($("bnbDue"), "报价暂时读不到", "Quote unavailable");
    }
    renderQuote();
  }

  async function refresh() {
    board = await C.readBoard();
    renderTide();
    renderSale();
    renderNight();
    renderActions();
    renderQuote();
    await refreshQuote();
    say($("statusRead"), "链上读取", "On-chain");
  }

  async function loadFeed() {
    try {
      var items = await C.recentFeed();
      renderFeed(items);
    } catch (e) {
      say($("feedEmpty"), "最近事件暂时读不到。", "Recent events could not be read.");
      var empty = $("feedEmpty");
      if (empty) empty.hidden = false;
    }
  }

  async function showAgent(addr) {
    var line = $("agentLine");
    if (!addr) {
      say(line, "连接后会读取 Agent ID。", "Connect to read the Agent ID.");
      return;
    }
    try {
      var v = await C.verifyAgent(addr);
      if (v.ok) say(line, "Agent ID：" + v.handle, "Agent ID: " + v.handle);
      else say(line, "这个地址没有可用的 Agent ID，铸造会被拒绝。", "This address has no usable Agent ID. Mint would be rejected.");
    } catch (e) {
      say(line, "Agent ID 暂时读不到。", "The Agent ID could not be read.");
    }
  }

  async function lookup(value) {
    var note = $("lookupNote");
    var raw = String(value || "").trim();
    if (!raw) {
      lookedUp = "";
      ticketRows = [];
      say(note, "输入钱包地址或船票编号。", "Enter a wallet address or a ticket id.");
      renderTickets();
      return;
    }
    if (/^\d+$/.test(raw)) {
      say(note, "正在读取船票 #" + raw + "。", "Reading ticket #" + raw + ".");
      var one = await C.readTicket(raw);
      lookedUp = "#" + raw;
      ticketRows = [];
      if (!one) {
        say(note, "链上没有船票 #" + raw + "。", "There is no ticket #" + raw + ".");
      } else {
        if (board && board.dayIndex) one.sandbag = await C.sandbagFor(one.id, board.dayIndex);
        ticketRows = [one];
        say(note, "船票 #" + raw + " 的持有人是 " + one.owner + "。", "Ticket #" + raw + " is held by " + one.owner + ".");
      }
      renderTickets();
      return;
    }
    if (!C.isAddr(raw)) {
      say(note, "地址格式不正确。", "That address is not valid.");
      return;
    }
    say(note, "正在读取 " + C.shortAddr(raw) + " 的船票。", "Reading tickets for " + C.shortAddr(raw) + ".");
    var found = await C.ticketsOf(raw);
    lookedUp = raw;
    var rows = found.tickets || [];
    if (board && board.dayIndex) {
      for (var i = 0; i < rows.length; i++) rows[i].sandbag = await C.sandbagFor(rows[i].id, board.dayIndex);
    }
    ticketRows = rows;
    var extra = found.truncated ? (zh() ? " 已铸造数量较大，本次只扫描了前 800 个编号。" : " Supply is large, so this pass scanned the first 800 ids.") : "";
    say(note,
      C.shortAddr(raw) + " 持有 " + found.balance.toString() + " 张，下面列出 " + rows.length + " 张。" + extra,
      C.shortAddr(raw) + " holds " + found.balance.toString() + ". Showing " + rows.length + "." + extra);
    renderTickets();
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (err) {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.left = "-9999px";
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
      document.body.removeChild(area);
      return ok;
    }
  }

  function syncChrome() {
    document.title = zh() ? "ARK100｜方舟100天" : "ARK100 · Hundred Days";
    document.querySelectorAll("[data-alt-zh]").forEach(function (el) {
      el.alt = zh() ? el.getAttribute("data-alt-zh") : el.getAttribute("data-alt-en");
    });
    document.querySelectorAll("[data-ph-zh]").forEach(function (el) {
      el.placeholder = zh() ? el.getAttribute("data-ph-zh") : el.getAttribute("data-ph-en");
    });
    document.querySelectorAll("[data-aria-zh]").forEach(function (el) {
      el.setAttribute("aria-label", zh() ? el.getAttribute("data-aria-zh") : el.getAttribute("data-aria-en"));
    });
    var toggle = $("langToggle");
    if (toggle) toggle.setAttribute("aria-label", zh() ? "语言" : "Language");
    var nav = $("siteNav");
    if (nav) nav.setAttribute("aria-label", zh() ? "页面分区" : "Sections");
    $("langZh").setAttribute("aria-pressed", zh() ? "true" : "false");
    $("langEn").setAttribute("aria-pressed", lang === "en" ? "true" : "false");
  }

  function setLang(next, persist) {
    lang = next === "en" ? "en" : "zh";
    document.documentElement.dataset.lang = lang;
    document.documentElement.lang = zh() ? "zh-CN" : "en";
    if (persist) {
      try { localStorage.setItem("ark100-lang", lang); } catch (e) {}
    }
    renderTide();
    renderSale();
    renderQuote();
    renderNight();
    renderActions();
    renderTickets();
    renderMarket();
    syncChrome();
    if (account) showAgent(account);
  }

  document.addEventListener("click", function (event) {
    var qtyBtn = event.target.closest("[data-qty]");
    if (qtyBtn) {
      qty = Number(qtyBtn.getAttribute("data-qty"));
      renderSale();
      refreshQuote();
      return;
    }
    var tab = event.target.closest("[data-tab]");
    if (tab) {
      var name = tab.getAttribute("data-tab");
      document.querySelectorAll("[data-tab]").forEach(function (btn) {
        btn.setAttribute("aria-selected", btn === tab ? "true" : "false");
      });
      $("panel-listings").hidden = name !== "listings";
      $("panel-bids").hidden = name !== "bids";
      return;
    }
    var filter = event.target.closest("#ark [data-filter]");
    if (filter) {
      ticketFilter = filter.getAttribute("data-filter");
      document.querySelectorAll("#ark [data-filter]").forEach(function (btn) {
        btn.setAttribute("aria-pressed", btn === filter ? "true" : "false");
      });
      renderTickets();
      return;
    }
    var langBtn = event.target.closest("[data-set-lang]");
    if (langBtn) {
      setLang(langBtn.getAttribute("data-set-lang"), true);
      return;
    }
    var copyBtn = event.target.closest("[data-copy='mint']");
    if (copyBtn) {
      copyText(mintBrief()).then(function (ok) {
        say($("mintStatus"), ok ? "已复制铸造说明。" : "无法写入剪贴板，说明仍留在页面上。", ok ? "Mint brief copied." : "Clipboard blocked. The brief is still on the page.");
      });
    }
  });

  $("connectBtn").addEventListener("click", function () {
    C.connect().then(function (addr) {
      account = addr;
      say($("walletChip"), addr ? C.shortAddr(addr) : "", addr ? C.shortAddr(addr) : "");
      $("walletInput").value = addr || "";
      showAgent(addr);
      say($("mintStatus"), "钱包已连接。", "Wallet connected.");
      return lookup(addr);
    }).catch(function (e) {
      say($("mintStatus"), walletError(e), walletError(e));
    });
  });

  $("mintBtn").addEventListener("click", function () {
    if (!board || !board.saleStarted || !board.mintOpen) {
      say($("mintStatus"), explain(board && board.refunding ? "refunding" : "sale-not-started"), explain(board && board.refunding ? "refunding" : "sale-not-started"));
      return;
    }
    say($("mintStatus"), "正在发送铸造交易。", "Sending the mint transaction.");
    C.sendMint(qty, board).then(function (out) {
      return track(out.hash, $("mintStatus"));
    }).catch(function (e) {
      say($("mintStatus"), walletError(e), walletError(e));
    });
  });

  $("lookup").addEventListener("submit", function (event) {
    event.preventDefault();
    lookup($("walletInput").value).catch(function () {
      say($("lookupNote"), "舱单暂时读不到。", "Tickets could not be read.");
    });
  });

  var useWallet = $("useWalletBtn");
  if (useWallet) {
    useWallet.addEventListener("click", function () {
      if (!account) {
        $("connectBtn").click();
        return;
      }
      $("walletInput").value = account;
      lookup(account).catch(function () {
        say($("lookupNote"), "舱单暂时读不到。", "Tickets could not be read.");
      });
    });
  }

  function idFrom(input) {
    var v = String($(input).value || "").trim();
    if (!/^\d+$/.test(v)) return null;
    return v;
  }

  function wireSend(id, slot, run) {
    var btn = $(id);
    if (!btn) return;
    btn.addEventListener("click", function () {
      Promise.resolve().then(run).then(function (hash) {
        if (!hash) return;
        return track(hash, $(slot));
      }).catch(function (e) {
        say($(slot), walletError(e), walletError(e));
      });
    });
  }

  wireSend("requestCabinBtn", "triggerStatus", function () {
    var id = idFrom("cabinIdInput");
    if (!id) throw C && Object.assign(new Error("bad-id"), { code: "bad-id" });
    say($("triggerStatus"), "正在发送 requestCabin。", "Sending requestCabin.");
    return C.sendRequestCabin(id);
  });
  wireSend("settleCabinBtn", "triggerStatus", function () {
    var id = idFrom("cabinIdInput");
    if (!id) throw Object.assign(new Error("bad-id"), { code: "bad-id" });
    say($("triggerStatus"), "正在发送 settleCabin。", "Sending settleCabin.");
    return C.sendSettleCabin(id);
  });
  wireSend("commitBtn", "triggerStatus", function () {
    var id = idFrom("floodDayInput");
    if (!id) throw Object.assign(new Error("bad-id"), { code: "bad-id" });
    say($("triggerStatus"), "正在发送 commit。", "Sending commit.");
    return C.sendCommit(id, board);
  });
  wireSend("openPoolBtn", "triggerStatus", function () {
    say($("triggerStatus"), "正在发送 openPool。", "Sending openPool.");
    return C.sendOpenPool(board);
  });
  wireSend("startFloodBtn", "triggerStatus", function () {
    say($("triggerStatus"), "正在发送 start。", "Sending start.");
    return C.sendStartFlood(board);
  });
  wireSend("enableRefundBtn", "triggerStatus", function () {
    say($("triggerStatus"), "正在发送 enableRefunds。", "Sending enableRefunds.");
    return C.sendEnableRefunds(board);
  });
  wireSend("claimShareBtn", "triggerStatus", function () {
    var id = idFrom("claimIdInput");
    if (!id) throw Object.assign(new Error("bad-id"), { code: "bad-id" });
    say($("triggerStatus"), "正在发送 claimShare。", "Sending claimShare.");
    return C.sendClaimShare(id, board);
  });
  wireSend("buyBagBtn", "triggerStatus", function () {
    say($("triggerStatus"), "正在发送购买沙袋。", "Sending the sandbag buy.");
    return C.sendBuyBag(1, board);
  });

  document.addEventListener("click", function (event) {
    var btn = event.target.closest("[data-act]");
    if (!btn) return;
    var act = btn.getAttribute("data-act");
    var id = btn.getAttribute("data-id");
    var run;
    if (act === "request-cabin") run = function () { return C.sendRequestCabin(id); };
    else if (act === "apply-bag") run = function () { return C.sendApplyBag(id, board && board.dayIndex, board); };
    else return;
    say($("arkStatus"), "正在发送交易。", "Sending the transaction.");
    Promise.resolve().then(run).then(function (hash) {
      return track(hash, $("arkStatus"));
    }).catch(function (e) {
      say($("arkStatus"), walletError(e), walletError(e));
    });
  });

  C.onWallet(function (addr) {
    account = addr || "";
    if ($("walletChip")) $("walletChip").textContent = account ? C.shortAddr(account) : "";
  });

  setLang(lang, false);
  renderMarket();
  renderTickets();
  refresh().catch(function () {
    say($("statusRead"), "链上读取失败", "Chain read failed");
    say($("mintStatus"), "链上状态暂时读不到。铸造保持关闭，不会发送交易。", "Chain state could not be read. Mint stays closed and no transaction will be sent.");
    setBi($("mintBtn"), "正式未开售", "Sale not started");
    $("mintBtn").disabled = true;
  });
  loadFeed();

  var sea = document.querySelector(".sea");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (!reduce && sea) {
    var ticking = false;
    window.addEventListener("scroll", function () {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(function () {
        var y = Math.min(window.scrollY, 800);
        sea.style.setProperty("--shift", (y * 0.08) + "px");
        ticking = false;
      });
    }, { passive: true });
  }
})();
