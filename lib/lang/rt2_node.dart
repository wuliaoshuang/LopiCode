/// 规矩版本 2 的小库·Node.js（`lc2.js`）。规矩见 docs/blocks-v5-parts/B-type-system.md 第 2、5、8、11 节。
///
/// 值在 JS 里的样子：整数、小数＝number；文字＝string；是否＝boolean；空＝null；列表＝Array；字典＝Map（键是文字，
/// 遍历按码点从小到大）；记录 / 变体 / 枚举 / 对象＝生成的 class（分别继承 Rec / Variant / Enum / Obj）；函数＝function。
library;

import 'package:lopicode/lang/rt2_js.dart';
import 'package:lopicode/lang/rt2_node_task.dart';

const String kRt2NodeSource =
    r'''
// LopiCode 积木的小库（Node.js，严格规矩）。由 LopiCode 生成，别手改。
"use strict";
''' +
    kRt2JsValues +
    r'''
// —— 输出：写一行就马上写出去（服务被关掉的时候不会丢）——
let wrote = false;
const log = (s) => { wrote = true; process.stdout.write(s + "\n"); };

''' +
    kRt2JsMore +
    r'''
// —— 宿主（清单见 host_v2.dart）——
function hostPrint(s, ch) {
  if (ch === "out") log(s);
  else if (ch === "err") process.stderr.write(s + "\n");
  else fail("通道只能是 out 或 err");
}
const hostNow = () => Date.now();
const copyVal = (v) => (Array.isArray(v) ? v.map(copyVal) : v instanceof Map ? new Map([...v].map(([k, x]) => [k, copyVal(x)])) : v);
const store = new Map();
const storeBusy = new Set();
const storeRead = (name) => (store.has(name) ? copyVal(store.get(name)) : null);
// Node 只有一条线，改格子的函数又不许“等”，所以别人插不进来；函数里再改同一个格子＝报错。
function storeUpdate(name, f) {
  if (storeBusy.has(name)) fail("「" + name + "」这个格子正在改，不能在改它的函数里再改它");
  storeBusy.add(name);
  try {
    const v = copyVal(f(storeRead(name)));
    store.set(name, v);
    return copyVal(v);
  } finally { storeBusy.delete(name); }
}
const hostEnv = (name) => { const v = process.env[name]; return v === undefined ? null : v; };

// —— 随机字节、文件、请求别的网址（细则见 docs/blocks-v5-parts/B-gen-notes.md 第 14 节）——
function hostRandomBytes(n) {
  if (n < 1 || n > 1024) fail("随机字节的个数要在 1 到 1024 之间");
  return Array.from(require("node:crypto").randomBytes(n));
}
const fs = require("node:fs"), nodePath = require("node:path");
function filePath(p) {
  if (p === "" || /^[\/\\]/.test(p) || /^[A-Za-z]:/.test(p) || p.split(/[\/\\]/).includes("..")) fail("路径不对：只能用工程文件夹里面的相对路径");
  return nodePath.join(process.cwd(), p);
}
function fileRead(p) {
  const full = filePath(p);
  let bytes;
  try { bytes = fs.readFileSync(full); } catch (e) { return fail(e.code === "ENOENT" ? "读不了文件：没有「" + p + "」" : "读不了文件：「" + p + "」"); }
  try { return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); } catch (e) { return fail("读不了文件：「" + p + "」不是 UTF-8 文字"); }
}
function fileWrite(p, text) {
  const full = filePath(p), tmp = full + ".lctmp" + process.pid;
  try {
    fs.mkdirSync(nodePath.dirname(full), { recursive: true });
    fs.writeFileSync(tmp, text, "utf8");
    fs.renameSync(tmp, full);
  } catch (e) {
    try { fs.unlinkSync(tmp); } catch (e2) { /* 临时文件本来就没写出来 */ }
    fail("写不了文件：「" + p + "」");
  }
}
const fileExists = (p) => fs.existsSync(filePath(p));
function fileList(p) {
  const full = filePath(p);
  try { return fs.readdirSync(full).sort(cmpText); } catch (e) { return fail("列不了文件夹：「" + p + "」"); }
}
function fileRemove(p) {
  const full = filePath(p);
  let ok = false;
  try { ok = fs.statSync(full).isFile(); if (ok) fs.unlinkSync(full); } catch (e) { ok = false; }
  if (!ok) fail("删不了文件：「" + p + "」");
}
// 网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）；# 后面的不发。
function encodeUrl(s) {
  const hash = s.indexOf("#");
  const bytes = Buffer.from(hash < 0 ? s : s.slice(0, hash), "utf8");
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    const ch = String.fromCharCode(bytes[i]);
    const escaped = ch === "%" && i + 2 < bytes.length && /^[0-9A-Fa-f]{2}$/.test(String.fromCharCode(bytes[i + 1], bytes[i + 2]));
    out += escaped || /^[A-Za-z0-9\-._~:\/?\[\]@!$&'()*+,;=]$/.test(ch) ? ch : "%" + bytes[i].toString(16).toUpperCase().padStart(2, "0");
  }
  return out;
}
const FETCH_METHODS = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"];
const FETCH_SKIP = ["host", "content-length", "connection", "expect", "upgrade"];
async function hostFetch(method, url, headers, body, timeoutMs) {
  if (lineNow().cancelled) throw cancelErr(); // 被取消了的事，到了要等的地方就停
  if (!/^https?:\/\//i.test(url)) fail("请求不了：网址要以 http:// 或 https:// 开头");
  if (!FETCH_METHODS.includes(method)) fail("请求不了：不认识的方式「" + method + "」");
  if (timeoutMs <= 0) fail("请求不了：超时毫秒要大于 0");
  const hs = [];
  let hasType = false, hasAgent = false;
  for (const k of keys(headers)) {
    const low = k.toLowerCase();
    if (FETCH_SKIP.includes(low)) continue;
    hasType = hasType || low === "content-type";
    hasAgent = hasAgent || low === "user-agent";
    hs.push([k, headers.get(k)]);
  }
  const init = { method, headers: hs, redirect: "follow", signal: AbortSignal.timeout(timeoutMs) };
  if (!hasAgent) hs.push(["User-Agent", "LopiCode"]);
  if (body !== null && method !== "GET" && method !== "HEAD") {
    init.body = Buffer.from(body, "utf8");
    if (!hasType) hs.push(["Content-Type", "text/plain; charset=utf-8"]);
  }
  let res, bytes;
  try {
    res = await fetch(encodeUrl(url), init);
    bytes = await res.arrayBuffer();
  } catch (e) {
    return fail(e && (e.name === "TimeoutError" || e.name === "AbortError") ? "请求超时了" : "请求不了：连不上");
  }
  const back = new Map();
  res.headers.forEach((v, k) => back.set(k.toLowerCase(), v));
  return new Map([["status", res.status], ["headers", back], ["body", new TextDecoder("utf-8", { ignoreBOM: true }).decode(bytes)]]);
}

''' +
    kRt2NodeTask +
    r'''
// —— 开服务（细则见 docs/blocks-v5-parts/C-library-system.md 9.1 和 B-gen-notes.md 第 12 节）——
const BODY_LIMIT = 1048576;
const errText = (e) => (e instanceof LcError ? "出错：" + e.message : String((e && e.stack) || e));
function writeRaw(req, res, status, headers, text) {
  const bytes = Buffer.from(text, "utf8");
  const noBody = status === 204 || status === 304 || status < 200;
  const list = [];
  for (const k of keys(headers)) if (k.toLowerCase() !== "content-length") list.push([k, dtext(headers.get(k))]);
  if (!noBody) list.push(["Content-Length", String(bytes.length)]);
  res.writeHead(status, list);
  res.end(noBody || req.method === "HEAD" ? undefined : bytes);
}
const hostError = (req, res, status, message) =>
  writeRaw(req, res, status, new Map([["Content-Type", "application/json; charset=utf-8"]]), toJson(new Map([["error", message]])));
async function serveOne(req, res, handler) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total <= BODY_LIMIT) chunks.push(chunk);
  }
  if (total > BODY_LIMIT) return hostError(req, res, 413, "请求内容太大");
  let body;
  try { body = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(Buffer.concat(chunks)); } catch (e) { body = null; }
  const headers = new Map();
  for (let i = 0; i + 1 < req.rawHeaders.length; i += 2) {
    const name = req.rawHeaders[i].toLowerCase();
    const value = req.rawHeaders[i + 1].replace(/^[ \t]+|[ \t]+$/g, "");
    headers.set(name, headers.has(name) ? headers.get(name) + ", " + value : value);
  }
  const url = req.url || "/";
  const q = url.indexOf("?");
  const request = new Map([["method", req.method], ["path", q < 0 ? url : url.slice(0, q)], ["query", q < 0 ? "" : url.slice(q + 1)], ["headers", headers], ["body", body]]);
  let out;
  try { out = await inLine(() => handler(request)); } catch (e) {
    process.stderr.write(errText(e) + "\n");
    return hostError(req, res, 500, "服务器内部出错");
  }
  const status = out instanceof Map ? out.get("status") : null;
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    process.stderr.write("处理函数返回的响应不对（要一个字典，status 是 100 到 599 的整数）\n");
    return hostError(req, res, 500, "服务器内部出错");
  }
  const hs = out.get("headers");
  return writeRaw(req, res, status, hs instanceof Map ? hs : new Map(), dtext(out.get("body")));
}
// 一直服务，不返回；端口用不了＝出错。
function hostServe(port, host, handler) {
  return new Promise((done, bad) => {
    if (port < 0 || port > 65535) return bad(new LcError("开不了服务：端口要在 0 到 65535 之间"));
    const server = require("node:http").createServer((req, res) => {
      serveOne(req, res, handler).catch((e) => {
        process.stderr.write(errText(e) + "\n");
        if (!res.headersSent) hostError(req, res, 500, "服务器内部出错");
        else res.destroy();
      });
    });
    server.on("error", () => bad(new LcError("开不了服务：" + host + ":" + port + " 用不了")));
    server.listen(port, host, () => log("后端已启动：http://" + host + ":" + server.address().port));
  });
}

function fatal(e) {
  if (!(e instanceof LcError)) throw e;
  log("出错：" + e.message);
  process.exitCode = 1;
}
// 跑主程序。什么都没写过的，最后补一个空行（和原来“攒到最后一次写”的样子一样）。
// 主程序做完＝整个程序结束：“开始做”了还没做完的事不再等（别的语言也是这样）；先等写出去的字都落了地再退。
const finish = () => { process.stdout.write(wrote ? "" : "\n", () => process.exit()); };
function run(main) {
  let r;
  try { r = main(); } catch (e) {
    try { fatal(e); } finally { finish(); }
    return;
  }
  if (r instanceof Promise) r.then(finish, (e) => { try { fatal(e); } finally { finish(); } });
  else finish();
}

module.exports = {
  LcError, errKind, errSetup, errObj, kindOf, Rec, Variant, Enum, Obj, MAX, fail, fmtNum, itext, boolText,
  iadd, isub, imul, imod, idiv, fdiv, fpow, toInt, floor, ceil, round, sqrt, now, steps, fsteps,
  textLen, cmpText, substring, charAt, codePoints, split, startsWith, endsWith, contains, indexOf, replace, trim, upper, lower,
  repeatText, parseInt: parseInt_,
  kind, asNum, asInt, asText, asBool, asFn, asList, asDict, asOpt, asA, isKind, asKind, widenOpt, asListOf, asDictOf, toDyn,
  eq, cmp, dcmp, at, setAt, push, pop, len, items, keys, get, dictSet, dictRemove, dictKeys, dictValues, dictHas, must,
  listMap, listFilter, listReduce, listFind, listEvery, listSome, listEach, listJoin, listReverse, listConcat, listSlice,
  listIndexOf, listContains, range, recCopy,
  abs, max, min, random, copy, template, toBool, listInsert, listRemove, listSort, dictPairs,
  dadd, dsub, dmul, ddiv, dpow, didiv, dmod, dynGet, dynSet, dynPush, dynPop, dynRemove, dynOrElse, dynSize,
  toJson, fromJson, dtext, log, run, isNumeric, isType, dictMerge, toNumber, urlDecode,
  hostPrint, hostNow, hostEnv, hostSleep, hostServe, spawn, wait, awaitMax, awaitAll, awaitAny, cancel, cancelled, lockEnter, lockLeave,
  storeRead, storeUpdate,
  hostRandomBytes, hostFetch, fileRead, fileWrite, fileExists, fileList, fileRemove,
};
''';
