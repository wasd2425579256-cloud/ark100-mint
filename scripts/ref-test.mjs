import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import {
  CHUNK_BLOCKS,
  MINTED_TOPIC,
  MINT_SELECTOR,
  NFT,
  SALE,
  TRANSFER_TOPIC,
  applyRatio,
  decodeMintCalldata,
  formatBps,
  formatWei,
  iterChunks,
  parseRatio
} from "./ref-report.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const refSrc = fs.readFileSync(path.join(root, "js/ref.js"), "utf8");
const chainSrc = fs.readFileSync(path.join(root, "js/chain.js"), "utf8");
const indexSrc = fs.readFileSync(path.join(root, "index.html"), "utf8");
const TTL = 30 * 24 * 60 * 60 * 1000;

function memoryStorage(seed) {
  const map = new Map();
  Object.keys(seed || {}).forEach(function (key) { map.set(key, seed[key]); });
  return {
    getItem(key) { return map.has(key) ? map.get(key) : null; },
    setItem(key, value) { map.set(String(key), String(value)); },
    removeItem(key) { map.delete(key); }
  };
}

function loadPage(storage, search) {
  const el = { hidden: true, textContent: "" };
  const window = {
    document: {
      getElementById(id) { return id === "refLine" ? el : null; }
    },
    location: { search: search || "" },
    localStorage: storage
  };
  window.window = window;
  const context = vm.createContext({
    window: window,
    document: window.document,
    localStorage: storage,
    location: window.location,
    console: console,
    TextEncoder: TextEncoder,
    TextDecoder: TextDecoder,
    URLSearchParams: URLSearchParams,
    Date: Date,
    fetch: function () { throw new Error("fetch is not used by the calldata test"); },
    AbortSignal: AbortSignal,
    setTimeout: setTimeout,
    clearTimeout: clearTimeout
  });
  vm.runInContext(refSrc, context, { filename: "js/ref.js" });
  vm.runInContext(chainSrc, context, { filename: "js/chain.js" });
  return { window: window, storage: storage, el: el, ArkRef: window.ArkRef, ArkChain: window.ArkChain };
}

function expectedCalldata(count, ref) {
  const head = MINT_SELECTOR + BigInt(count).toString(16).padStart(64, "0");
  if (!ref) return head;
  return head + Buffer.from("ARKREF:" + ref, "utf8").toString("hex");
}

test("sanitize keeps lowercase [a-z0-9_] of length 1..20", function () {
  const page = loadPage(memoryStorage(), "");
  const s = page.ArkRef.sanitize;
  assert.equal(s("AbC_12"), "abc_12");
  assert.equal(s("  Foo-Bar! "), "foobar");
  assert.equal(s("a"), "a");
  assert.equal(s("a".repeat(20)), "a".repeat(20));
  assert.equal(s("a".repeat(21)), "");
  assert.equal(s("!!!"), "");
  assert.equal(s(""), "");
  assert.equal(s(null), "");
  assert.equal(s(undefined), "");
});

test("first touch wins for 30 days and an expired ref is replaced", function () {
  const page = loadPage(memoryStorage(), "");
  const storage = memoryStorage();
  const now = 1_700_000_000_000;
  const first = page.ArkRef.capture(storage, "?utm=1&ref=Alpha_1", now);
  assert.equal(first.ref, "alpha_1");
  assert.equal(first.wrote, true);
  assert.equal(JSON.parse(storage.getItem("ark100_ref")).ts, now);

  const kept = page.ArkRef.capture(storage, "?ref=beta", now + TTL - 1);
  assert.equal(kept.ref, "alpha_1");
  assert.equal(kept.wrote, false);
  assert.equal(JSON.parse(storage.getItem("ark100_ref")).ts, now);

  const invalid = page.ArkRef.capture(storage, "?ref=!!!", now + 10);
  assert.equal(invalid.ref, "alpha_1");
  assert.equal(invalid.wrote, false);

  const expired = page.ArkRef.capture(storage, "?ref=Next_2", now + TTL);
  assert.equal(expired.ref, "next_2");
  assert.equal(expired.wrote, true);
  assert.equal(JSON.parse(storage.getItem("ark100_ref")).ts, now + TTL);
});

test("page load stores the ref and shows a muted line", function () {
  const storage = memoryStorage();
  const page = loadPage(storage, "?ref=Crew_9");
  assert.equal(page.ArkRef.current(), "crew_9");
  assert.equal(page.el.hidden, false);
  assert.equal(page.el.textContent, "ref: crew_9");
  const again = loadPage(storage, "?ref=other");
  assert.equal(again.ArkRef.current(), "crew_9");
  assert.equal(again.el.textContent, "ref: crew_9");
});

test("a page with no ref leaves the line hidden", function () {
  const page = loadPage(memoryStorage(), "");
  assert.equal(page.ArkRef.current(), "");
  assert.equal(page.ArkRef.tagSuffix(), "");
  assert.equal(page.el.hidden, true);
  assert.equal(page.el.textContent, "");
});

test("sale mint calldata carries the suffix and still matches isSaleMint", function () {
  const storage = memoryStorage();
  const page = loadPage(storage, "?ref=pilot_7");
  const data = page.ArkChain.saleMintCalldata(3);
  assert.equal(data, expectedCalldata(3, "pilot_7"));
  assert.equal(page.ArkChain.isSaleMint(page.ArkChain.ADDR.sale, data), true);
  assert.equal(page.ArkChain.isSaleMint(page.ArkChain.ADDR.legacySale, data), true);
  const decoded = decodeMintCalldata(data);
  assert.equal(decoded.count, 3n);
  assert.equal(decoded.ref, "pilot_7");
  assert.equal(data.indexOf(MINT_SELECTOR), 0);
  assert.equal(data.length, MINT_SELECTOR.length + 64 + Buffer.from("ARKREF:pilot_7", "utf8").length * 2);
});

test("no suffix without a ref, and a garbage suffix does not invent one", function () {
  const page = loadPage(memoryStorage(), "");
  const plain = page.ArkChain.saleMintCalldata(1);
  assert.equal(plain, expectedCalldata(1, ""));
  assert.equal(page.ArkChain.isSaleMint(SALE, plain), true);
  const decoded = decodeMintCalldata(plain);
  assert.equal(decoded.count, 1n);
  assert.equal(decoded.ref, "");

  const extra = plain + Buffer.from("ARKREF:pilot_7!", "utf8").toString("hex");
  assert.equal(decodeMintCalldata(extra).ref, "");
  assert.equal(decodeMintCalldata(extra).count, 1n);
  assert.equal(decodeMintCalldata("0xa0712d68"), null);
  assert.equal(decodeMintCalldata("0x1234"), null);
});

test("an expired stored ref is not appended", function () {
  const storage = memoryStorage({
    ark100_ref: JSON.stringify({ ref: "old_ref", ts: Date.now() - TTL - 1 })
  });
  const page = loadPage(storage, "");
  assert.equal(page.ArkRef.current(), "");
  assert.equal(page.ArkChain.saleMintCalldata(2), expectedCalldata(2, ""));
  assert.equal(page.el.hidden, true);
});

test("only the new-sale mint builder reads the referral tag", function () {
  const before = chainSrc.slice(0, chainSrc.indexOf("function saleMintCalldata"));
  const builder = chainSrc.slice(chainSrc.indexOf("function saleMintCalldata"), chainSrc.indexOf("async function sendMint"));
  assert.equal(before.includes("ArkRef"), false);
  assert.equal(builder.split("global.ArkRef").length - 1, 3);
  const sendMint = chainSrc.slice(chainSrc.indexOf("async function sendMint"), chainSrc.indexOf("async function sendOpenPool"));
  assert.match(sendMint, /var data = saleMintCalldata\(count\)/);
  assert.match(sendMint, /sendTx\(ADDR\.sale, data, q\.bnbDue\)/);
  assert.doesNotMatch(sendMint, /legacySale/);
  const otherSends = chainSrc.slice(chainSrc.indexOf("async function sendOpenPool"), chainSrc.indexOf("function onWallet"));
  assert.doesNotMatch(otherSends, /saleMintCalldata|ArkRef|ARKREF/);
  assert.match(otherSends, /ADDR\.legacySale/);
  assert.match(indexSrc, /<script src="js\/ref\.js"><\/script>\s*<script src="js\/chain\.js"><\/script>/);
  assert.match(chainSrc, /isSaleMint/);
  assert.match(chainSrc, new RegExp(MINTED_TOPIC));
});

test("report constants match the page and chunk the scan by 5000 blocks", function () {
  const page = loadPage(memoryStorage(), "");
  assert.equal(SALE.toLowerCase(), page.ArkChain.ADDR.sale.toLowerCase());
  assert.equal(NFT.toLowerCase(), page.ArkChain.ADDR.nft.toLowerCase());
  assert.equal(CHUNK_BLOCKS, 5000n);
  assert.equal(TRANSFER_TOPIC, "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef");
  assert.deepEqual(iterChunks(10n, 20n, 5n), [[10n, 14n], [15n, 19n], [20n, 20n]]);
  assert.deepEqual(iterChunks(1n, 5000n, 5000n), [[1n, 5000n]]);
  assert.deepEqual(iterChunks(1n, 5001n, 5000n), [[1n, 5000n], [5001n, 5001n]]);
  assert.deepEqual(iterChunks(5n, 4n, 5000n), []);
});

test("referrer payable is a floored share of team revenue", function () {
  const share = parseRatio("0.35", "--share");
  const team = parseRatio("0.2", "--team-ratio");
  const paid = 10n ** 18n;
  const teamWei = applyRatio(paid, team);
  const referrer = applyRatio(teamWei, share);
  assert.equal(teamWei, 200000000000000000n);
  assert.equal(referrer, 70000000000000000n);
  assert.equal(formatWei(referrer), "0.07");
  assert.equal(formatBps(2000n), "0.2");
  assert.equal(formatWei(0n), "0");
  assert.throws(function () { parseRatio("1.2", "--share"); }, /0 to 1/);
  assert.throws(function () { parseRatio("-0.1", "--team-ratio"); }, /0 to 1/);
});
