/* Referral capture for new-sale mints. Loaded on every page that loads chain.js.
   Named KOL codes stay 1–20 chars of [a-z0-9_]. A wallet invite is the full
   0x + 40 hex address: 20 characters of that alphabet cannot hold 20 bytes. */
(function (global) {
  var KEY = "ark100_ref";
  var TTL_MS = 30 * 24 * 60 * 60 * 1000;
  var TAG = "ARKREF:";
  /* Apex https://ark100.vip/ 301s to www and drops ?ref= on the root path. */
  var SITE = "https://www.ark100.vip";
  /* Fraction of the friend's ticket payment paid to an address referrer. */
  var PLAYER_REWARD = "0.05";
  var NAME_RE = /^[a-z0-9_]{1,20}$/;
  var ADDR_RE = /^0x[a-f0-9]{40}$/;

  function sanitize(raw) {
    if (raw == null) return "";
    var text = String(raw).trim();
    if (/^0x[0-9a-fA-F]{40}$/i.test(text)) return "0x" + text.slice(2).toLowerCase();
    if (/^[0-9a-fA-F]{40}$/.test(text)) return "0x" + text.toLowerCase();
    var cleaned = text.toLowerCase().replace(/[^a-z0-9_]/g, "");
    if (!NAME_RE.test(cleaned)) return "";
    return cleaned;
  }

  function isAddress(ref) {
    return ADDR_RE.test(String(ref || ""));
  }

  function sameAddress(a, b) {
    var left = sanitize(a);
    var right = sanitize(b);
    return isAddress(left) && left === right;
  }

  function buyerAddress() {
    try {
      var chain = global.ArkChain;
      if (chain && typeof chain.account === "function") return String(chain.account() || "");
    } catch (e) {}
    return "";
  }

  function readStored(storage, now) {
    if (!storage) return null;
    var raw = null;
    try { raw = storage.getItem(KEY); } catch (e) { return null; }
    if (!raw) return null;
    var obj = null;
    try { obj = JSON.parse(raw); } catch (e) { return null; }
    if (!obj || typeof obj.ref !== "string" || typeof obj.ts !== "number" || !isFinite(obj.ts)) return null;
    var ref = sanitize(obj.ref);
    if (!ref || ref !== obj.ref) return null;
    return { ref: ref, ts: obj.ts, expired: now - obj.ts >= TTL_MS };
  }

  function capture(storage, search, now) {
    var params = new URLSearchParams(String(search || ""));
    var incoming = sanitize(params.get("ref"));
    var stored = readStored(storage, now);
    var wrote = false;
    if (incoming && (!stored || stored.expired)) {
      try {
        storage.setItem(KEY, JSON.stringify({ ref: incoming, ts: now }));
        wrote = true;
        stored = { ref: incoming, ts: now, expired: false };
      } catch (e) {}
    }
    var active = stored && !stored.expired ? stored : null;
    return { ref: active ? active.ref : "", wrote: wrote, ts: active ? active.ts : null };
  }

  function utf8Hex(text) {
    var bytes = new TextEncoder().encode(text);
    var hex = "";
    for (var i = 0; i < bytes.length; i++) hex += bytes[i].toString(16).padStart(2, "0");
    return hex;
  }

  function tagSuffixFor(ref, buyer) {
    var clean = sanitize(ref);
    if (!clean) return "";
    var who = arguments.length > 1 ? buyer : buyerAddress();
    if (isAddress(clean) && sameAddress(clean, who)) return "";
    return utf8Hex(TAG + clean);
  }

  function storedRef(now) {
    var storage = null;
    try { storage = global.localStorage; } catch (e) { return ""; }
    var row = readStored(storage, now);
    return row && !row.expired ? row.ref : "";
  }

  function current() {
    return storedRef(Date.now());
  }

  function tagSuffix() {
    return tagSuffixFor(current());
  }

  function rewardPercentLabel(rateText) {
    var s = String(rateText == null ? PLAYER_REWARD : rateText).trim();
    var m = /^(\d+)(?:\.(\d+))?$/.exec(s);
    if (!m) return s;
    var frac = m[2] || "";
    var num = BigInt(m[1] + frac);
    var den = 10n ** BigInt(frac.length);
    var pct = num * 100n;
    var whole = pct / den;
    var rem = pct % den;
    if (rem === 0n) return whole.toString() + "%";
    var remStr = rem.toString().padStart(frac.length, "0").replace(/0+$/, "");
    return whole.toString() + "." + remStr + "%";
  }

  function rewardLine(lang) {
    var pct = rewardPercentLabel(PLAYER_REWARD);
    if (lang === "en") {
      return "Friends who mint through your link earn you " + pct + " of the ticket payment (settled weekly, BNB sent to your wallet).";
    }
    return "好友通过你的链接铸造，你可获得其票款的 " + pct + " 奖励（每周结算，BNB 发到你的钱包）";
  }

  function inviteLink(address) {
    var addr = sanitize(address);
    if (!isAddress(addr)) return "";
    return SITE + "/?ref=" + addr;
  }

  function shareText(link, lang) {
    var url = String(link || "");
    if (lang === "en") return "I boarded ARK100. Come aboard from here: " + url;
    return "我在 ARK100 上船了，从这里登船：" + url;
  }

  function shareIntent(link, lang) {
    return "https://x.com/intent/tweet?text=" + encodeURIComponent(shareText(link, lang));
  }

  function paint() {
    var doc = global.document;
    if (!doc || typeof doc.getElementById !== "function") return;
    var el = doc.getElementById("refLine");
    if (!el) return;
    var ref = current();
    if (!ref || (isAddress(ref) && sameAddress(ref, buyerAddress()))) {
      el.hidden = true;
      el.textContent = "";
      return;
    }
    el.hidden = false;
    el.textContent = "ref: " + ref;
  }

  function fillInvite(doc, address, lang) {
    if (!doc || typeof doc.getElementById !== "function") return "";
    var card = doc.getElementById("inviteCard");
    if (!card) return "";
    var link = inviteLink(address);
    var reward = doc.getElementById("inviteReward");
    var linkEl = doc.getElementById("inviteLink");
    var share = doc.getElementById("inviteShare");
    var status = doc.getElementById("inviteStatus");
    if (!link) {
      card.hidden = true;
      if (status) status.textContent = "";
      if (share) share.href = "https://x.com/intent/tweet";
      return "";
    }
    card.hidden = false;
    if (reward && typeof reward.querySelector === "function") {
      var zhEl = reward.querySelector(".t-zh");
      var enEl = reward.querySelector(".t-en");
      if (zhEl) zhEl.textContent = rewardLine("zh");
      if (enEl) enEl.textContent = rewardLine("en");
    }
    if (linkEl) linkEl.textContent = link;
    if (share) share.href = shareIntent(link, lang === "en" ? "en" : "zh");
    return link;
  }

  function boot() {
    var search = "";
    try { search = (global.location && global.location.search) || ""; } catch (e) {}
    var storage = null;
    try { storage = global.localStorage; } catch (e) {}
    if (storage) capture(storage, search, Date.now());
    paint();
    return current();
  }

  global.ArkRef = {
    KEY: KEY,
    TTL_MS: TTL_MS,
    TAG: TAG,
    SITE: SITE,
    PLAYER_REWARD: PLAYER_REWARD,
    sanitize: sanitize,
    isAddress: isAddress,
    sameAddress: sameAddress,
    capture: capture,
    readStored: readStored,
    tagSuffixFor: tagSuffixFor,
    tagSuffix: tagSuffix,
    current: current,
    rewardPercentLabel: rewardPercentLabel,
    rewardLine: rewardLine,
    inviteLink: inviteLink,
    shareText: shareText,
    shareIntent: shareIntent,
    paint: paint,
    fillInvite: fillInvite,
    boot: boot
  };

  try { boot(); } catch (e) {}
})(typeof window !== "undefined" ? window : globalThis);
