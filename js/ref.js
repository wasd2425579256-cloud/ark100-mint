/* Referral capture for new-sale mints. Loaded on every page that loads chain.js. */
(function (global) {
  var KEY = "ark100_ref";
  var TTL_MS = 30 * 24 * 60 * 60 * 1000;
  var TAG = "ARKREF:";

  function sanitize(raw) {
    if (raw == null) return "";
    var cleaned = String(raw).toLowerCase().replace(/[^a-z0-9_]/g, "");
    if (cleaned.length < 1 || cleaned.length > 20) return "";
    return cleaned;
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

  function tagSuffixFor(ref) {
    var clean = sanitize(ref);
    if (!clean) return "";
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

  function paint() {
    var doc = global.document;
    if (!doc || typeof doc.getElementById !== "function") return;
    var el = doc.getElementById("refLine");
    if (!el) return;
    var ref = current();
    if (!ref) {
      el.hidden = true;
      el.textContent = "";
      return;
    }
    el.hidden = false;
    el.textContent = "ref: " + ref;
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
    sanitize: sanitize,
    capture: capture,
    readStored: readStored,
    tagSuffixFor: tagSuffixFor,
    tagSuffix: tagSuffix,
    current: current,
    paint: paint,
    boot: boot
  };

  try { boot(); } catch (e) {}
})(typeof window !== "undefined" ? window : globalThis);
