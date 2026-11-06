#!/usr/bin/env node
/**
 * Scan ArkSale mint(uint256) transactions for a trailing ARKREF: tag.
 *
 *   node scripts/ref-report.mjs [--from-block N] [--to-block N]
 *       [--share 0.35] [--team-ratio 0.2] [--out file.csv]
 *
 * RPC defaults to https://bsc-dataseed.binance.org. Override with env RPC
 * or --rpc. That host rejects eth_getLogs, so log queries fall back to
 * https://bsc.publicnode.com and then https://bsc-rpc.publicnode.com
 * (the same log endpoints js/chain.js uses). No dependencies. Node 18+.
 *
 * Referrer payable is a cut of team revenue, not of gross BNB:
 *   team_bnb = floor(bnb_paid * team_ratio)
 *   referrer_bnb = floor(team_bnb * share)
 * team_ratio is ArkSale.TEAM_BPS() / 10000 unless --team-ratio is passed.
 * If that view cannot be read and --team-ratio is omitted, the summary
 * prints team_ratio REQUIRED and leaves the payable columns blank.
 */
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export const SALE = "0x64a67c2D48898D414DbD63F56deAbD0988C2Af65";
export const NFT = "0xDF2aF96477aBe8E5Eaa9Cf79650D58917e6c3490";
export const MINT_SELECTOR = "0xa0712d68";
export const START_TIMESTAMP = 1793880000n;
export const DEFAULT_RPC = "https://bsc-dataseed.binance.org";
export const DEFAULT_SHARE = "0.35";
export const CHUNK_BLOCKS = 5000n;
/** ArkSale Minted(address,uint256,uint256,uint256,string). Same topic as js/chain.js "minted". */
export const MINTED_TOPIC = "0xd8b419dcb55349414000518e58bc0ec29a3419a418cc9ab706cd9db1260cb2f4";
/** ERC-721 Transfer(address,address,uint256). Fallback: TicketNFT mints come from 0x0. */
export const TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
const ZERO_TOPIC = "0x" + "0".repeat(64);
const TEAM_BPS_DATA = "0xd5861d91";
const SOLD_DATA = "0x02c7e7af";
const TAG = "ARKREF:";
const LOG_FALLBACKS = [
  "https://bsc.publicnode.com",
  "https://bsc-rpc.publicnode.com"
];

let rpcUrl = process.env.RPC || DEFAULT_RPC;
let logRpc = "";

export function parseRatio(input, name) {
  const s = String(input).trim();
  if (!/^\d+(\.\d+)?$/.test(s)) throw new Error(name + " must be a decimal fraction from 0 to 1");
  const parts = s.split(".");
  const frac = parts[1] || "";
  const num = BigInt(parts[0] + frac);
  const den = 10n ** BigInt(frac.length);
  if (num > den) throw new Error(name + " must be from 0 to 1");
  return { num: num, den: den, text: s };
}

export function applyRatio(wei, ratio) {
  return (BigInt(wei) * ratio.num) / ratio.den;
}

export function formatWei(wei) {
  const v = BigInt(wei);
  const neg = v < 0n;
  const x = neg ? -v : v;
  const s = x.toString().padStart(19, "0");
  const whole = s.slice(0, -18).replace(/^0+(?=\d)/, "");
  const frac = s.slice(-18).replace(/0+$/, "");
  const text = frac ? whole + "." + frac : whole;
  return neg ? "-" + text : text;
}

export function formatBps(bps) {
  const v = BigInt(bps);
  const whole = v / 10000n;
  const rem = v % 10000n;
  if (rem === 0n) return whole.toString();
  const frac = rem.toString().padStart(4, "0").replace(/0+$/, "");
  return whole.toString() + "." + frac;
}

export function iterChunks(from, to, size) {
  const step = size == null ? CHUNK_BLOCKS : BigInt(size);
  if (step <= 0n) throw new Error("chunk size must be positive");
  const start0 = BigInt(from);
  const end0 = BigInt(to);
  const out = [];
  if (start0 > end0) return out;
  for (let s = start0; s <= end0; s += step) {
    let e = s + step - 1n;
    if (e > end0) e = end0;
    out.push([s, e]);
  }
  return out;
}

export function decodeMintCalldata(input) {
  let hex = String(input || "").toLowerCase();
  if (hex.startsWith("0x")) hex = hex.slice(2);
  if (!hex.startsWith(MINT_SELECTOR.slice(2))) return null;
  if (hex.length < 8 + 64 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/.test(hex)) return null;
  const count = BigInt("0x" + hex.slice(8, 72));
  const trail = hex.slice(72);
  let ref = "";
  if (trail.length) {
    const text = Buffer.from(trail, "hex").toString("utf8");
    if (Buffer.from(text, "utf8").toString("hex") === trail && text.startsWith(TAG)) {
      const body = text.slice(TAG.length);
      if (/^[a-z0-9_]{1,20}$/.test(body) && text === TAG + body) ref = body;
    }
  }
  return { count: count, ref: ref };
}

function hexBlock(n) {
  return "0x" + BigInt(n).toString(16);
}

function sleep(ms) {
  return new Promise(function (resolve) { setTimeout(resolve, ms); });
}

function logEndpoints() {
  const list = [rpcUrl].concat(LOG_FALLBACKS);
  const seen = new Set();
  const out = [];
  list.forEach(function (url) {
    const key = String(url || "").replace(/\/$/, "");
    if (!key || seen.has(key)) return;
    seen.add(key);
    out.push(key);
  });
  return out;
}

async function rpcOnce(url, method, params) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: method, params: params })
  });
  const text = await res.text();
  if (res.status === 429 || res.status >= 500) {
    const err = new Error(method + ": HTTP " + res.status);
    err.retry = true;
    throw err;
  }
  let data;
  try { data = JSON.parse(text); } catch (e) {
    const err = new Error(method + ": bad json");
    err.retry = true;
    throw err;
  }
  if (data.error) {
    const message = data.error.message || JSON.stringify(data.error);
    const err = new Error(method + ": " + message);
    err.code = data.error.code;
    err.permanent = data.error.code === -32005 || /limit exceeded/i.test(message);
    err.range = /range|too many|more than|response size|query returned|exceed maximum/i.test(message);
    throw err;
  }
  return data.result;
}

async function rpc(method, params) {
  let last = "unknown";
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      return await rpcOnce(rpcUrl, method, params);
    } catch (e) {
      last = e && e.message ? e.message : String(e);
      if (!e.retry && !/timeout|temporar|busy|header not found|rate/i.test(last)) throw e;
      await sleep(300 * (attempt + 1));
    }
  }
  throw new Error(method + " failed: " + last);
}

async function getLogsOnce(filter) {
  const urls = logRpc ? [logRpc] : logEndpoints();
  let last;
  for (let i = 0; i < urls.length; i++) {
    const url = urls[i];
    try {
      const result = await rpcOnce(url, "eth_getLogs", [filter]);
      if (!Array.isArray(result)) throw new Error("eth_getLogs did not return an array");
      if (logRpc !== url) {
        process.stderr.write("eth_getLogs endpoint: " + url + "\n");
        logRpc = url;
      }
      return result;
    } catch (e) {
      last = e;
      const msg = e && e.message ? e.message : String(e);
      if (logRpc === url) throw e;
      if (e.permanent || /limit exceeded|method not found|not supported|not available/i.test(msg)) {
        process.stderr.write("eth_getLogs on " + url + " rejected (" + msg + ").\n");
        continue;
      }
      throw e;
    }
  }
  throw last;
}

function decodeWord(hex) {
  const h = String(hex || "0x").replace(/^0x/, "");
  if (!h) return 0n;
  return BigInt("0x" + h.slice(0, 64));
}

async function blockTimestamp(n) {
  const block = await rpc("eth_getBlockByNumber", [hexBlock(n), false]);
  if (!block || block.timestamp == null) throw new Error("missing block " + n.toString());
  return BigInt(block.timestamp);
}

export async function findStartBlock(targetTs) {
  const latest = BigInt(await rpc("eth_blockNumber", []));
  const target = BigInt(targetTs);
  const hiTs = await blockTimestamp(latest);
  if (hiTs < target) return { from: latest + 1n, to: latest, latest: latest };
  let lo = 0n;
  let hi = latest;
  while (lo < hi) {
    const mid = (lo + hi) / 2n;
    const ts = await blockTimestamp(mid);
    if (ts >= target) hi = mid;
    else lo = mid + 1n;
  }
  return { from: lo, to: latest, latest: latest };
}

async function getLogsRange(filter, from, to) {
  const query = Object.assign({}, filter, {
    fromBlock: hexBlock(from),
    toBlock: hexBlock(to)
  });
  try {
    return await getLogsOnce(query);
  } catch (e) {
    const span = to - from;
    if (span <= 0n || !e.range) throw e;
    const mid = from + span / 2n;
    const left = await getLogsRange(filter, from, mid);
    const right = await getLogsRange(filter, mid + 1n, to);
    return left.concat(right);
  }
}

async function getLogsChunked(filter, from, to) {
  const logs = [];
  const chunks = iterChunks(from, to, CHUNK_BLOCKS);
  for (let i = 0; i < chunks.length; i++) {
    const start = chunks[i][0];
    const end = chunks[i][1];
    const batch = await getLogsRange(filter, start, end);
    logs.push.apply(logs, batch);
    process.stderr.write("logs " + start.toString() + ".." + end.toString() + " +" + batch.length + "\n");
  }
  return logs;
}

function logOrder(a, b) {
  const blockDelta = BigInt(a.blockNumber) - BigInt(b.blockNumber);
  if (blockDelta !== 0n) return blockDelta < 0n ? -1 : 1;
  const ai = a.logIndex == null ? 0n : BigInt(a.logIndex);
  const bi = b.logIndex == null ? 0n : BigInt(b.logIndex);
  if (ai === bi) return 0;
  return ai < bi ? -1 : 1;
}

function uniqueHashes(logs) {
  const sorted = logs.slice().sort(logOrder);
  const seen = new Set();
  const hashes = [];
  for (let i = 0; i < sorted.length; i++) {
    const hash = sorted[i].transactionHash;
    if (!hash || seen.has(hash)) continue;
    seen.add(hash);
    hashes.push(hash);
  }
  return hashes;
}

async function collectHashes(from, to) {
  const mintedFilter = { address: SALE, topics: [MINTED_TOPIC] };
  try {
    const logs = await getLogsChunked(mintedFilter, from, to);
    return { source: "ArkSale.Minted", hashes: uniqueHashes(logs) };
  } catch (e) {
    process.stderr.write("Minted logs unavailable (" + (e && e.message ? e.message : e) + "). Falling back to TicketNFT Transfer from 0x0.\n");
    const logs = await getLogsChunked({
      address: NFT,
      topics: [TRANSFER_TOPIC, ZERO_TOPIC]
    }, from, to);
    return { source: "TicketNFT.Transfer(from=0x0)", hashes: uniqueHashes(logs) };
  }
}

async function mapPool(items, limit, fn) {
  const out = new Array(items.length);
  let cursor = 0;
  async function worker() {
    while (cursor < items.length) {
      const i = cursor++;
      out[i] = await fn(items[i], i);
    }
  }
  const n = Math.min(limit, items.length);
  const jobs = [];
  for (let i = 0; i < n; i++) jobs.push(worker());
  await Promise.all(jobs);
  return out;
}

function csvCell(value) {
  const s = String(value);
  if (/[",\n]/.test(s)) return '"' + s.replace(/"/g, '""') + '"';
  return s;
}

function csvRow(cols) {
  return cols.map(csvCell).join(",") + "\n";
}

async function readOptionalUint(data) {
  try {
    const raw = await rpc("eth_call", [{ to: SALE, data: data }, "latest"]);
    return decodeWord(raw);
  } catch (e) {
    return null;
  }
}

async function resolveTeamRatio(flag) {
  const onChain = await readOptionalUint(TEAM_BPS_DATA);
  if (flag != null) {
    const ratio = parseRatio(flag, "--team-ratio");
    return {
      ratio: ratio,
      required: false,
      note: "team_ratio " + ratio.text + " from --team-ratio"
        + (onChain == null ? "" : " (ArkSale.TEAM_BPS() = " + onChain.toString() + ", " + formatBps(onChain) + " of BNB)")
    };
  }
  if (onChain == null || onChain > 10000n) {
    return {
      ratio: null,
      required: true,
      note: "team_ratio REQUIRED. Pass --team-ratio, the fraction of BNB paid that is team revenue. Read ArkSale.TEAM_BPS() via eth_call to " + SALE + " data " + TEAM_BPS_DATA + " and divide by 10000. This run did not use a guessed ratio."
    };
  }
  return {
    ratio: { num: onChain, den: 10000n, text: formatBps(onChain) },
    required: false,
    note: "team_ratio " + formatBps(onChain) + " from ArkSale.TEAM_BPS() = " + onChain.toString() + " / 10000"
  };
}

function addGroup(groups, ref, tickets, wei) {
  const key = ref || "(none)";
  let row = groups.get(key);
  if (!row) {
    row = { ref: key, txs: 0n, tickets: 0n, wei: 0n };
    groups.set(key, row);
  }
  row.txs += 1n;
  row.tickets += tickets;
  row.wei += wei;
}

function summaryText(meta, groups, team, share) {
  const lines = [];
  lines.push("sale: " + SALE);
  lines.push("event: " + meta.source);
  lines.push("blocks: " + meta.from.toString() + " .. " + meta.to.toString());
  lines.push("direct mint txs: " + meta.rows.length);
  lines.push("skipped (not a direct mint(uint256) to ArkSale): " + meta.skipped);
  if (meta.missing) lines.push("missing transactions: " + meta.missing);
  if (meta.sold != null) lines.push("ArkSale.sold() now: " + meta.sold.toString() + " (refunds lower this; the scan counts historical mints)");
  lines.push("share: " + share.text);
  lines.push(team.note);
  lines.push("referrer_bnb = floor(team_bnb * share), team_bnb = floor(bnb_paid * team_ratio)");
  lines.push("team revenue is the TEAM_BPS leg. Before the pool opens it sits in teamDue and is paid to projectWallet at openPool. After open, each mint pays that leg immediately. POT_BPS (15%) is not part of the referral base.");
  lines.push("bnb_paid is the transaction value. The contract refunds msg.value above the quote before the split, so an overpay is larger than the BNB that is actually divided. Site mints send the quoted amount.");
  lines.push("");
  const header = ["ref", "txs", "tickets", "bnb_paid", "team_bnb", "referrer_bnb"];
  lines.push(header.join(","));
  const named = [];
  let none = null;
  groups.forEach(function (row) {
    if (row.ref === "(none)") none = row;
    else named.push(row);
  });
  named.sort(function (a, b) { return a.ref < b.ref ? -1 : a.ref > b.ref ? 1 : 0; });
  if (none) named.push(none);
  let txs = 0n;
  let tickets = 0n;
  let wei = 0n;
  let teamWei = 0n;
  let refWei = 0n;
  function money(v) {
    return team.ratio ? formatWei(v) : "";
  }
  named.forEach(function (row) {
    const teamPart = team.ratio ? applyRatio(row.wei, team.ratio) : 0n;
    const refPart = team.ratio ? applyRatio(teamPart, share) : 0n;
    txs += row.txs;
    tickets += row.tickets;
    wei += row.wei;
    teamWei += teamPart;
    refWei += refPart;
    lines.push([row.ref, row.txs.toString(), row.tickets.toString(), formatWei(row.wei), money(teamPart), money(refPart)].join(","));
  });
  lines.push(["TOTAL", txs.toString(), tickets.toString(), formatWei(wei), money(teamWei), money(refWei)].join(","));
  return lines.join("\n") + "\n";
}

function parseArgs(argv) {
  const out = {
    share: DEFAULT_SHARE,
    teamRatio: null,
    fromBlock: null,
    toBlock: null,
    out: null,
    rpc: process.env.RPC || DEFAULT_RPC,
    help: false
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    function next() {
      if (i + 1 >= argv.length) throw new Error("missing value for " + a);
      i += 1;
      return argv[i];
    }
    if (a === "--share") out.share = next();
    else if (a === "--team-ratio") out.teamRatio = next();
    else if (a === "--from-block") out.fromBlock = next();
    else if (a === "--to-block") out.toBlock = next();
    else if (a === "--out") out.out = next();
    else if (a === "--rpc") out.rpc = next();
    else if (a === "--help" || a === "-h") out.help = true;
    else throw new Error("unknown argument " + a);
  }
  return out;
}

function parseBlock(v, name) {
  const s = String(v).trim();
  if (!/^(0x[0-9a-fA-F]+|\d+)$/.test(s)) throw new Error(name + " must be an integer block number");
  return BigInt(s);
}

function helpText() {
  return [
    "Usage: node scripts/ref-report.mjs [options]",
    "",
    "Scan ArkSale " + SALE + " for successful direct mint(uint256) calls",
    "and group them by the trailing ARKREF: tag. Untagged rows are (none).",
    "",
    "Options:",
    "  --from-block N   First block. Default: first block with timestamp >= " + START_TIMESTAMP.toString(),
    "                   (ArkSale startTime, 2026-11-05 20:00 Asia/Shanghai), via binary search.",
    "  --to-block N     Last block. Default: latest.",
    "  --share F        Referrer share of team revenue. Default " + DEFAULT_SHARE + ". Fraction from 0 to 1.",
    "  --team-ratio F   Fraction of BNB paid that is team revenue. Default: TEAM_BPS()/10000",
    "                   when that eth_call succeeds. Otherwise REQUIRED (no guessed payout).",
    "  --rpc URL        JSON-RPC URL. Overrides env RPC. Default " + DEFAULT_RPC + ".",
    "                   eth_getLogs falls back to bsc.publicnode.com when the RPC",
    "                   rejects logs (bsc-dataseed returns -32005).",
    "  --out FILE       Write the transaction CSV here. Default: CSV on stdout, summary on stderr.",
    "",
    "Team ratio: eth_call " + SALE + " data " + TEAM_BPS_DATA + "  (TEAM_BPS()).",
    "Divide the uint256 by 10000. The source constant is 2000, so the fraction is 0.2.",
    "POT_BPS is 1500 and is not the referral base. Pre-open, the team leg accrues in teamDue",
    "and is paid at openPool. Post-open, mint pays projectWallet immediately.",
    ""
  ].join("\n");
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    process.stdout.write(helpText());
    return;
  }
  rpcUrl = args.rpc || DEFAULT_RPC;
  const share = parseRatio(args.share, "--share");
  let from;
  let to;
  if (args.fromBlock == null) {
    const found = await findStartBlock(START_TIMESTAMP);
    from = found.from;
    to = args.toBlock == null ? found.to : parseBlock(args.toBlock, "--to-block");
    process.stderr.write("start block " + from.toString() + " (timestamp >= " + START_TIMESTAMP.toString() + "), latest " + found.latest.toString() + "\n");
  } else {
    from = parseBlock(args.fromBlock, "--from-block");
    if (args.toBlock == null) to = BigInt(await rpc("eth_blockNumber", []));
    else to = parseBlock(args.toBlock, "--to-block");
  }
  if (from > to) throw new Error("from-block " + from.toString() + " is after to-block " + to.toString());

  const collected = await collectHashes(from, to);
  process.stderr.write(collected.source + " unique txs: " + collected.hashes.length + "\n");
  const txs = await mapPool(collected.hashes, 4, function (hash) {
    return rpc("eth_getTransactionByHash", [hash]);
  });

  const groups = new Map();
  const rows = [];
  let skipped = 0;
  let missing = 0;
  for (let i = 0; i < txs.length; i++) {
    const tx = txs[i];
    if (!tx) {
      missing += 1;
      continue;
    }
    const toAddr = String(tx.to || "").toLowerCase();
    if (toAddr !== SALE.toLowerCase()) {
      skipped += 1;
      continue;
    }
    const decoded = decodeMintCalldata(tx.input || "0x");
    if (!decoded) {
      skipped += 1;
      continue;
    }
    const value = BigInt(tx.value || "0x0");
    const ref = decoded.ref || "(none)";
    addGroup(groups, decoded.ref, decoded.count, value);
    rows.push({
      hash: tx.hash,
      block: BigInt(tx.blockNumber || "0x0"),
      from: tx.from || "",
      tickets: decoded.count,
      value: value,
      ref: ref
    });
  }
  rows.sort(function (a, b) {
    if (a.block === b.block) return a.hash < b.hash ? -1 : a.hash > b.hash ? 1 : 0;
    return a.block < b.block ? -1 : 1;
  });

  let csv = csvRow(["hash", "block", "from", "tickets", "value_wei", "bnb_paid", "ref"]);
  rows.forEach(function (row) {
    csv += csvRow([
      row.hash,
      row.block.toString(),
      row.from,
      row.tickets.toString(),
      row.value.toString(),
      formatWei(row.value),
      row.ref
    ]);
  });

  const team = await resolveTeamRatio(args.teamRatio);
  const sold = await readOptionalUint(SOLD_DATA);
  const text = summaryText({
    source: collected.source,
    from: from,
    to: to,
    rows: rows,
    skipped: skipped,
    missing: missing,
    sold: sold
  }, groups, team, share);

  if (args.out) {
    const file = path.resolve(args.out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, csv);
    process.stderr.write("csv: " + file + "\n");
  } else {
    process.stdout.write(csv);
  }
  process.stderr.write(text);
}

function invokedDirectly() {
  const arg = process.argv[1];
  if (!arg) return false;
  return import.meta.url === pathToFileURL(path.resolve(arg)).href;
}

if (invokedDirectly()) {
  main().catch(function (err) {
    process.stderr.write((err && err.stack ? err.stack : String(err)) + "\n");
    process.exit(1);
  });
}
