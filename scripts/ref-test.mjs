import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import {
  CHUNK_BLOCKS,
  DEFAULT_PLAYER_REWARD,
  MINTED_TOPIC,
  MINT_SELECTOR,
  NFT,
  SALE,
  TRANSFER_TOPIC,
  applyRatio,
  classifyRef,
  decodeMintCalldata,
  foldMints,
  formatBps,
  formatWei,
  isSelfReferral,
  iterChunks,
  parseRatio,
  payoutOf
} from "./ref-report.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const refSrc = fs.readFileSync(path.join(root, "js/ref.js"), "utf8");
const chainSrc = fs.readFileSync(path.join(root, "js/chain.js"), "utf8");
const indexSrc = fs.readFileSync(path.join(root, "index.html"), "utf8");
const appSrc = fs.readFileSync(path.join(root, "js/app.js"), "utf8");
const ADDR = "0x" + "ab".repeat(20);
const OTHER = "0x" + "cd".repeat(20);
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

test("sanitize accepts a full address and still caps names at 20", function () {
  const page = loadPage(memoryStorage(), "");
  const s = page.ArkRef.sanitize;
  const mixed = "0x" + "Ab".repeat(20);
  assert.equal(s(mixed), ADDR);
  assert.equal(s("  " + mixed.toUpperCase() + "  "), ADDR);
  assert.equal(s("AB".repeat(20)), ADDR);
  assert.equal(s("0xabc"), "0xabc");
  assert.equal(s("0x" + "ab".repeat(19)), "");
  assert.equal(s("0x" + "zz".repeat(20)), "");
  assert.equal(s("a".repeat(21)), "");
  assert.equal(page.ArkRef.isAddress(ADDR), true);
  assert.equal(page.ArkRef.isAddress("pilot_7"), false);
});

test("an address ref keeps first touch for 30 days", function () {
  const page = loadPage(memoryStorage(), "");
  const storage = memoryStorage();
  const now = 1_700_000_000_000;
  const first = page.ArkRef.capture(storage, "?ref=" + ("0x" + "Ab".repeat(20)), now);
  assert.equal(first.ref, ADDR);
  assert.equal(first.wrote, true);
  const kept = page.ArkRef.capture(storage, "?ref=beta", now + TTL - 1);
  assert.equal(kept.ref, ADDR);
  assert.equal(kept.wrote, false);
  const replaced = page.ArkRef.capture(storage, "?ref=Next_2", now + TTL);
  assert.equal(replaced.ref, "next_2");
  assert.equal(replaced.wrote, true);
});

test("address calldata is only a trailing tag and decodes back to the full address", function () {
  const storage = memoryStorage();
  const page = loadPage(storage, "?ref=" + ADDR);
  const data = page.ArkChain.saleMintCalldata(3);
  const head = expectedCalldata(3, "");
  assert.equal(data.slice(0, head.length), head);
  assert.equal(data, expectedCalldata(3, ADDR));
  assert.equal(page.ArkChain.isSaleMint(page.ArkChain.ADDR.sale, data), true);
  const decoded = decodeMintCalldata(data);
  assert.equal(decoded.count, 3n);
  assert.equal(decoded.ref, ADDR);
  assert.equal(decoded.kind, "address");
  const upperBody = "ARKREF:" + "0x" + "AB".repeat(20);
  const upper = head + Buffer.from(upperBody, "utf8").toString("hex");
  assert.equal(decodeMintCalldata(upper).ref, ADDR);
  const bare = head + Buffer.from("ARKREF:" + "ab".repeat(20), "utf8").toString("hex");
  assert.equal(decodeMintCalldata(bare).ref, ADDR);
  const short = head + Buffer.from("ARKREF:0x" + "ab".repeat(19), "utf8").toString("hex");
  assert.equal(decodeMintCalldata(short).ref, "");
});

test("a self-referral is not tagged and a different buyer still is", function () {
  const storage = memoryStorage();
  const page = loadPage(storage, "?ref=" + ("0x" + "AB".repeat(20)));
  assert.equal(page.ArkRef.current(), ADDR);
  assert.equal(page.el.hidden, false);
  assert.equal(page.el.textContent, "ref: " + ADDR);
  page.ArkChain.account = function () { return "0x" + "AB".repeat(20); };
  page.ArkRef.paint();
  assert.equal(page.el.hidden, true);
  assert.equal(page.ArkChain.saleMintCalldata(1), expectedCalldata(1, ""));
  page.ArkChain.account = function () { return "0x" + "CD".repeat(20); };
  page.ArkRef.paint();
  assert.equal(page.el.textContent, "ref: " + ADDR);
  const data = page.ArkChain.saleMintCalldata(2);
  assert.equal(data, expectedCalldata(2, ADDR));
  assert.equal(decodeMintCalldata(data).ref, ADDR);
  assert.equal(isSelfReferral("0x" + "AB".repeat(20), ADDR), true);
  assert.equal(isSelfReferral(OTHER, ADDR), false);
  assert.equal(isSelfReferral(ADDR, "pilot_7"), false);
});

test("a connected wallet does not strip a named ref", function () {
  const page = loadPage(memoryStorage(), "?ref=Pilot_7");
  page.ArkChain.account = function () { return ADDR; };
  assert.equal(page.ArkChain.saleMintCalldata(1), expectedCalldata(1, "pilot_7"));
  assert.equal(page.el.textContent, "ref: pilot_7");
});

test("player reward is one constant and the invite copy uses it", function () {
  const page = loadPage(memoryStorage(), "");
  assert.equal(page.ArkRef.PLAYER_REWARD, "0.05");
  assert.equal(DEFAULT_PLAYER_REWARD, page.ArkRef.PLAYER_REWARD);
  assert.equal(page.ArkRef.rewardPercentLabel(), "5%");
  assert.equal(page.ArkRef.rewardPercentLabel("0.125"), "12.5%");
  assert.equal(
    page.ArkRef.rewardLine("zh"),
    "好友通过你的链接铸造，你可获得其票款的 5% 奖励（每周结算，BNB 发到你的钱包）"
  );
  const link = page.ArkRef.inviteLink("0x" + "AB".repeat(20));
  assert.equal(link, "https://ark100.vip/?ref=" + ADDR);
  assert.equal(page.ArkRef.inviteLink("pilot_7"), "");
  const text = page.ArkRef.shareText(link, "zh");
  assert.match(text, new RegExp(ADDR));
  ["价格", "赌", "暴富", "稳赚", "翻倍", "梭哈", "财富", "空投", "保本"].forEach(function (word) {
    assert.equal(text.includes(word), false, word);
  });
  const intent = page.ArkRef.shareIntent(link, "zh");
  assert.equal(intent.indexOf("https://x.com/intent/tweet?text="), 0);
  assert.match(decodeURIComponent(intent), /我在 ARK100 上船了/);
  const nodes = {};
  function make(id) {
    const node = { hidden: true, textContent: "", href: "", kids: {} };
    node.querySelector = function (sel) {
      const key = sel === ".t-zh" ? "zh" : "en";
      if (!node.kids[key]) node.kids[key] = { textContent: "" };
      return node.kids[key];
    };
    nodes[id] = node;
    return node;
  }
  ["inviteCard", "inviteReward", "inviteLink", "inviteShare", "inviteStatus"].forEach(make);
  const doc = { getElementById: function (id) { return nodes[id] || null; } };
  assert.equal(page.ArkRef.fillInvite(doc, "", "zh"), "");
  assert.equal(nodes.inviteCard.hidden, true);
  assert.equal(page.ArkRef.fillInvite(doc, ADDR, "zh"), link);
  assert.equal(nodes.inviteCard.hidden, false);
  assert.equal(nodes.inviteLink.textContent, link);
  assert.equal(nodes.inviteReward.kids.zh.textContent, page.ArkRef.rewardLine("zh"));
  assert.match(nodes.inviteShare.href, /^https:\/\/x\.com\/intent\/tweet\?text=/);
  assert.match(indexSrc, /id="inviteCard"/);
  assert.match(indexSrc, /邀请好友上船/);
  assert.match(indexSrc, /id="inviteCopy"/);
  assert.match(indexSrc, /id="inviteShare"/);
  assert.match(appSrc, /ArkRef\.fillInvite/);
  assert.match(appSrc, /ArkRef\.inviteLink/);
  assert.match(appSrc, /inviteCopy/);
});

test("address payout is 5% of payment and named KOLs stay on the team share", function () {
  const share = parseRatio("0.35", "--share");
  const team = parseRatio("0.2", "--team-ratio");
  const player = parseRatio(DEFAULT_PLAYER_REWARD, "--player-reward");
  const paid = 10n ** 18n;
  const folded = foldMints([
    { from: OTHER, ref: "pilot_7", tickets: 2n, wei: paid },
    { from: OTHER, ref: "0x" + "AB".repeat(20), tickets: 4n, wei: paid * 2n },
    { from: "0x" + "AB".repeat(20), ref: ADDR, tickets: 1n, wei: paid },
    { from: OTHER, ref: "", tickets: 1n, wei: 5n * 10n ** 17n }
  ], team, share, player);
  const byRef = {};
  folded.rows.forEach(function (row) { byRef[row.ref] = row; });
  assert.equal(byRef.pilot_7.kind, "name");
  assert.equal(byRef.pilot_7.tickets, 2n);
  assert.equal(byRef.pilot_7.payoutWei, 70000000000000000n);
  assert.equal(byRef.pilot_7.payable, "");
  assert.equal(payoutOf("name", paid, team, share, player), 70000000000000000n);
  assert.equal(byRef[ADDR].kind, "address");
  assert.equal(byRef[ADDR].tickets, 4n);
  assert.equal(byRef[ADDR].wei, 2n * paid);
  assert.equal(byRef[ADDR].payoutWei, applyRatio(2n * paid, player));
  assert.equal(formatWei(byRef[ADDR].payoutWei), "0.1");
  assert.equal(byRef[ADDR].payable, ADDR);
  assert.equal(byRef["(self)"].kind, "self");
  assert.equal(byRef["(self)"].tickets, 1n);
  assert.equal(byRef["(self)"].wei, paid);
  assert.equal(byRef["(self)"].payoutWei, 0n);
  assert.equal(byRef["(self)"].payable, "");
  assert.equal(byRef["(none)"].tickets, 1n);
  assert.equal(byRef["(none)"].payoutWei, 0n);
  assert.equal(folded.payable.length, 1);
  assert.equal(folded.payable[0].ref, ADDR);
  assert.equal(classifyRef(ADDR), "address");
  assert.equal(classifyRef("pilot_7"), "name");

  const open = foldMints([
    { from: OTHER, ref: "pilot_7", tickets: 1n, wei: paid },
    { from: OTHER, ref: ADDR, tickets: 1n, wei: paid }
  ], null, share, player);
  const openBy = {};
  open.rows.forEach(function (row) { openBy[row.ref] = row; });
  assert.equal(openBy.pilot_7.payoutWei, null);
  assert.equal(openBy.pilot_7.teamWei, null);
  assert.equal(openBy[ADDR].payoutWei, 50000000000000000n);
  assert.equal(formatWei(openBy[ADDR].payoutWei), "0.05");
});
