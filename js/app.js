(function () {
  var C = window.ArkChain;
  var lang = document.documentElement.dataset.lang === "en" ? "en" : "zh";
  var qty = 1;
  var board = null;
  var legacyRefund = null;
  var legacyAnchorMs = 0;
  var legacyRechecked = false;
  var boardAnchorMs = 0;
  var newRefundRechecked = false;
  var quote = null;
  var ticketFilter = "all";
  var ticketRows = [];
  var lookedUp = "";
  var account = "";
  var payBook = "bnb";
  var listingCache = {
    bnb: { deployed: false, feeBps: 250n, rows: [] },
    ark: { deployed: false, feeBps: 250n, rows: [] }
  };
  var bidCache = { deployed: false, feeBps: 250n, rows: [] };

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

  function mintPaused() {
    return !C || C.MINT_PAUSED !== false;
  }

  function saleLabel() {
    if (mintPaused()) return { zh: "铸造已暂停", en: "Minting paused" };
    if (!board) return { zh: "正在读取", en: "Reading" };
    if (!board.saleStarted) return { zh: "正式未开售", en: "Sale not started" };
    if (board.sold >= 10000n) return { zh: "已售罄", en: "Sold out" };
    return { zh: "发售中", en: "Sale is live" };
  }

  function mintBrief() {
    if (zh()) {
      return [
        "ARK100 暂停说明",
        "修复后的合约已经部署。铸造仍暂停，要等新发售写入 startTime。本站不会发送铸造。",
        "",
        "已经买到的旧船票，只有在旧发售开池前没有卖满 3000 张时，才能在退款窗口打开后全额退款。",
        "退款窗口大约是 2026-11-11 18:36（北京时间）。",
        "旧合约卖满 3000 张会自动开池，开池后就不能退款。请不要绕过官网直接调用旧合约铸造。",
        "窗口打开后，先在本站「公开动作」为旧发售开启退款，再到「我的方舟」，用当时付款的钱包按船票领取。",
        "新发售的开售时间，我们会另行公布。"
      ].join("\n");
    }
    return [
      "ARK100 pause notice",
      "The fixed suite is deployed. Minting stays paused until the new sale’s startTime is set. This site will not send a mint.",
      "",
      "Tickets already bought on the old sale can be refunded in full only if that sale stays under 3,000 before its pool opens.",
      "The refund window is around 2026-11-11 18:36 Asia/Shanghai.",
      "If the old contract reaches 3,000 sold, it opens the pool automatically, and refunds cannot be enabled after that. Do not bypass this site and mint by calling the old contract directly.",
      "After the window opens, turn refunds on for the old sale under Public actions, then claim each ticket in My Ark from the wallet that paid.",
      "When the new sale’s start time is set, it will be announced separately."
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
      say($("remainLine"), "已售已到 #3000。若池子还没打开，任何人可以再点开池。", "Sold has reached #3000. If the pool is still closed, anyone may call openPool().");
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
    mintBtn.disabled = true;
    mintBtn.setAttribute("aria-disabled", "true");
    mintBtn.classList.add("is-paused");
    setBi(mintBtn, "铸造已暂停，等待开售", "Minting paused until the sale starts");
  }

  function plainArk(value, fallback) {
    if (value == null) return fallback;
    var text = C.formatUnits(value, 18, 2);
    if (!text || text === "0") return fallback;
    return text;
  }

  function renderNight() {
    var count = $("nightCount");
    var hint = $("nightHint");
    if (!board) return;
    if (!board.floodStarted || !board.dayIndex) {
      setBi(count, "洪水未启动", "Flood not started");
      setBi(hint, "开池并启动百夜洪水之后，才有第 1 到第 100 晚", "Nights 1–100 begin after the pool opens and start()");
    } else {
      var n = board.dayIndex.toString();
      var settled = board.day && board.day.settled;
      setBi(count, "第 " + n + " / 100 晚", "Night " + n + " / 100");
      setBi(hint, settled ? "这一晚已经过完" : "这一晚还没过完", settled ? "This night is settled" : "This night is not settled yet");
    }
    if ($("arkNight")) {
      if (!board.floodStarted || !board.dayIndex) say($("arkNight"), "当前晚数：洪水未启动。", "Current night: the flood has not started.");
      else say($("arkNight"), "当前是第 " + board.dayIndex.toString() + " 晚。", "Current night: " + board.dayIndex.toString() + ".");
    }
    var base = plainArk(board.basePrice, "50");
    var showLive = !!(board.opened && board.aliveCount != null && board.aliveCount > 0n && board.shopPrice != null);
    if (showLive) {
      var price = plainArk(board.shopPrice, base);
      var alive = C.formatInt(board.aliveCount);
      say($("sandbagLive"),
        "现在还在船上的票有 " + alive + " 张，一袋大约 " + price + " ARK。人还多时大约 " + base + " ARK 一袋，幸存者越少越贵。",
        "With " + alive + " tickets still afloat, a bag is about " + price + " ARK. While many tickets are still afloat it is about " + base + " ARK, and the price rises as fewer survive.");
    } else {
      say($("sandbagLive"),
        "人还多、票还在航时，一袋大约 " + base + " ARK。幸存者越少越贵。开池、而且还有在航的票之后，才按当时还在船上的人数计价。开池前不把链上的预开数字当成现在要付的价格。",
        "While many tickets are still afloat, a bag is about " + base + " ARK. The price rises as fewer survive. The shop prices a bag from how many tickets are still afloat only after the pool is open. Until then, this page does not treat the pre-open chain figure as what you pay.");
    }
  }

  function renderActions() {
    if (!board) return;
    var openCard = $("openPoolCard");
    var startCard = $("startFloodCard");
    var refundCard = $("refundCard");
    if (openCard) openCard.hidden = !board.canOpen;
    if (startCard) startCard.hidden = !board.canStart;
    if (refundCard) refundCard.hidden = board.startTime === 0n || board.opened;
    var dayInput = $("floodDayInput");
    if (dayInput && board.dayIndex && !dayInput.value) dayInput.value = board.dayIndex.toString();
    var parts = [];
    var refundZh = board.startTime === 0n ? "未开始" : (board.opened ? "已结束" : (board.refundsOpen ? "可按票退" : "倒计时"));
    var refundEn = board.startTime === 0n ? "not started" : (board.opened ? "closed" : (board.refundsOpen ? "per ticket" : "countdown"));
    parts.push(zh()
      ? ("已售 " + C.formatInt(board.sold) + " / 10,000。开池：" + (board.opened ? "已打开" : "未打开") + "。退款：" + refundZh + "。洪水：" + (board.floodStarted ? "已启动" : "未启动") + "。")
      : (C.formatInt(board.sold) + " / 10,000 sold. Pool: " + (board.opened ? "open" : "closed") + ". Refunds: " + refundEn + ". Flood: " + (board.floodStarted ? "started" : "not started") + "."));
    if (mintPaused()) parts.push(zh() ? "网站已暂停铸造，不会发送铸造交易。" : "Minting on this site is paused. No mint is sent.");
    else if (!board.saleStarted) parts.push(zh() ? "铸造正式未开售。" : "Minting is not open yet.");
    else if (board.mintOpen) parts.push(zh() ? "铸造已开放。" : "Minting is open.");
    if (board.refundsOpen) {
      parts.push(zh()
        ? "新发售可按票退。到「我的方舟」，用持有这张票的钱包领取。铸造继续，卖到 3000 张仍会开池。"
        : "New-sale tickets can be refunded one by one. In My Ark, use the wallet that holds the ticket. Minting continues, and the pool still opens at 3,000.");
    }
    if (legacyRefund && legacyRefund.refunding) {
      parts.push(zh()
        ? "旧船票退款已开启。到「我的方舟」，用当时付款的钱包按票领取。"
        : "Refunds are on for old tickets. In My Ark, claim each one from the wallet that paid.");
    } else if (legacyRefund && legacyRefund.canEnableRefunds) {
      parts.push(zh()
        ? "旧发售已到退款窗口。可在公开动作为旧船票开启退款。"
        : "The old sale refund window is open. Turn refunds on for those tickets under Public actions.");
    }
    var line = parts.join(" ");
    say($("chainStatus"), line, line);
    var buy = $("buyBagBtn");
    if (buy) {
      buy.disabled = !board.opened;
      setBi(buy, board.opened ? "购买 1 个沙袋" : "开池后才能买沙袋", board.opened ? "Buy 1 sandbag" : "Sandbags open with the pool");
    }
    paintNewClocks();
  }

  function pad2(n) {
    n = Number(n);
    return (n < 10 ? "0" : "") + n;
  }

  function zoneParts(ts, offsetHours) {
    var shifted = Number(ts) + offsetHours * 3600;
    var d = new Date(shifted * 1000);
    return {
      y: d.getUTCFullYear(),
      m: d.getUTCMonth() + 1,
      day: d.getUTCDate(),
      h: d.getUTCHours(),
      min: d.getUTCMinutes()
    };
  }

  function zoneStamp(p) {
    return p.y + "-" + pad2(p.m) + "-" + pad2(p.day) + " " + pad2(p.h) + ":" + pad2(p.min);
  }

  function shortStamp(p) {
    return p.m + "/" + p.day + " " + pad2(p.h) + ":" + pad2(p.min);
  }

  function legacyNowSec() {
    if (!legacyRefund || !legacyAnchorMs) return BigInt(Math.floor(Date.now() / 1000));
    var elapsed = BigInt(Math.max(0, Math.floor((Date.now() - legacyAnchorMs) / 1000)));
    return legacyRefund.now + elapsed;
  }

  function countdownText(secs) {
    var s = Number(secs);
    if (s < 0) s = 0;
    var days = Math.floor(s / 86400);
    var clock = pad2(Math.floor((s % 86400) / 3600)) + ":" + pad2(Math.floor((s % 3600) / 60)) + ":" + pad2(s % 60);
    if (zh()) return days > 0 ? ("还剩 " + days + " 天 " + clock) : ("还剩 " + clock);
    return days > 0 ? (days + "d " + clock + " left") : (clock + " left");
  }

  function boardNowSec() {
    if (!board || !boardAnchorMs) return BigInt(Math.floor(Date.now() / 1000));
    var elapsed = BigInt(Math.max(0, Math.floor((Date.now() - boardAnchorMs) / 1000)));
    return board.now + elapsed;
  }

  function paintNewClocks() {
    var clock = $("newRefundClock");
    if (!board || board.startTime === 0n || board.opened) {
      if (clock) clock.hidden = true;
      return;
    }
    if (clock) {
      clock.hidden = false;
      var left = board.refundOpensAt - boardNowSec();
      if (board.refundsOpen || left <= 0n) {
        setBi(clock, "窗口已打开。到「我的方舟」按票退款。", "The window is open. Refund each ticket in My Ark.");
      } else {
        var text = countdownText(left);
        setBi(clock, text, text);
      }
    }
    document.querySelectorAll("[data-refund-clock]").forEach(function (el) {
      var remain = board.refundOpensAt - boardNowSec();
      if (remain < 0n) remain = 0n;
      var label = countdownText(remain);
      var zhEl = el.querySelector(".t-zh");
      var enEl = el.querySelector(".t-en");
      if (zhEl && enEl) {
        zhEl.textContent = label;
        enEl.textContent = label;
      } else {
        el.textContent = label;
      }
    });
    if (!board.refundsOpen && board.refundOpensAt !== 0n && boardNowSec() >= board.refundOpensAt && !newRefundRechecked) {
      newRefundRechecked = true;
      refresh().catch(function () {});
    }
  }

  function paintOldClock() {
    var clock = $("oldRefundClock");
    if (!clock || !legacyRefund || legacyRefund.refundsClosed || legacyRefund.refunding) return;
    if (legacyRefund.canEnableRefunds) {
      say(clock, "窗口已打开。", "The window is open.");
      return;
    }
    var left = legacyRefund.opensAt - legacyNowSec();
    if (left < 0n) left = 0n;
    var text = countdownText(left);
    say(clock, text, text);
  }

  function renderOldRefund() {
    var stats = $("oldRefundStats");
    var when = $("oldRefundWhen");
    var btn = $("oldEnableRefundBtn");
    var status = $("oldRefundStatus");
    if (!stats || !btn) return;
    if (!legacyRefund) {
      say(stats, "旧发售暂时读不到。新发售潮位不受影响。", "The old sale could not be read. The new sale tide is unchanged.");
      say(when, "退款窗口时间还没有读到。", "The refund window time is not in yet.");
      say($("oldRefundClock"), "倒计时暂停。", "Countdown paused.");
      btn.hidden = false;
      btn.disabled = true;
      btn.setAttribute("aria-disabled", "true");
      setBi(btn, "11/11 18:36（北京）后开放", "Opens Nov 11, 18:36 Beijing");
      return;
    }
    var sold = C.formatInt(legacyRefund.sold);
    say(stats,
      "旧发售已售 " + sold + " 张。池子" + (legacyRefund.opened ? "已打开" : "未打开") + "。退款" + (legacyRefund.refunding ? "已开启" : "未开启") + "。这张数不计入新发售潮位。",
      "Old sale: " + sold + " sold. Pool " + (legacyRefund.opened ? "open" : "closed") + ". Refunds " + (legacyRefund.refunding ? "on" : "off") + ". This count is not the new sale tide.");
    if (legacyRefund.refundsClosed) {
      say(when, "旧发售已开池，或已售达到 3000 张。退款不能再开启。", "The old sale opened, or it reached 3,000 sold. Refunds can no longer be turned on.");
      say($("oldRefundClock"), "倒计时已结束。", "The countdown is over.");
      btn.hidden = true;
      btn.disabled = true;
      btn.setAttribute("aria-disabled", "true");
      if (status) say(status, "旧票不能再退。", "Old tickets can no longer be refunded.");
      return;
    }
    var bj = zoneParts(legacyRefund.opensAt, 8);
    var tk = zoneParts(legacyRefund.opensAt, 9);
    say(when,
      "退款窗口：" + zoneStamp(bj) + "（北京） · " + zoneStamp(tk) + "（东京）。",
      "Refund window: " + zoneStamp(bj) + " Beijing · " + zoneStamp(tk) + " Tokyo.");
    if (legacyRefund.refunding) {
      say($("oldRefundClock"), "退款已经开启。", "Refunds are on.");
      btn.hidden = true;
      btn.disabled = true;
      btn.setAttribute("aria-disabled", "true");
      if (status) {
        status.innerHTML = "<span class=\"t-zh\">旧发售退款已开启。到<a href=\"#ark\">我的方舟</a>，用当时付款的钱包按旧票点「领退款」。</span><span class=\"t-en\">Refunds are on for the old tickets. In <a href=\"#ark\">My Ark</a>, claim each one from the wallet that paid.</span>";
      }
      return;
    }
    btn.hidden = false;
    paintOldClock();
    if (legacyRefund.canEnableRefunds) {
      btn.disabled = false;
      btn.removeAttribute("aria-disabled");
      setBi(btn, "开启退款", "enableRefunds");
      return;
    }
    btn.disabled = true;
    btn.setAttribute("aria-disabled", "true");
    setBi(btn, shortStamp(bj) + "（北京）后开放", "Opens " + shortStamp(bj) + " Beijing");
  }

  function cabinBadge(row) {
    if (row.sunk) return { cls: "mute", zh: "已沉", en: "Sunk" };
    if (row.unsettled) return { cls: "wait", zh: "未抽舱", en: "Unsettled" };
    if (row.cabin === 1) return { cls: "eco", zh: "经济 70%", en: "Economy 70%" };
    if (row.cabin === 2) return { cls: "biz", zh: "商务 25%", en: "Business 25%" };
    if (row.cabin === 3) return { cls: "cap", zh: "船长 5%", en: "Captain 5%" };
    return { cls: "wait", zh: "未抽舱", en: "Unsettled" };
  }

  function sameAddr(a, b) {
    return !!a && !!b && String(a).toLowerCase() === String(b).toLowerCase();
  }

  function payerClaim(payer) {
    if (account && sameAddr(account, payer)) return "ok";
    if (!account && C.isAddr(lookedUp) && sameAddr(lookedUp, payer)) return "ok";
    if (account && C.isAddr(lookedUp) && sameAddr(lookedUp, payer) && !sameAddr(account, payer)) return "switch";
    if (!account) return "connect";
    return "only";
  }

  function payerNote(kind) {
    if (kind === "switch") return ["请换付款钱包再领", "Switch to the paying wallet to claim"];
    if (kind === "connect") return ["连接付款钱包后可领", "Connect the paying wallet to claim"];
    return ["只有付款人能领", "Only the payer can claim"];
  }

  function refundOffer(row) {
    if (row.legacy) {
      if (legacyRefund && legacyRefund.refundsClosed) {
        return { kind: "mute", zh: "旧发售已开池，不能退款", en: "The old sale opened. Refunds are no longer possible." };
      }
      if (row.paidBnb == null || row.payerKnown === false) {
        return { kind: "mute", zh: "退款信息暂时读不到", en: "Refund details could not be read" };
      }
      var paid = BigInt(row.paidBnb);
      if (paid === 0n) return { kind: "mute", zh: "已领回", en: "Already claimed" };
      var ready = !!(legacyRefund && legacyRefund.refunding);
      if (!ready) return { kind: "button", disabled: true, paid: paid, sale: "legacy" };
      if (payerClaim(row.payer || "") === "ok") return { kind: "button", disabled: false, paid: paid, sale: "legacy" };
      var note = payerNote(payerClaim(row.payer || ""));
      return { kind: "button", disabled: true, paid: paid, sale: "legacy", zh: note[0], en: note[1] };
    }
    if (!board || board.opened || board.startTime === 0n) return null;
    if (row.paidBnb == null) {
      return { kind: "mute", zh: "退款信息暂时读不到", en: "Refund details could not be read" };
    }
    var paidNew = BigInt(row.paidBnb);
    if (paidNew === 0n) return null;
    if (!board.refundsOpen) return { kind: "countdown", paid: paidNew };
    var holding = account && sameAddr(account, row.owner || "");
    if (!holding) {
      return {
        kind: "button",
        disabled: true,
        paid: paidNew,
        sale: "new",
        zh: account ? "只有持有人能退" : "连接持有钱包后可退",
        en: account ? "Only the holder can refund" : "Connect the holding wallet to refund"
      };
    }
    return { kind: "button", disabled: false, paid: paidNew, sale: "new" };
  }

  function renderTickets() {
    var body = $("ticketBody");
    if (!body) return;
    body.innerHTML = "";
    var visible = 0;
    var afloat = 0, pending = 0, sunk = 0, bags = 0, daily = 0, legacyN = 0;
    ticketRows.forEach(function (row) {
      var state = row.sunk ? "sunk" : (row.unsettled ? "pending" : "afloat");
      if (row.legacy) legacyN++;
      else {
        if (state === "afloat") { afloat++; if (row.rate) daily += row.rate; }
        if (state === "pending") pending++;
        if (state === "sunk") sunk++;
        if (row.sandbag) bags++;
      }
      if (ticketFilter !== "all" && ticketFilter !== state) return;
      visible++;
      var tr = document.createElement("tr");
      tr.setAttribute("data-state", state);
      var badge = cabinBadge(row);
      var statusZh = state === "afloat" ? "在航" : (state === "pending" ? "待抽舱" : "已沉");
      var statusEn = state === "afloat" ? "Afloat" : (state === "pending" ? "Pending" : "Sunk");
      var statusCls = state === "afloat" ? "ok" : (state === "sunk" ? "sunk" : "wait");
      var bagZh = row.legacy ? "—" : (row.sandbag ? "已堆沙袋" : (board && board.floodStarted ? "无沙袋" : "—"));
      var bagEn = row.legacy ? "—" : (row.sandbag ? "Sandbagged" : (board && board.floodStarted ? "No sandbag" : "—"));
      var rate = row.rate == null ? "—" : String(row.rate);
      var idCell = "#" + row.id.toString();
      if (row.legacy) idCell += " <span class=\"badge mute\"><span class=\"t-zh\">旧票</span><span class=\"t-en\">Old</span></span>";
      tr.innerHTML =
        "<td>" + idCell + "</td>" +
        "<td><span class=\"badge " + badge.cls + "\"><span class=\"t-zh\">" + badge.zh + "</span><span class=\"t-en\">" + badge.en + "</span></span></td>" +
        "<td><span class=\"badge " + statusCls + "\"><span class=\"t-zh\">" + statusZh + "</span><span class=\"t-en\">" + statusEn + "</span></span></td>" +
        "<td>" + rate + "</td>" +
        "<td><span class=\"t-zh\">" + bagZh + "</span><span class=\"t-en\">" + bagEn + "</span></td>" +
        "<td></td>";
      var cell = tr.lastChild;
      var offer = refundOffer(row);
      if (offer && offer.kind === "countdown") {
        var clock = document.createElement("span");
        clock.className = "muted";
        clock.setAttribute("data-refund-clock", "1");
        clock.innerHTML = "<span class=\"t-zh\"></span><span class=\"t-en\"></span>";
        cell.appendChild(clock);
      } else if (offer && offer.kind === "button") {
        var wrap = document.createElement("div");
        wrap.className = "row-acts";
        var claim = actionButton("claim-refund", row.id, "领退款", "Claim refund", "refund");
        claim.setAttribute("data-sale", offer.sale || (row.legacy ? "legacy" : "new"));
        if (offer.disabled) {
          claim.disabled = true;
          claim.setAttribute("aria-disabled", "true");
        }
        wrap.appendChild(claim);
        wrap.appendChild(textSpan(bnbText(offer.paid), bnbText(offer.paid)));
        if (offer.zh) wrap.appendChild(textSpan(offer.zh, offer.en));
        cell.appendChild(wrap);
      } else if (offer) {
        cell.appendChild(textSpan(offer.zh, offer.en));
      } else if (row.legacy) {
        cell.appendChild(textSpan("—", "—"));
      } else if (state === "pending") cell.appendChild(actionButton("request-cabin", row.id, "抽舱", "Draw cabin"));
      else if (state === "afloat") cell.appendChild(actionButton("apply-bag", row.id, "沙袋护住", "Apply sandbag"));
      else cell.appendChild(textSpan("无产出", "No yield"));
      body.appendChild(tr);
    });
    $("statAfloat").textContent = String(afloat);
    $("statPending").textContent = String(pending);
    $("statSunk").textContent = String(sunk);
    $("statBags").textContent = String(bags);
    var legacyDaily = legacyN
      ? (zh() ? (" 另有旧船票 " + legacyN + " 张，不计入这份日产，退款走旧发售。") : (" " + legacyN + " old-sale ticket(s) are listed separately and are not in this total."))
      : "";
    say($("dailyLine"),
      lookedUp ? ("在航且已抽舱的日产合计 " + daily + " ARK。未抽舱还没有日产，已沉为 0。" + legacyDaily) : "连接钱包或输入地址后，这里显示链上日产。",
      lookedUp ? ("Afloat settled daily total " + daily + " ARK. Unsettled tickets have no rate yet. Sunk tickets earn 0." + legacyDaily) : "Connect a wallet or paste an address to read on-chain daily ARK.");
    var empty = $("filterEmpty");
    if (empty) {
      empty.hidden = !(lookedUp && visible === 0);
      setBi(empty, "这个筛选下没有船票。", "No tickets in this filter.");
    }
    var hint = $("refundHint");
    if (hint) {
      if (legacyRefund && legacyRefund.refundsClosed) {
        hint.hidden = false;
        setBi(hint, "旧发售已经开池，或者已售到了 3000 张。这些旧票不能再退。", "The old sale opened, or it reached 3,000 sold. Those old tickets can no longer be refunded.");
      } else if (legacyRefund && legacyRefund.refunding) {
        hint.hidden = false;
        setBi(hint, "旧发售退款已开启。用当时付款的钱包查看旧船票，再按票点「领退款」。已经领过的票不显示按钮。", "Refunds are on for the old sale. Look up tickets with the wallet that paid, then press Claim refund. A ticket already claimed shows no button.");
      } else if (legacyN > 0) {
        hint.hidden = false;
        setBi(hint, "旧票的「领退款」先停着，等旧发售退款开启后才能点。已经领过的票不显示按钮。", "Claim refund on an old ticket stays off until that sale’s refunds are on. A ticket already claimed shows no button.");
      } else if (board && board.refundsOpen) {
        hint.hidden = false;
        setBi(hint, "新发售可以按票退款。用持有这张票的钱包点「领退款」。铸造不停止，卖到 3000 张仍会开池。开池后不能再退。退款不恢复每地址 10 张的额度。", "New-sale tickets can be refunded one by one from the wallet that holds them. Minting continues, and the pool still opens at 3,000. Refunds stop once the pool opens. A refund does not restore the 10-per-address mint cap.");
      } else if (board && board.startTime !== 0n && !board.opened) {
        hint.hidden = false;
        setBi(hint, "新发售满 7 天、池子还没开时，持有人可以按票退款。窗口还没到，先显示倒计时。", "Seven days after the new sale starts, while the pool is closed, the holder can refund a ticket. The window is not open yet, so this shows a countdown.");
      } else {
        hint.hidden = true;
      }
    }
    paintNewClocks();
  }

  function textSpan(zhText, enText) {
    var span = document.createElement("span");
    span.className = "muted";
    span.innerHTML = "<span class=\"t-zh\"></span><span class=\"t-en\"></span>";
    span.querySelector(".t-zh").textContent = zhText;
    span.querySelector(".t-en").textContent = enText;
    return span;
  }

  function actionButton(act, id, zhText, enText, extraClass) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = extraClass ? ("ghost " + extraClass) : "ghost";
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

  function marketAddr(book) {
    return book === "ark" ? C.ADDR.marketArk : C.ADDR.marketBnb;
  }

  function feePct(bps) {
    var n = Number(bps);
    if (!Number.isFinite(n)) return "2.5%";
    return (n / 100).toString() + "%";
  }

  function throwCode(code) {
    var err = new Error(code);
    err.code = code;
    throw err;
  }

  function marketCabin(row) {
    if (row.mintedAt === 0n || row.cabin === 4) return { cls: "mute", zh: "已沉", en: "Sunk" };
    if (row.commit !== 0n) return { cls: "wait", zh: "抽舱中", en: "Cabin pending" };
    if (row.cabin === 1) return { cls: "eco", zh: "经济舱", en: "Economy" };
    if (row.cabin === 2) return { cls: "biz", zh: "商务舱", en: "Business" };
    if (row.cabin === 3) return { cls: "cap", zh: "船长舱", en: "Captain" };
    return { cls: "wait", zh: "未抽舱", en: "Unsettled" };
  }

  function marketRate(row) {
    if (row.mintedAt === 0n || row.cabin === 4) return "0";
    if (row.cabin === 0 || row.commit !== 0n) return "—";
    return C.CABIN_RATE[row.cabin] ? String(C.CABIN_RATE[row.cabin]) : "—";
  }

  function moneyText(amount, unit) {
    return C.formatUnits(amount, 18, 6) + " " + unit;
  }

  function bidWant(row) {
    if (row.kind === 2) return "#" + row.param.toString();
    if (row.kind === 1) {
      var names = { 0: ["未抽舱", "Unsettled"], 1: ["经济舱", "Economy"], 2: ["商务舱", "Business"], 3: ["船长舱", "Captain"] };
      var pair = names[Number(row.param)] || ["舱位", "Cabin"];
      return zh() ? pair[0] : pair[1];
    }
    return zh() ? "任何可挂船票" : "Any listable ticket";
  }

  function bidExpired(row) {
    var now = board && board.now ? board.now : BigInt(Math.floor(Date.now() / 1000));
    return row.expires <= now;
  }

  function bidStatus(row) {
    if (!row.open) return zh() ? "已关闭" : "Closed";
    if (bidExpired(row)) return zh() ? "已过期" : "Expired";
    var now = board && board.now ? Number(board.now) : Math.floor(Date.now() / 1000);
    var hrs = Math.max(1, Math.ceil((Number(row.expires) - now) / 3600));
    return zh() ? ("开放 · 约 " + hrs + " 小时") : ("Open · about " + hrs + "h");
  }

  function fillMarketOptions() {
    document.querySelectorAll("#market option[data-zh]").forEach(function (el) {
      el.textContent = zh() ? el.getAttribute("data-zh") : el.getAttribute("data-en");
    });
  }

  function syncBidFields() {
    var kind = $("bidKind") ? $("bidKind").value : "0";
    if ($("bidCabinWrap")) $("bidCabinWrap").hidden = kind !== "1";
    if ($("bidTokenWrap")) $("bidTokenWrap").hidden = kind !== "2";
    if ($("bidQty")) {
      $("bidQty").disabled = kind === "2";
      if (kind === "2") $("bidQty").value = "1";
    }
  }

  function showNote(el, textZh, textEn, on) {
    if (!el) return;
    el.hidden = !on;
    if (on) say(el, textZh, textEn);
  }

  function renderListingTable() {
    var body = $("listingBody");
    var book = listingCache[payBook] || { deployed: false, rows: [] };
    var unit = payBook === "ark" ? "ARK" : "BNB";
    if ($("priceHead")) setBi($("priceHead"), "价格（" + unit + "）", "Price (" + unit + ")");
    setBi($("listPriceLabel"), "价格（" + unit + "）", "Price (" + unit + ")");
    setBi($("listBtn"), payBook === "ark" ? "用 ARK 挂单" : "用 BNB 挂单", payBook === "ark" ? "List for ARK" : "List for BNB");
    var live = !C.isZeroAddr(marketAddr(payBook));
    ["listBtn", "cancelListBtn", "cleanListBtn"].forEach(function (id) {
      if ($(id)) $(id).disabled = !live;
    });
    if (!body) return;
    body.innerHTML = "";
    var rows = book.rows || [];
    if (!book.deployed) {
      showNote($("listingEmpty"), "市场合约待部署。", "Market contracts are not deployed yet.", true);
      showNote($("listingNote"), "", "", false);
      return;
    }
    showNote($("listingEmpty"), "这本簿上还没有挂单。", "No listings on this book yet.", rows.length === 0);
    showNote($("listingNote"), "挂单较多，这里只显示前 40 条。", "More than 40 listings. Showing the first 40.", !!book.truncated && rows.length > 0);
    rows.forEach(function (row) {
      var tr = document.createElement("tr");
      var badge = marketCabin(row);
      tr.innerHTML =
        "<td>#" + row.id.toString() + "</td>" +
        "<td><span class=\"badge " + badge.cls + "\"><span class=\"t-zh\">" + badge.zh + "</span><span class=\"t-en\">" + badge.en + "</span></span></td>" +
        "<td>" + marketRate(row) + "</td>" +
        "<td>" + moneyText(row.price, unit) + "</td>" +
        "<td></td><td></td>";
      tr.children[4].textContent = C.shortAddr(row.seller);
      var acts = document.createElement("div");
      acts.className = "row-acts";
      if (account && sameAddr(account, row.seller)) {
        var cancel = actionButton("cancel-listing", row.id, "撤单", "Cancel");
        cancel.setAttribute("data-book", payBook);
        acts.appendChild(cancel);
      } else if (row.buyable) {
        var buy = actionButton("buy-listing", row.id, "购买", "Buy");
        buy.setAttribute("data-book", payBook);
        acts.appendChild(buy);
      } else {
        var clean = actionButton("clean-listing", row.id, "清理", "Clean");
        clean.setAttribute("data-book", payBook);
        acts.appendChild(clean);
        acts.appendChild(textSpan("现在不能成交", "Not buyable now"));
      }
      tr.children[5].appendChild(acts);
      body.appendChild(tr);
    });
  }

  function renderBidTable() {
    var body = $("bidBody");
    var live = !C.isZeroAddr(C.ADDR.marketBid);
    ["postBidBtn", "cancelBidBtn", "refundBidBtn"].forEach(function (id) {
      if ($(id)) $(id).disabled = !live;
    });
    if (!body) return;
    body.innerHTML = "";
    var rows = (bidCache && bidCache.rows) || [];
    if (!bidCache.deployed) {
      showNote($("bidEmpty"), "市场合约待部署。", "Market contracts are not deployed yet.", true);
      showNote($("bidNote"), "", "", false);
      return;
    }
    showNote($("bidEmpty"), "这本求购簿上还没有出价。", "No bids on this book yet.", rows.length === 0);
    showNote($("bidNote"), "求购较多，这里只显示前 40 条。", "More than 40 bids. Showing the first 40.", !!bidCache.truncated && rows.length > 0);
    rows.forEach(function (row) {
      var tr = document.createElement("tr");
      var expired = bidExpired(row);
      tr.innerHTML =
        "<td>#" + row.id.toString() + "</td>" +
        "<td></td>" +
        "<td>" + moneyText(row.unitPrice, "BNB") + "</td>" +
        "<td>" + row.qtyLeft.toString() + "</td>" +
        "<td></td>" +
        "<td></td><td></td>";
      tr.children[1].textContent = bidWant(row);
      tr.children[4].textContent = C.shortAddr(row.buyer);
      tr.children[5].textContent = bidStatus(row);
      var acts = document.createElement("div");
      acts.className = "row-acts";
      if (row.open && expired) {
        acts.appendChild(actionButton("refund-bid", row.id, "退回", "Refund"));
      } else if (row.open) {
        if (row.kind === 2) {
          var fillFixed = actionButton("fill-bid", row.param, "成交", "Fill");
          fillFixed.setAttribute("data-bid", row.id.toString());
          fillFixed.setAttribute("data-token", row.param.toString());
          acts.appendChild(fillFixed);
        } else {
          var input = document.createElement("input");
          input.className = "mini-input";
          input.setAttribute("inputmode", "numeric");
          input.setAttribute("data-fill-for", row.id.toString());
          input.placeholder = zh() ? "船票编号" : "Ticket id";
          var fill = actionButton("fill-bid", row.id, "成交", "Fill");
          fill.setAttribute("data-bid", row.id.toString());
          acts.appendChild(input);
          acts.appendChild(fill);
        }
      }
      if (account && sameAddr(account, row.buyer) && row.open) {
        acts.appendChild(actionButton("cancel-bid", row.id, "撤销", "Cancel"));
      }
      tr.children[6].appendChild(acts);
      body.appendChild(tr);
    });
  }

  function formWei(id) {
    var el = $(id);
    if (!el || !String(el.value || "").trim()) return "";
    try {
      var parsed = C.parseUnits(el.value, 18);
      return parsed > 0n ? parsed.toString() : "";
    } catch (e) {
      return "";
    }
  }

  function marketBrief() {
    var book = payBook;
    var market = marketAddr(book);
    var bnbBps = listingCache.bnb && listingCache.bnb.feeBps != null ? listingCache.bnb.feeBps.toString() : "250";
    var arkBps = listingCache.ark && listingCache.ark.feeBps != null ? listingCache.ark.feeBps.toString() : "250";
    var bidBps = bidCache && bidCache.feeBps != null ? bidCache.feeBps.toString() : "250";
    var ticket = ($("listId") && $("listId").value.trim()) || "TICKET_ID";
    var price = formWei("listPrice") || "PRICE_WEI";
    var kind = $("bidKind") ? $("bidKind").value : "0";
    var param = "0";
    var qty = ($("bidQty") && $("bidQty").value.trim()) || "1";
    if (kind === "1") param = $("bidCabin") ? $("bidCabin").value : "0";
    if (kind === "2") {
      param = ($("bidTokenId") && $("bidTokenId").value.trim()) || "TICKET_ID";
      qty = "1";
    }
    var unit = formWei("bidPrice") || "UNIT_PRICE_WEI";
    var hours = ($("bidHours") && $("bidHours").value.trim()) || "168";
    var deployedNote = (!C.isZeroAddr(C.ADDR.marketBnb) || !C.isZeroAddr(C.ADDR.marketArk) || !C.isZeroAddr(C.ADDR.marketBid))
      ? ""
      : (zh() ? "市场合约待部署。下面的地址还是 0，不要发送交易。" : "Market contracts are not deployed yet. The addresses below are still zero. Do not send.");
    if (zh()) {
      return [
        "ARK100 市场说明",
        "链：BNB Smart Chain（chainId 56）",
        deployedNote,
        "不需要 Agent ID。只有铸造需要。",
        "可成交：还在航，且 cabinCommitBlock 为 0。沉船和正在 requestCabin 的票会被拒绝。",
        "舱位和未领日产跟着船票走。",
        "手续费：BNB 簿 MARKET_FEE_BPS=" + bnbBps + "，ARK 簿=" + arkBps + "，求购=" + bidBps + "。由合约付给项目手续费钱包。",
        "",
        "BNB 挂单 TicketMarketBNB: " + C.ADDR.marketBnb,
        "ARK 挂单 TicketMarketARK: " + C.ADDR.marketArk,
        "BNB 求购 TicketBidMarket: " + C.ADDR.marketBid,
        "船票 TicketNFT: " + C.ADDR.nft,
        "ARK: " + C.ADDR.ark,
        "",
        "当前挂单簿：" + (book === "ark" ? "ARK" : "BNB"),
        "1. 船票授权给这本簿（若尚未授权）：TicketNFT.approve(market, " + ticket + ")",
        "2. list(" + ticket + ", " + price + ")，价格单位是 wei，不要附带 BNB。",
        book === "ark"
          ? "购买：ARK.approve(TicketMarketARK, 价格) 然后 buy(" + ticket + ")，value = 0。不要把 BNB 打进 ARK 簿。"
          : "购买：buy(" + ticket + ")，value = 挂单价格（wei）。多付的 BNB 会退回。",
        "撤单：cancel(" + ticket + ")，仅卖家。失效记录：cleanListing(" + ticket + ")。",
        "",
        "求购：postBid(kind, param, unitPrice, qty, durationSeconds)",
        "kind 0 任何可挂（param=0），kind 1 舱位（0 未抽舱 / 1 经济 / 2 商务 / 3 船长），kind 2 指定船票且 qty=1。",
        "这一笔：postBid(" + kind + ", " + param + ", " + unit + ", " + qty + ", " + hours + " * 3600)",
        "value 必须等于单价 × 数量。",
        "成交：先把船票授权给求购合约，再 acceptBid(bidId, tokenId)。过期不能成交。",
        "出价人 cancelBid(bidId) 退回剩余。过期后任何人 refundExpired(bidId)。"
      ].filter(Boolean).join("\n");
    }
    return [
      "ARK100 market brief",
      "Chain: BNB Smart Chain (chainId 56)",
      deployedNote,
      "No Agent ID. Mint is the only call that checks it.",
      "Tradable: afloat and cabinCommitBlock == 0. Sunk tickets and tickets inside requestCabin are rejected.",
      "Cabin and unclaimed yield stay on the ticket.",
      "Fee: BNB book MARKET_FEE_BPS=" + bnbBps + ", ARK book=" + arkBps + ", bids=" + bidBps + ". The contract pays the project fee wallet.",
      "",
      "BNB listings TicketMarketBNB: " + C.ADDR.marketBnb,
      "ARK listings TicketMarketARK: " + C.ADDR.marketArk,
      "BNB bids TicketBidMarket: " + C.ADDR.marketBid,
      "TicketNFT: " + C.ADDR.nft,
      "ARK: " + C.ADDR.ark,
      "",
      "Open listing book: " + (book === "ark" ? "ARK" : "BNB"),
      "1. Approve the ticket for that book if needed: TicketNFT.approve(market, " + ticket + ")",
      "2. list(" + ticket + ", " + price + "). Price is wei. Do not attach BNB to list.",
      book === "ark"
        ? "Buy: ARK.approve(TicketMarketARK, price) then buy(" + ticket + ") with value 0. Do not send BNB to the ARK book."
        : "Buy: buy(" + ticket + ") with value = the listing price in wei. Extra BNB is refunded.",
      "Cancel: cancel(" + ticket + "), seller only. Stale row: cleanListing(" + ticket + ").",
      "",
      "Bid: postBid(kind, param, unitPrice, qty, durationSeconds)",
      "kind 0 any listable (param 0), kind 1 cabin (0 unsettled / 1 economy / 2 business / 3 captain), kind 2 one tokenId and qty 1.",
      "This form: postBid(" + kind + ", " + param + ", " + unit + ", " + qty + ", " + hours + " * 3600)",
      "value must equal unitPrice * qty.",
      "Fill: approve the ticket for the bid market, then acceptBid(bidId, tokenId). Expired bids cannot be filled.",
      "The bidder calls cancelBid(bidId) to refund the remainder. After expiry anyone calls refundExpired(bidId)."
    ].filter(Boolean).join("\n");
  }

  function renderMarketBrief() {
    var pre = $("marketCmd");
    if (pre) pre.textContent = marketBrief();
  }

  function renderMarket() {
    var bnbLive = !C.isZeroAddr(C.ADDR.marketBnb);
    var arkLive = !C.isZeroAddr(C.ADDR.marketArk);
    var bidLive = !C.isZeroAddr(C.ADDR.marketBid);
    var bps = function (key) {
      var src = key === "bid" ? bidCache : listingCache[key];
      return src && src.feeBps != null ? src.feeBps : 250n;
    };
    if (bnbLive && arkLive && bidLive) {
      say($("marketDeploy"),
        "三本市场簿已接上 BSC 主网。",
        "All three market books are on BSC mainnet.");
    } else if (!bnbLive && !arkLive && !bidLive) {
      say($("marketDeploy"),
        "市场合约待部署。js/chain.js 里 marketBnb、marketArk、marketBid 还是 0 地址，所以下面的表是空的。",
        "Market contracts are not deployed yet. marketBnb, marketArk, and marketBid in js/chain.js are still the zero address, so these tables stay empty.");
    } else {
      say($("marketDeploy"),
        "已填地址的簿会读链上挂单和求购。还是 0 地址的簿保持空白。",
        "Books with an address read live listings and bids. A zero address stays blank.");
    }
    say($("marketFee"),
      "手续费 " + feePct(bps(payBook)) + "（MARKET_FEE_BPS）。BNB 簿 " + bps("bnb").toString() + "，ARK 簿 " + bps("ark").toString() + "，求购 " + bps("bid").toString() + "。",
      "Fee " + feePct(bps(payBook)) + " (MARKET_FEE_BPS). BNB book " + bps("bnb").toString() + ", ARK book " + bps("ark").toString() + ", bids " + bps("bid").toString() + ".");
    fillMarketOptions();
    syncBidFields();
    renderListingTable();
    renderBidTable();
    renderMarketBrief();
  }

  async function loadMarket() {
    var results = await Promise.allSettled([
      C.readListingBook(C.ADDR.marketBnb),
      C.readListingBook(C.ADDR.marketArk),
      C.readBidBook(C.ADDR.marketBid)
    ]);
    if (results[0].status === "fulfilled") listingCache.bnb = results[0].value;
    if (results[1].status === "fulfilled") listingCache.ark = results[1].value;
    if (results[2].status === "fulfilled") bidCache = results[2].value;
    renderMarket();
    var failed = results.find(function (item) { return item.status === "rejected"; });
    if (failed) throw failed.reason || new Error("market");
  }

  async function marketTrack(hash) {
    var slot = $("marketStatus");
    say(slot, "交易已提交，等待确认。", "Transaction submitted, waiting for confirmation.");
    if (slot) {
      slot.appendChild(document.createTextNode(" "));
      slot.appendChild(txLink(hash));
    }
    var rec = await C.waitReceipt(hash);
    if (!rec) {
      say(slot, "交易已提交，确认还没返回。", "Submitted. The receipt is not back yet.");
      if (slot) { slot.appendChild(document.createTextNode(" ")); slot.appendChild(txLink(hash)); }
      return false;
    }
    var ok = rec.status === "0x1";
    say(slot, ok ? "交易已确认。" : "交易失败。", ok ? "Transaction confirmed." : "Transaction failed.");
    if (slot) { slot.appendChild(document.createTextNode(" ")); slot.appendChild(txLink(hash)); }
    if (ok) refresh().catch(function () {});
    return ok;
  }

  async function ensureNftApproval(market, id) {
    var approved = "";
    try { approved = await C.getApproved(id); } catch (e) { approved = ""; }
    var all = false;
    if (account) {
      try { all = await C.isApprovedForAll(account, market); } catch (e2) { all = false; }
    }
    if (all || sameAddr(approved, market)) return true;
    say($("marketStatus"), "先授权船票给市场，确认后再继续。", "Approve the ticket for the market, then this continues.");
    var hash = await C.sendApproveNft(market, id);
    return marketTrack(hash);
  }

  async function doList() {
    var market = marketAddr(payBook);
    if (C.isZeroAddr(market)) throwCode("market-not-deployed");
    var id = idFrom("listId");
    if (!id) throwCode("bad-id");
    var price = C.parseUnits($("listPrice").value, 18);
    if (price <= 0n) throwCode("bad-amount");
    if (!await ensureNftApproval(market, id)) return;
    say($("marketStatus"), "正在发送挂单。", "Sending list.");
    await marketTrack(await C.sendList(market, id, price));
  }

  async function doCancelListing(id) {
    var market = marketAddr(payBook);
    if (C.isZeroAddr(market)) throwCode("market-not-deployed");
    if (!/^\d+$/.test(String(id || ""))) throwCode("bad-id");
    say($("marketStatus"), "正在撤单。", "Sending cancel.");
    await marketTrack(await C.sendCancelListing(market, id));
  }

  async function doCleanListing(id) {
    var market = marketAddr(payBook);
    if (C.isZeroAddr(market)) throwCode("market-not-deployed");
    if (!/^\d+$/.test(String(id || ""))) throwCode("bad-id");
    say($("marketStatus"), "正在清理失效挂单。", "Sending cleanListing.");
    await marketTrack(await C.sendCleanListing(market, id));
  }

  async function doBuy(book, id) {
    var market = marketAddr(book);
    if (C.isZeroAddr(market)) throwCode("market-not-deployed");
    if (!/^\d+$/.test(String(id || ""))) throwCode("bad-id");
    if (book === "ark") {
      var row = await C.readListing(market, id);
      if (row.price === 0n) throwCode("unlisted");
      var allowance = 0n;
      if (account) {
        try { allowance = await C.arkAllowance(account, market); } catch (e) { allowance = 0n; }
      }
      if (allowance < row.price) {
        say($("marketStatus"), "先授权 ARK，确认后再购买。", "Approve ARK, then the buy continues.");
        if (!await marketTrack(await C.sendApproveArk(market, row.price))) return;
      }
      say($("marketStatus"), "正在发送 ARK 购买。", "Sending the ARK buy.");
      await marketTrack(await C.sendBuyArk(id));
      return;
    }
    say($("marketStatus"), "正在发送 BNB 购买。", "Sending the BNB buy.");
    await marketTrack(await C.sendBuyBnb(id));
  }

  function readBidForm() {
    if (C.isZeroAddr(C.ADDR.marketBid)) throwCode("market-not-deployed");
    var kind = Number($("bidKind").value);
    if (kind !== 0 && kind !== 1 && kind !== 2) throwCode("bad-kind");
    var qtyText = String($("bidQty").value || "").trim();
    if (!/^\d+$/.test(qtyText) || BigInt(qtyText) <= 0n) throwCode("bad-qty");
    var qty = BigInt(qtyText);
    var param = 0n;
    if (kind === 1) param = BigInt($("bidCabin").value);
    if (kind === 2) {
      var token = idFrom("bidTokenId");
      if (!token) throwCode("bad-id");
      param = BigInt(token);
      qty = 1n;
    }
    var unit = C.parseUnits($("bidPrice").value, 18);
    if (unit <= 0n) throwCode("bad-amount");
    var hoursText = String($("bidHours").value || "").trim();
    if (!/^\d+$/.test(hoursText)) throwCode("bad-duration");
    var hours = BigInt(hoursText);
    if (hours < 1n || hours > 720n) throwCode("bad-duration");
    return { kind: kind, param: param, unit: unit, qty: qty, duration: hours * 3600n };
  }

  async function doPostBid() {
    var spec = readBidForm();
    var total = spec.unit * spec.qty;
    say($("marketStatus"),
      "正在发布求购，托管 " + C.formatUnits(total, 18, 6) + " BNB。",
      "Posting the bid. Escrow " + C.formatUnits(total, 18, 6) + " BNB.");
    await marketTrack(await C.sendPostBid(spec.kind, spec.param, spec.unit, spec.qty, spec.duration));
  }

  async function doFill(bidId, tokenId) {
    if (C.isZeroAddr(C.ADDR.marketBid)) throwCode("market-not-deployed");
    if (!/^\d+$/.test(String(bidId || "")) || !/^\d+$/.test(String(tokenId || ""))) throwCode("bad-id");
    if (!await ensureNftApproval(C.ADDR.marketBid, tokenId)) return;
    say($("marketStatus"), "正在成交求购。", "Sending acceptBid.");
    await marketTrack(await C.sendAcceptBid(bidId, tokenId));
  }

  async function doCancelBid(id) {
    if (!/^\d+$/.test(String(id || ""))) throwCode("bad-id");
    say($("marketStatus"), "正在撤销求购。", "Sending cancelBid.");
    await marketTrack(await C.sendCancelBid(id));
  }

  async function doRefundBid(id) {
    if (!/^\d+$/.test(String(id || ""))) throwCode("bad-id");
    say($("marketStatus"), "正在退回过期求购。", "Sending refundExpired.");
    await marketTrack(await C.sendRefundExpired(id));
  }

  function wireMarket(id, run) {
    var btn = $(id);
    if (!btn || btn.dataset.marketBound) return;
    btn.dataset.marketBound = "1";
    btn.addEventListener("click", function () {
      Promise.resolve().then(run).catch(function (e) {
        say($("marketStatus"), walletError(e), walletError(e));
      });
    });
  }

  function initMarket() {
    ["listId", "listPrice", "cancelListId", "cleanListId", "bidKind", "bidCabin", "bidTokenId", "bidPrice", "bidQty", "bidHours"].forEach(function (id) {
      var el = $(id);
      if (!el || el.dataset.marketBound) return;
      el.dataset.marketBound = "1";
      var update = function () { syncBidFields(); renderMarketBrief(); };
      el.addEventListener("input", update);
      el.addEventListener("change", update);
    });
    wireMarket("listBtn", doList);
    wireMarket("cancelListBtn", function () { return doCancelListing(idFrom("cancelListId")); });
    wireMarket("cleanListBtn", function () { return doCleanListing(idFrom("cleanListId")); });
    wireMarket("postBidBtn", doPostBid);
    wireMarket("cancelBidBtn", function () { return doCancelBid(idFrom("cancelBidId")); });
    wireMarket("refundBidBtn", function () { return doRefundBid(idFrom("cancelBidId")); });
  }

  function explain(code, detail) {
    var map = {
      "mint-paused": ["铸造已暂停，要等新发售设定 startTime。没有发送交易。旧合约卖满 3000 张会自动开池，开池后就不能退款，请不要绕过官网直接铸造。", "Minting is paused until the new sale’s startTime is set. No transaction was sent. If the old contract reaches 3,000 sold, it opens the pool automatically, and refunds cannot be enabled after that. Do not bypass this site and mint on the old contract."],
      "sale-not-started": ["正式未开售，没有发送交易。", "Sale not started. No transaction was sent."],
      "refunding": ["退款已开启，铸造已停止，没有发送交易。", "Refunds are on, so mint is closed. No transaction was sent."],
      "mint-closed": ["当前不能铸造，没有发送交易。", "Mint is closed. No transaction was sent."],
      "no-wallet": ["没有发现浏览器钱包。", "No browser wallet was found."],
      "open-not-ready": ["还不能开池：需要已售至少 3000，而且池子还没打开。没有发送交易。", "openPool is not ready: sold must be at least 3,000 and the pool still closed. No transaction was sent."],
      "start-not-ready": ["还不能启动洪水：需要池子已开且洪水未启动。没有发送交易。", "start() is not ready: the pool must be open and the flood not started. No transaction was sent."],
      "refund-not-ready": ["退款窗口还没到。没有发送交易。", "The refund window is not open. No transaction was sent."],
      "refund-closed": ["退款还没开启，没有发送交易。", "Refunds are not on yet. No transaction was sent."],
      "flood-not-started": ["洪水尚未启动，没有发送交易。", "The flood has not started. No transaction was sent."],
      "pool-not-open": ["开池之后才能买沙袋，没有发送交易。", "Sandbags can be bought after the pool opens. No transaction was sent."],
      "pot-not-landed": ["奖池尚未靠岸，没有发送交易。", "The pot has not landed. No transaction was sent."],
      "bad-id": ["请输入船票编号。", "Enter a ticket id."],
      "market-not-deployed": ["市场合约待部署，没有发送交易。", "Market contracts are not deployed. No transaction was sent."],
      "bad-amount": ["价格格式不正确。用十进制数量，最多 18 位小数。", "Price must be a decimal with at most 18 fractional digits."],
      "bad-qty": ["求购数量要是正整数。指定船票时数量只能是 1。", "Bid quantity must be a positive integer. A specific ticket allows quantity 1."],
      "bad-duration": ["求购时长要在 1 到 720 小时之间。", "Bid duration must be from 1 to 720 hours."],
      "bad-kind": ["求购类型不正确。", "That bid kind is not valid."],
      "unlisted": ["这张船票没有挂单。", "That ticket is not listed."],
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
    boardAnchorMs = Date.now();
    try {
      legacyRefund = await C.readLegacyRefund();
      legacyAnchorMs = Date.now();
      legacyRechecked = !!(legacyRefund && (legacyRefund.canEnableRefunds || legacyRefund.refunding || legacyRefund.refundsClosed));
    } catch (e) {
      legacyRefund = null;
    }
    renderOldRefund();
    renderTide();
    renderSale();
    renderNight();
    renderActions();
    renderTickets();
    renderQuote();
    await refreshQuote();
    say($("statusRead"), "链上读取", "On-chain");
    try {
      await loadMarket();
    } catch (e) {
      say($("marketStatus"), zh() ? "市场暂时读不到。" : "The market could not be read.");
    }
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
      else say(line, "这个地址没有可用的 Agent ID。", "This address has no usable Agent ID.");
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
        if (board && board.dayIndex && !one.legacy) one.sandbag = await C.sandbagFor(one.id, board.dayIndex);
        ticketRows = [one];
        if (one.legacy) {
          say(note, "船票 #" + raw + " 是旧发售船票，持有人是 " + one.owner + "。退款走旧发售合约。", "Ticket #" + raw + " is an old-sale ticket, held by " + one.owner + ". Refunds use the old sale.");
        } else {
          say(note, "船票 #" + raw + " 的持有人是 " + one.owner + "。", "Ticket #" + raw + " is held by " + one.owner + ".");
        }
      }
      renderTickets();
      return;
    }
    if (!C.isAddr(raw)) {
      say(note, "地址格式不正确。", "That address is not valid.");
      return;
    }
    say(note, "正在读取 " + C.shortAddr(raw) + " 的船票。", "Reading tickets for " + C.shortAddr(raw) + ".");
    var found = await C.ticketsOf(raw, { includePayer: true });
    lookedUp = raw;
    var rows = found.tickets || [];
    if (board && board.dayIndex) {
      for (var i = 0; i < rows.length; i++) {
        if (!rows[i].legacy) rows[i].sandbag = await C.sandbagFor(rows[i].id, board.dayIndex);
      }
    }
    ticketRows = rows;
    var legacyListed = rows.filter(function (row) { return row.legacy; }).length;
    var extra = found.truncated ? (zh() ? " 已铸造数量较大，本次只扫描了前 800 个编号。" : " Supply is large, so this pass scanned the first 800 ids.") : "";
    var transferred = (found.legacyBalance != null && legacyListed > Number(found.legacyBalance))
      ? (zh() ? " 其中有已转出、但仍记在这只付款钱包名下的旧票。" : " Some old tickets were transferred away and are still recorded to this paying wallet.")
      : "";
    var oldNote = legacyListed
      ? (zh() ? (" 其中 " + legacyListed + " 张是旧发售船票。") : (" " + legacyListed + " of those are old-sale tickets."))
      : "";
    say(note,
      C.shortAddr(raw) + " 在新船票上持有 " + found.balance.toString() + " 张，下面列出 " + rows.length + " 张。" + oldNote + transferred + extra,
      C.shortAddr(raw) + " holds " + found.balance.toString() + " on the new tickets. Showing " + rows.length + "." + oldNote + transferred + extra);
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
    fillMarketOptions();
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
    renderOldRefund();
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
    var pay = event.target.closest("[data-pay]");
    if (pay) {
      payBook = pay.getAttribute("data-pay") === "ark" ? "ark" : "bnb";
      document.querySelectorAll("[data-pay]").forEach(function (btn) {
        btn.setAttribute("aria-selected", btn === pay ? "true" : "false");
      });
      renderMarket();
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
        say($("mintStatus"), ok ? "已复制暂停说明。" : "无法写入剪贴板，说明仍留在页面上。", ok ? "Pause notice copied." : "Clipboard blocked. The notice is still on the page.");
      });
    }
    var copyMarket = event.target.closest("[data-copy='market']");
    if (copyMarket) {
      copyText(marketBrief()).then(function (ok) {
        say($("marketStatus"), ok ? "已复制市场说明。" : "无法写入剪贴板，说明仍留在页面上。", ok ? "Market brief copied." : "Clipboard blocked. The brief is still on the page.");
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

  $("mintBtn").addEventListener("click", function (event) {
    event.preventDefault();
    renderSale();
    say($("mintStatus"), explain("mint-paused"), explain("mint-paused"));
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
    say($("triggerStatus"), "正在发送申请抽舱。", "Sending requestCabin.");
    return C.sendRequestCabin(id);
  });
  wireSend("settleCabinBtn", "triggerStatus", function () {
    var id = idFrom("cabinIdInput");
    if (!id) throw Object.assign(new Error("bad-id"), { code: "bad-id" });
    say($("triggerStatus"), "正在发送揭晓舱位。", "Sending settleCabin.");
    return C.sendSettleCabin(id);
  });
  wireSend("commitBtn", "triggerStatus", function () {
    var id = idFrom("floodDayInput");
    if (!id) throw Object.assign(new Error("bad-id"), { code: "bad-id" });
    say($("triggerStatus"), "正在提交当晚洪水。", "Sending commit.");
    return C.sendCommit(id, board);
  });
  wireSend("openPoolBtn", "triggerStatus", function () {
    say($("triggerStatus"), "正在发送开池。", "Sending openPool.");
    return C.sendOpenPool(board);
  });
  wireSend("startFloodBtn", "triggerStatus", function () {
    say($("triggerStatus"), "正在启动百夜洪水。", "Sending start.");
    return C.sendStartFlood(board);
  });
  wireSend("oldEnableRefundBtn", "oldRefundStatus", function () {
    var btn = $("oldEnableRefundBtn");
    if (!btn || btn.disabled || btn.hidden) return;
    if (!legacyRefund || !legacyRefund.canEnableRefunds || legacyRefund.refundsClosed) {
      var blocked = new Error("refund-not-ready");
      blocked.code = "refund-not-ready";
      throw blocked;
    }
    say($("oldRefundStatus"), "正在为旧发售开启退款。", "Sending enableRefunds on the old sale.");
    return C.sendEnableRefunds();
  });
  wireSend("claimShareBtn", "triggerStatus", function () {
    var id = idFrom("claimIdInput");
    if (!id) throw Object.assign(new Error("bad-id"), { code: "bad-id" });
    say($("triggerStatus"), "正在发送领取奖池份额。", "Sending claimShare.");
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
    if (act === "request-cabin") {
      say($("arkStatus"), "正在发送交易。", "Sending the transaction.");
      run = function () { return C.sendRequestCabin(id); };
    } else if (act === "apply-bag") {
      say($("arkStatus"), "正在发送交易。", "Sending the transaction.");
      run = function () { return C.sendApplyBag(id, board && board.dayIndex, board); };
    } else if (act === "claim-refund") {
      if (btn.disabled) return;
      var sale = btn.getAttribute("data-sale") || "legacy";
      if (sale === "new") {
        if (!board || !board.refundsOpen || board.opened || board.startTime === 0n) {
          say($("arkStatus"), explain("refund-not-ready"), explain("refund-not-ready"));
          return;
        }
        say($("arkStatus"), "正在发送领退款。", "Sending the refund claim.");
        run = function () { return C.sendRefundNew(id); };
      } else {
        if (!legacyRefund || legacyRefund.refundsClosed || !legacyRefund.refunding) {
          say($("arkStatus"), explain("refund-closed"), explain("refund-closed"));
          return;
        }
        say($("arkStatus"), "正在发送领退款。", "Sending the refund claim.");
        run = function () { return C.sendRefund(id); };
      }
    } else if (act === "buy-listing" || act === "cancel-listing" || act === "clean-listing" || act === "fill-bid" || act === "cancel-bid" || act === "refund-bid") {
      var book = btn.getAttribute("data-book") || payBook;
      var bidId = btn.getAttribute("data-bid") || id;
      var tokenId = btn.getAttribute("data-token");
      if (!tokenId && act === "fill-bid") {
        var fillInput = document.querySelector("[data-fill-for='" + bidId + "']");
        tokenId = fillInput ? String(fillInput.value || "").trim() : "";
      }
      var job = null;
      if (act === "buy-listing") job = doBuy(book, id);
      else if (act === "cancel-listing") {
        payBook = book;
        job = doCancelListing(id);
      }
      else if (act === "clean-listing") {
        payBook = book;
        job = doCleanListing(id);
      }
      else if (act === "fill-bid") job = doFill(bidId, tokenId);
      else if (act === "cancel-bid") job = doCancelBid(id);
      else job = doRefundBid(id);
      Promise.resolve(job).catch(function (e) {
        say($("marketStatus"), walletError(e), walletError(e));
      });
      return;
    } else return;
    Promise.resolve().then(run).then(function (hash) {
      return track(hash, $("arkStatus"));
    }).then(function () {
      if (act === "claim-refund" && $("walletInput") && String($("walletInput").value || "").trim()) {
        return lookup($("walletInput").value).catch(function () {
          say($("lookupNote"), "舱单暂时读不到。", "Tickets could not be read.");
        });
      }
    }).catch(function (e) {
      say($("arkStatus"), walletError(e), walletError(e));
    });
  });

  C.onWallet(function (addr) {
    account = addr || "";
    if ($("walletChip")) $("walletChip").textContent = account ? C.shortAddr(account) : "";
    renderTickets();
    renderMarket();
  });

  setLang(lang, false);
  renderMarket();
  initMarket();
  renderTickets();
  refresh().catch(function () {
    say($("statusRead"), "链上读取失败", "Chain read failed");
    say($("mintStatus"), "链上状态暂时读不到。铸造保持暂停，不会发送交易。", "Chain state could not be read. Mint stays paused and no transaction will be sent.");
    setBi($("mintBtn"), "铸造已暂停，等待开售", "Minting paused until the sale starts");
    $("mintBtn").disabled = true;
    $("mintBtn").classList.add("is-paused");
    C.readLegacyRefund().then(function (snap) {
      legacyRefund = snap;
      legacyAnchorMs = Date.now();
      renderOldRefund();
    }).catch(function () { renderOldRefund(); });
    loadMarket().catch(function () {});
  });
  setInterval(function () {
    paintOldClock();
    paintNewClocks();
    if (!legacyRefund || legacyRefund.refundsClosed || legacyRefund.refunding || legacyRefund.canEnableRefunds) return;
    if (!legacyRefund.opensAt || legacyNowSec() < legacyRefund.opensAt || legacyRechecked) return;
    legacyRechecked = true;
    C.readLegacyRefund().then(function (snap) {
      legacyRefund = snap;
      legacyAnchorMs = Date.now();
      renderOldRefund();
      if (board) renderActions();
      renderTickets();
    }).catch(function () {});
  }, 1000);
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
